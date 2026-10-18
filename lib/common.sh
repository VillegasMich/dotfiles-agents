# Shared helpers for install.sh and capture.sh. Sourced, not executed.
# Bash 3.2 compatible (stock macOS bash): no associative arrays, no mapfile.

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

AGENTS_HOME="$HOME/.agents"
CLAUDE_HOME="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
CODEX_HOME="${CODEX_HOME:-$HOME/.codex}"
OPENCODE_HOME="${XDG_CONFIG_HOME:-$HOME/.config}/opencode"

SKILL_LOCK="$AGENTS_HOME/.skill-lock.json"

# Agents that get a symlink to each skill. Codex, Cursor, Gemini, Copilot and other
# .agents/skills-compatible agents read ~/.agents/skills directly and need no entry.
SKILL_AGENTS="${SKILL_AGENTS:-claude-code opencode}"
# Pinned for reproducible installs; override with SKILLS_CLI=skills@latest.
SKILLS_CLI="${SKILLS_CLI:-skills@1.7.0}"
# Keys of ~/.claude/settings.json that are machine- or tool-generated and never synced.
CLAUDE_SETTINGS_EXCLUDE="${CLAUDE_SETTINGS_EXCLUDE:-hooks}"
# Skill sources matching this regex are filed under skills/work.txt by capture.sh.
WORK_SOURCES="${WORK_SOURCES:-geniussports}"

DRY_RUN=0

if [ -t 1 ]; then
  C_BOLD=$'\033[1m' C_DIM=$'\033[2m' C_GREEN=$'\033[32m' C_YELLOW=$'\033[33m' C_RED=$'\033[31m' C_RESET=$'\033[0m'
else
  C_BOLD='' C_DIM='' C_GREEN='' C_YELLOW='' C_RED='' C_RESET=''
fi

step() { printf '\n%s==> %s%s\n' "$C_BOLD" "$*" "$C_RESET"; }
info() { printf '  %s\n' "$*"; }
ok()   { printf '  %s✓%s %s\n' "$C_GREEN" "$C_RESET" "$*"; }
warn() { printf '  %s!%s %s\n' "$C_YELLOW" "$C_RESET" "$*" >&2; }
die()  { printf '%serror:%s %s\n' "$C_RED" "$C_RESET" "$*" >&2; exit 1; }

have() { command -v "$1" >/dev/null 2>&1; }

# Print and run a command, or only print it with --dry-run.
run() {
  printf '  %s$ %s%s\n' "$C_DIM" "$*" "$C_RESET"
  [ "$DRY_RUN" = 1 ] || "$@"
}

expand_home() {
  case "$1" in
    "~") printf '%s\n' "$HOME" ;;
    "~/"*) printf '%s/%s\n' "$HOME" "${1#\~/}" ;;
    *) printf '%s\n' "$1" ;;
  esac
}

# dot.toml entries as "<repo path>\t<absolute target>" lines.
dot_entries() {
  awk -F'=' '
    /^[[:space:]]*(#|$)/ { next }
    {
      src = $1; dst = substr($0, index($0, "=") + 1)
      gsub(/^[[:space:]"]+|[[:space:]"]+$/, "", src)
      gsub(/^[[:space:]"]+|[[:space:]"]+$/, "", dst)
      print src "\t" dst
    }' "$REPO_DIR/dot.toml" |
    while IFS=$'\t' read -r src dst; do
      printf '%s\t%s\n' "$src" "$(expand_home "$dst")"
    done
}

# Skill manifest lines as "<name>\t<source>", comments and blanks dropped.
manifest_entries() {
  [ -f "$1" ] || return 0
  awk '!/^[[:space:]]*(#|$)/ { print $1 "\t" $2 }' "$1"
}

# Top-level (before the first [table]) keys of a TOML file as "<key>\t<raw value>".
toml_top_keys() {
  [ -f "$1" ] || return 0
  awk '
    /^[[:space:]]*\[/ { exit }
    /^[[:space:]]*(#|$)/ { next }
    /=/ {
      key = substr($0, 1, index($0, "=") - 1); val = substr($0, index($0, "=") + 1)
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", key); gsub(/^[[:space:]]+|[[:space:]]+$/, "", val)
      print key "\t" val
    }' "$1"
}

# Set a top-level TOML key in place, replacing it or inserting it before the first table.
toml_set_top_key() {
  local file="$1" key="$2" value="$3" tmp
  tmp="$(mktemp)"
  awk -v key="$key" -v line="$key = $value" '
    BEGIN { done = 0; in_table = 0 }
    /^[[:space:]]*\[/ && !in_table { if (!done) { print line; print ""; done = 1 } in_table = 1 }
    !in_table && $0 ~ "^[[:space:]]*" key "[[:space:]]*=" { if (!done) { print line; done = 1 } next }
    { print }
    END { if (!done) print line }' "$file" >"$tmp"
  cat "$tmp" >"$file" && rm -f "$tmp"
}
