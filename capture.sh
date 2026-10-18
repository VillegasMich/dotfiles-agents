#!/usr/bin/env bash
# Copy this machine's current agent setup back into the repo: new skills, changed Claude Code
# and Codex settings, and linked files that were replaced by a regular file. It never commits;
# review the result with `git diff`.
#
# Usage: ./capture.sh [--dry-run]
set -euo pipefail

source "$(dirname "$0")/lib/common.sh"

case "${1:-}" in
  --dry-run) DRY_RUN=1 ;;
  -h | --help) sed -n '2,6p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
  "") ;;
  *) die "unknown option: $1" ;;
esac

have jq || die "jq is required"

[ "$DRY_RUN" = 1 ] && printf '%sDry run: nothing will be changed.%s\n' "$C_YELLOW" "$C_RESET"

# ---------------------------------------------------------------------------------------

step "Linked files"
while IFS=$'\t' read -r src dst <&3; do
  if [ -L "$dst" ]; then
    ok "$dst is linked"
  elif [ -f "$dst" ]; then
    if cmp -s "$REPO_DIR/$src" "$dst"; then
      ok "$dst matches the repo (not linked yet; install.sh links it)"
    else
      # Some tools replace a symlink with a regular file when they save; keep their edits.
      info "$dst was edited outside the repo"
      run cp "$dst" "$REPO_DIR/$src"
    fi
  else
    info "$dst not present on this machine"
  fi
done 3< <(dot_entries)

# ---------------------------------------------------------------------------------------

step "Skills"
tracked="$(manifest_entries "$REPO_DIR/skills/personal.txt"; manifest_entries "$REPO_DIR/skills/work.txt")"
is_tracked() { printf '%s\n' "$tracked" | awk -F'\t' -v n="$1" '$1 == n { f = 1 } END { exit !f }'; }

if [ -f "$SKILL_LOCK" ]; then
  installed="$(jq -r '.skills // {} | to_entries[] | "\(.key)\t\(.value.source)"' "$SKILL_LOCK")"
else
  installed=""
  warn "$SKILL_LOCK not found; no skills installed with the skills CLI"
fi

new=0
while IFS=$'\t' read -r name src <&3; do
  [ -n "$name" ] || continue
  is_tracked "$name" && continue
  if printf '%s' "$src" | grep -Eq "$WORK_SOURCES"; then target=work.txt; else target=personal.txt; fi
  info "new skill $name ($src) -> skills/$target"
  [ "$DRY_RUN" = 1 ] || printf '%-46s %s\n' "$name" "$src" >>"$REPO_DIR/skills/$target"
  new=1
done 3< <(printf '%s\n' "$installed")
[ "$new" = 1 ] || ok "every installed skill is already in a manifest"

for manifest in personal.txt work.txt; do
  while IFS=$'\t' read -r name src <&3; do
    printf '%s\n' "$installed" | awk -F'\t' -v n="$name" '$1 == n { f = 1 } END { exit !f }' && continue
    if [ "$manifest" = work.txt ]; then
      info "$name (work) is not installed here; fine on a personal machine"
    else
      warn "$name is in skills/personal.txt but not installed here (delete its line if you removed it on purpose)"
    fi
  done 3< <(manifest_entries "$REPO_DIR/skills/$manifest")
done

# Skill folders the CLI does not know about: probably written by hand on this machine.
if [ -d "$AGENTS_HOME/skills" ]; then
  for dir in "$AGENTS_HOME"/skills/*/; do
    [ -d "$dir" ] || continue
    dir="${dir%/}"
    name="$(basename "$dir")"
    case "$name" in twg | twg-*) continue ;; esac
    [ -L "$dir" ] && continue
    printf '%s\n' "$installed" | awk -F'\t' -v n="$name" '$1 == n { f = 1 } END { exit !f }' && continue
    warn "$dir is not from the skills CLI; to sync it: mv \"$dir\" \"$REPO_DIR/skills/own/\" && ./install.sh --only own"
  done
fi

# ---------------------------------------------------------------------------------------

step "Claude Code settings"
live="$CLAUDE_HOME/settings.json"
repo="$REPO_DIR/claude/settings.json"
if [ -f "$live" ]; then
  captured="$(jq --arg ex "$CLAUDE_SETTINGS_EXCLUDE" \
    '($ex | split(" ")) as $x | with_entries(select(.key as $k | $x | index($k) | not))' "$live")"
  if [ "$(jq -S . "$repo")" = "$(printf '%s' "$captured" | jq -S .)" ]; then
    ok "claude/settings.json is up to date"
  else
    diff <(jq -S . "$repo") <(printf '%s' "$captured" | jq -S .) | sed 's/^/    /' || true
    if [ "$DRY_RUN" = 1 ]; then
      info "would update claude/settings.json"
    else
      printf '%s\n' "$captured" >"$repo"
      ok "updated claude/settings.json (excluded keys: $CLAUDE_SETTINGS_EXCLUDE)"
    fi
  fi
else
  info "$live not found"
fi

# ---------------------------------------------------------------------------------------

step "Codex settings"
live="$CODEX_HOME/config.toml"
if [ -f "$live" ]; then
  changed=0
  # Only keys already listed in codex/config.toml are captured.
  while IFS=$'\t' read -r key value <&3; do
    current="$(toml_top_keys "$live" | awk -F'\t' -v k="$key" '$1 == k { print $2 }')"
    [ -n "$current" ] && [ "$current" != "$value" ] || continue
    info "$key: $value -> $current"
    run toml_set_top_key "$REPO_DIR/codex/config.toml" "$key" "$current"
    changed=1
  done 3< <(toml_top_keys "$REPO_DIR/codex/config.toml")
  [ "$changed" = 1 ] || ok "codex/config.toml is up to date"
else
  info "$live not found"
fi

step "Done"
info "Review the changes with: git -C \"$REPO_DIR\" diff"
