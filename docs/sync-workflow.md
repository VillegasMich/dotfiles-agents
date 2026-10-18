# Sync workflow

## The loop

```sh
# on the machine where something changed
cd ~/dotfiles-agents
./capture.sh            # machine → repo
git diff                # review
git commit -am "Add X skill" && git push

# on every other machine
cd ~/dotfiles-agents
git pull
./install.sh            # repo → machine   (--work on work machines)
```

Both scripts accept `--dry-run`. Run it first when you're unsure what will change.

### What `capture.sh` does

| Section | Action |
|---|---|
| Linked files | If a `dot.toml` target is now a regular file that differs from the repo copy (a tool replaced the symlink when saving), copies it into the repo |
| Skills | Adds skills from `~/.agents/.skill-lock.json` that aren't in a manifest yet: to `work.txt` if the source matches `WORK_SOURCES`, otherwise to `personal.txt`. Warns about listed skills that aren't installed, and about hand-made skill folders that could go in `skills/own/` |
| Claude settings | Writes `~/.claude/settings.json` minus excluded keys to `claude/settings.json` |
| Codex settings | Updates the keys listed in `codex/config.toml` from `~/.codex/config.toml` |

It only edits files inside the repo. Commit them yourself.

### What `install.sh` does

| Step | Action |
|---|---|
| `links` | Removes targets that are exact copies of the repo file, backs up targets that differ, then runs `dot sync` (or `ln -s` without `dot`) |
| `skills` | Installs manifest skills that are missing or not linked for an agent. With `--work`, also the work list and `twg-*`. With `--update`, updates them all |
| `own` | Symlinks every `skills/own/<name>/` into `~/.agents/skills` and the Claude skills folder |
| `claude` | Deep-merges `claude/settings.json` into `~/.claude/settings.json` (backup first) |
| `plugins` | Adds missing marketplaces and installs missing plugins |
| `codex` | Sets the top-level keys from `codex/config.toml` in `~/.codex/config.toml` |

## New machine

**macOS**: run `dotfiles-macos/bootstrap.sh` first, since it installs Homebrew, Node, Rust/`dot`,
Claude Code and Codex. Then:

```sh
git clone git@github.com:VillegasMich/dotfiles-agents.git ~/dotfiles-agents
~/dotfiles-agents/install.sh            # or --work
```

**Linux**:

```sh
sudo apt install -y git jq curl
curl -fsSL https://fnm.vercel.app/install | bash && fnm install --lts   # Node for npx
curl -fsSL https://claude.ai/install.sh | bash                           # Claude Code
# optional: cargo install dot_rust; npm i -g @openai/codex

git clone git@github.com:VillegasMich/dotfiles-agents.git ~/dotfiles-agents
~/dotfiles-agents/install.sh
```

Then log in to each tool (`claude`, `codex login`, `twg login`). Credentials are never synced.

## Troubleshooting

**"exists but is not a symlink — skipping" from `dot`.** Something recreated the file. Run
`./capture.sh` to keep its contents, then `./install.sh --only links`.

**A `*.backup-<timestamp>` file appeared.** `install.sh` moved a file it was about to replace.
Compare it with the new one, then delete it.

**`skills add` fails for a work source.** You don't have access to the work GitLab from this
machine (SSH key / VPN). Leave out `--work`.

**A skill shows up in Codex/opencode but not Claude Code.** `~/.claude/skills/<name>` link is
missing. `./install.sh --only skills,own` recreates it.

**Settings I changed keep coming back.** `install.sh` applies the repo values. Run
`./capture.sh` after changing a setting, before the next `install.sh`.
