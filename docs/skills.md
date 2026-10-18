# Skills

A skill is a folder with a `SKILL.md` (plus optional scripts and references) that an agent loads
when a task matches its description. All my agents share one canonical location:

```
~/.agents/skills/<name>/            canonical copy, read directly by Codex, opencode, Cursor, Gemini, …
~/.claude/skills/<name>  ──symlink──▶ ../../.agents/skills/<name>     (Claude Code needs a link)
```

Skills come from three places, and each is synced differently.

## 1. Skills from a repo: `skills/personal.txt` and `skills/work.txt`

These are installed with the [`skills` CLI](https://github.com/vercel-labs/skills), which records
each one in `~/.agents/.skill-lock.json`. The repo keeps only the name and source:

```
# <skill name>                                 <source>
caveman                                        JuliusBrussee/caveman
architecture-decision-record-skill             architecture-decision-record/architecture-decision-record
```

`<source>` is anything `skills add` accepts: a GitHub `owner/repo`, a full git URL
(`git@gitlab.com:group/repo.git`) or a local path. `install.sh` groups lines by source and runs
one command for each:

```sh
npx -y skills@1.7.0 add <source> -g -y -s <name> [<name> …] -a claude-code opencode
```

- **personal.txt**: installed on every machine.
- **work.txt**: installed only with `./install.sh --work`. These sources are on the work GitLab
  and fail without access.

### Add a skill

Either install it and capture it:

```sh
npx skills add owner/repo -g            # pick the skill(s) interactively
./capture.sh                            # appends the new skill(s) to personal.txt or work.txt
git diff skills/
```

or add the line to the manifest by hand and run `./install.sh --only skills`.

To see which skills a repo provides: `npx skills add owner/repo --list`.

### Remove a skill

```sh
npx skills remove <name> -g -y
# then delete its line from personal.txt / work.txt
```

If you skip the second step, `capture.sh` warns that the skill is listed but not installed, and
`install.sh` reinstalls it on the next run.

### Update skills

```sh
./install.sh --update --only skills     # = npx skills update -g -y (+ twg skills refresh with --work)
```

The manifests don't pin versions, so a fresh machine always gets the latest. The pinned version
is only the CLI's (`SKILLS_CLI`).

## 2. TWG skills (`twg-*`)

These come from the Atlassian TWG CLI, not the skills CLI, and aren't listed in any manifest.
With `--work`, `install.sh` runs:

```sh
twg skills install -y --agent claude --agent opencode
```

if `twg` is installed and the skills aren't there yet. `twg upgrade` keeps them current on its own.

## 3. My own skills: `skills/own/<name>/`

Skills I write myself are stored in the repo and **symlinked**, so editing them in place edits
the repo:

```
~/.agents/skills/<name>  ──▶ ~/dotfiles-agents/skills/own/<name>
~/.claude/skills/<name>  ──▶ ~/dotfiles-agents/skills/own/<name>
```

### Create one

```sh
cd ~/dotfiles-agents/skills/own
npx skills init my-skill                # or write my-skill/SKILL.md by hand
cd ../.. && ./install.sh --only own
```

`SKILL.md` needs at least this frontmatter:

```markdown
---
name: my-skill
description: What it does and when to use it. Agents decide when to load it from this text.
---
```

In Claude Code, `/skill-creator` helps write and test one.

### Move an existing local skill into the repo

`capture.sh` lists folders in `~/.agents/skills` that the skills CLI doesn't know about, which are
probably skills written on that machine. To start syncing one:

```sh
mv ~/.agents/skills/my-skill ~/dotfiles-agents/skills/own/
rm -f ~/.claude/skills/my-skill         # old link, if any
./install.sh --only own
```

## Which agents get links

`SKILL_AGENTS` (default `claude-code opencode`) is passed to `skills add -a`. The CLI treats
opencode and Codex as "universal": they read `~/.agents/skills` directly, so they get no extra
link. Claude Code and Cursor need their own links, which `install.sh` checks for. To add Cursor:

```sh
SKILL_AGENTS="claude-code opencode cursor" ./install.sh --only skills,own
```
