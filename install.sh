#!/usr/bin/env bash
# Apply this repo to the current machine (macOS or Linux): install skills, link hand-written
# files, merge Claude Code / Codex settings and install Claude plugins. Safe to re-run.
#
# Usage: ./install.sh [--work] [--update] [--only <steps>] [--dry-run]
set -euo pipefail

source "$(dirname "$0")/lib/common.sh"

ALL_STEPS="links skills own claude plugins codex"
STEPS="$ALL_STEPS"
WORK=0
UPDATE=0
TS="$(date +%Y%m%d-%H%M%S)"

usage() {
  cat <<EOF
Usage: ./install.sh [options]

Options:
  --work           Also install work skills (skills/work.txt and twg-*)
  --update         Update already-installed skills to their latest version
  --only <steps>   Comma-separated subset of: ${ALL_STEPS// /, }
  --dry-run        Print what would change without changing anything
  -h, --help       Show this help

Environment:
  SKILL_AGENTS     Agents to link skills into (default: "$SKILL_AGENTS")
  SKILLS_CLI       npx package for the skills CLI (default: $SKILLS_CLI)
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    --work) WORK=1 ;;
    --update) UPDATE=1 ;;
    --only) [ $# -ge 2 ] || die "--only needs a value"; STEPS="${2//,/ }"; shift ;;
    --dry-run) DRY_RUN=1 ;;
    -h | --help) usage; exit 0 ;;
    *) usage >&2; die "unknown option: $1" ;;
  esac
  shift
done

for s in $STEPS; do
  case " $ALL_STEPS " in *" $s "*) ;; *) die "unknown step: $s (valid: $ALL_STEPS)" ;; esac
done

want() { case " $STEPS " in *" $1 "*) return 0 ;; *) return 1 ;; esac; }

# Directory where an agent needs its own link to each skill. Empty for "universal" agents
# (opencode, codex, ...) that read ~/.agents/skills directly, and for unknown ones.
agent_skills_dir() {
  case "$1" in
    claude-code) echo "$CLAUDE_HOME/skills" ;;
    cursor) echo "$HOME/.cursor/skills" ;;
  esac
}

# Symlink src to dst, moving aside anything that is not already a symlink.
link_path() {
  local src="$1" dst="$2"
  if [ -L "$dst" ] && [ "$(readlink "$dst")" = "$src" ]; then
    return 0
  fi
  if [ -e "$dst" ] && [ ! -L "$dst" ]; then
    warn "$dst exists; moving it to $dst.backup-$TS"
    run mv "$dst" "$dst.backup-$TS"
  fi
  run mkdir -p "$(dirname "$dst")"
  run ln -sfn "$src" "$dst"
  ok "$dst -> $src"
}

# ---------------------------------------------------------------------------------------

step_links() {
  step "Linking files from dot.toml"
  local src dst
  # dot skips targets that already exist as regular files, so adopt them first: drop exact
  # copies of the repo file, back up anything that differs.
  while IFS=$'\t' read -r src dst <&3; do
    [ -e "$dst" ] && [ ! -L "$dst" ] || continue
    if cmp -s "$REPO_DIR/$src" "$dst"; then
      run rm "$dst"
    else
      warn "$dst differs from the repo copy; moving it to $dst.backup-$TS (run capture.sh first to keep it)"
      run mv "$dst" "$dst.backup-$TS"
    fi
  done 3< <(dot_entries)

  if have dot; then
    (cd "$REPO_DIR" && run dot sync)
  else
    info "dot not found; linking with ln -s"
    while IFS=$'\t' read -r src dst <&3; do
      link_path "$REPO_DIR/$src" "$dst"
    done 3< <(dot_entries)
  fi
}

step_skills() {
  step "Installing skills"
  if ! have npx || ! have git; then
    warn "npx (Node.js) and git are required for skills; skipping"
    return 0
  fi

  local manifests="$REPO_DIR/skills/personal.txt"
  [ "$WORK" = 1 ] && manifests="$manifests $REPO_DIR/skills/work.txt"

  # A skill is missing when its canonical copy or any agent's link to it is missing.
  local name src agent dir missing="" m
  for m in $manifests; do
    while IFS=$'\t' read -r name src <&3; do
      if [ ! -e "$AGENTS_HOME/skills/$name" ]; then
        info "$name: not installed"
        missing="$missing$name"$'\t'"$src"$'\n'
        continue
      fi
      for agent in $SKILL_AGENTS; do
        dir="$(agent_skills_dir "$agent")"
        if [ -n "$dir" ] && [ ! -e "$dir/$name" ]; then
          info "$name: not linked for $agent"
          missing="$missing$name"$'\t'"$src"$'\n'
          break
        fi
      done
    done 3< <(manifest_entries "$m")
  done

  if [ -z "$missing" ]; then
    ok "all skills already installed"
  else
    # One `skills add` per source, selecting just the listed skills from it.
    local names
    while IFS=$'\t' read -r src names <&3; do
      # shellcheck disable=SC2086 # names and agents are intentionally word-split
      run npx -y "$SKILLS_CLI" add "$src" -g -y -s $names -a $SKILL_AGENTS </dev/null
    done 3< <(printf '%s' "$missing" | awk -F'\t' 'NF == 2 { s[$2] = s[$2] " " $1 } END { for (k in s) print k "\t" substr(s[k], 2) }')
  fi

  if [ "$UPDATE" = 1 ]; then
    run npx -y "$SKILLS_CLI" update -g -y </dev/null
  fi

  if [ "$WORK" = 1 ]; then
    if ! have twg; then
      warn "twg not found; skipping twg-* skills (install the TWG CLI, then re-run with --work)"
    elif [ -e "$AGENTS_HOME/skills/twg" ] && [ "$UPDATE" = 0 ]; then
      ok "twg-* skills already installed (refresh with --update or 'twg upgrade')"
    else
      run twg skills install -y --agent claude --agent opencode </dev/null
    fi
  fi
}

