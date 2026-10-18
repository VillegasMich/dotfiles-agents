# Claude Code

## Settings: `claude/settings.json`

`~/.claude/settings.json` mixes two kinds of content:

- **My preferences**: model, effort levels, status line, TUI mode, enabled plugins, marketplaces.
  These are portable and live in `claude/settings.json`.
- **Content tools write**: currently the `hooks` block (about 40 KB) that Orca installs for its
  agent status integration, and anything else a tool or `/config` adds later.

It isn't symlinked, because Claude Code and Orca rewrite the file and would replace the link
with a regular file. The two scripts merge it instead:

| Script | Does |
|---|---|
| `install.sh` (step `claude`) | `jq -s '.[0] * .[1]' live repo` deep merge. Repo values win, keys that only exist locally (e.g. `hooks`) are kept. The previous file is saved as `settings.json.backup-<ts>`. Prints a diff first |
| `capture.sh` | Copies the live file minus `CLAUDE_SETTINGS_EXCLUDE` keys (default `hooks`) into the repo. Prints a diff |

So a setting changed through `/config` or `/model` stays local until you run `capture.sh`.

To keep another key local-only, add it to the exclude list, for example in your shell profile:

```sh
export CLAUDE_SETTINGS_EXCLUDE="hooks permissions"
```

Then remove that key from `claude/settings.json`.

A deep merge can only add or change keys, never delete them. To remove a setting everywhere,
delete it from `claude/settings.json` **and** from `~/.claude/settings.json` on each machine
(or run `/config` there).

`~/.claude/settings.local.json` holds machine-specific permission grants and isn't synced.

## Plugins

Plugins are declared in `claude/settings.json`:

```json
"enabledPlugins": {
  "rust-analyzer-lsp@claude-plugins-official": true,
  "statuspane@claude-statuspane": true
},
"extraKnownMarketplaces": {
  "claude-statuspane": { "source": { "source": "github", "repo": "xuanji86/claude-statuspane" } }
}
```

The `plugins` step of `install.sh`:

1. Adds each marketplace that's missing (`claude plugin marketplace add <repo>`), plus
   `anthropics/claude-plugins-official`.
2. Installs each enabled plugin that's missing (`claude plugin install <id> --scope user`).

To add a plugin, install it normally (`/plugin` or `claude plugin install …`), then run
`./capture.sh`. That writes the new `enabledPlugins` entry, and the marketplace if it's a new one.

Some plugins need tools on the machine: `rust-analyzer-lsp` needs `rust-analyzer`, and
`swift-lsp` needs `sourcekit-lsp` (Xcode on macOS, the Swift toolchain on Linux). Without them
the plugin installs but stays inactive.

## Status line

`claude/statusline-command.sh` is symlinked to `~/.claude/statusline-command.sh` and referenced
from `statusLine` in the settings. It needs `jq`. Edit it in either place; both are the same file.

## Global instructions (`CLAUDE.md`)

There isn't one yet. To start syncing one:

```sh
$EDITOR ~/dotfiles-agents/claude/CLAUDE.md
echo '"claude/CLAUDE.md" = "~/.claude/CLAUDE.md"' >> ~/dotfiles-agents/dot.toml
./install.sh --only links
```

The same pattern works for any other hand-written file, such as custom agents in
`~/.claude/agents/` or commands in `~/.claude/commands/`. Link the whole folder with one
`dot.toml` line.