step_own() {
  step "Linking own skills from skills/own"
  local dir name agent agent_dir found=0
  for dir in "$REPO_DIR"/skills/own/*/; do
    [ -f "$dir/SKILL.md" ] || continue
    found=1
    dir="${dir%/}"
    name="$(basename "$dir")"
    link_path "$dir" "$AGENTS_HOME/skills/$name"
    for agent in $SKILL_AGENTS; do
      agent_dir="$(agent_skills_dir "$agent")"
      [ -n "$agent_dir" ] && link_path "$dir" "$agent_dir/$name"
    done
  done
  [ "$found" = 1 ] || info "no skills in skills/own yet"
}

step_claude() {
  step "Merging Claude Code settings"
  if ! have jq; then
    warn "jq is required to merge settings; skipping"
    return 0
  fi
  local base="$REPO_DIR/claude/settings.json" live="$CLAUDE_HOME/settings.json" merged
  if [ -f "$live" ]; then
    # Deep merge: repo values win, keys only present locally (e.g. hooks) are kept.
    merged="$(jq -s '.[0] * .[1]' "$live" "$base")"
    if [ "$(jq -S . "$live")" = "$(printf '%s' "$merged" | jq -S .)" ]; then
      ok "$live already up to date"
      return 0
    fi
    diff <(jq -S . "$live") <(printf '%s' "$merged" | jq -S .) | sed 's/^/    /' || true
    run cp "$live" "$live.backup-$TS"
  else
    merged="$(jq . "$base")"
    run mkdir -p "$CLAUDE_HOME"
  fi
  if [ "$DRY_RUN" = 1 ]; then
    info "would write $live"
  else
    printf '%s\n' "$merged" >"$live"
    ok "wrote $live"
  fi
}

step_plugins() {
  step "Installing Claude Code plugins"
  if ! have claude || ! have jq; then
    warn "claude and jq are required for plugins; skipping"
    return 0
  fi
  local base="$REPO_DIR/claude/settings.json" known installed name repo id

  known="$(claude plugin marketplace list 2>/dev/null || true)"
  # Marketplaces declared in settings, plus the official one most plugins come from.
  while IFS=$'\t' read -r name repo <&3; do
    [ -n "$repo" ] || continue
    if printf '%s' "$known" | grep -qF "$name"; then
      ok "marketplace $name"
    else
      run claude plugin marketplace add "$repo" </dev/null
    fi
  done 3< <(
    printf 'claude-plugins-official\tanthropics/claude-plugins-official\n'
    jq -r '.extraKnownMarketplaces // {} | to_entries[] | "\(.key)\t\(.value.source.repo // .value.source.url // "")"' "$base"
  )

  installed="$(claude plugin list 2>/dev/null || true)"
  while read -r id <&3; do
    if printf '%s' "$installed" | grep -qF "$id"; then
      ok "plugin $id"
    else
      run claude plugin install "$id" --scope user </dev/null
    fi
  done 3< <(jq -r '.enabledPlugins // {} | to_entries[] | select(.value == true) | .key' "$base")
}

step_codex() {
  step "Merging Codex settings"
  if [ ! -d "$CODEX_HOME" ] && ! have codex; then
    info "Codex not installed; skipping"
    return 0
  fi
  local live="$CODEX_HOME/config.toml" key value current changed=0
  if [ ! -f "$live" ]; then
    run mkdir -p "$CODEX_HOME"
    run touch "$live"
  fi
  while IFS=$'\t' read -r key value <&3; do
    current="$(toml_top_keys "$live" | awk -F'\t' -v k="$key" '$1 == k { print $2 }')"
    [ "$current" = "$value" ] && continue
    run toml_set_top_key "$live" "$key" "$value"
    changed=1
  done 3< <(toml_top_keys "$REPO_DIR/codex/config.toml")
  [ "$changed" = 1 ] && ok "updated $live" || ok "$live already up to date"
}

# ---------------------------------------------------------------------------------------

[ "$DRY_RUN" = 1 ] && printf '%sDry run: nothing will be changed.%s\n' "$C_YELLOW" "$C_RESET"

want links && step_links
want skills && step_skills
want own && step_own
want claude && step_claude
want plugins && step_plugins
want codex && step_codex

step "Done"
info "Restart Claude Code, Codex and opencode so they pick up new skills and settings."
