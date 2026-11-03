---
name: orca-features
description: >-
  Design and build features or bug fixes with Matt Pocock's engineering flow,
  then implement them in parallel with one supervised Orca agent per ticket,
  each in its own branch + worktree. The current session is the coordinator:
  grills the user (grilling + domain-modeling, leaving GLOSSARY/ADRs), turns
  the result into a spec and tracer-bullet tickets when the work is big
  enough, spawns workers via `orca orchestration` that build test-first and
  self-review, relays every implementation doubt to the user, verifies each
  branch, and after explicit user approval opens the PRs and merges them into
  the target branch (default branch unless told otherwise). Works in any git
  repo; project conventions come from its CLAUDE.md / AGENTS.md. Use when the
  user says "start a feature", "new features with orca", "spawn agents per
  feature", "grill then build with orca", "/orca-features", or lists several
  features or fixes to build in parallel.
---

# Orca features — coordinator workflow

You are the **coordinator**. You never implement feature code yourself; workers
do. You own: designing with the user (Matt Pocock flow), briefs, answering/relaying
questions, independent verification, PRs and merges.

Hard gates (never skip):

1. **Plan gate** — user approves the ticket list + design decisions before any worker starts.
2. **Doubt gate** — a worker question that is a design/behavior choice goes to the user, not answered by you.
3. **Merge gate** — no push, PR, or merge until the user explicitly approves *that* ticket after verification.

Unit of work: **1 ticket = 1 worker = 1 branch/worktree = 1 PR** into the target.
Blocking edges between tickets become **waves**: a blocked ticket starts only after
every blocker is merged, based on the updated target.

## 0. Resolve the Orca CLI, load its guide, learn the project

- `ORCA_CLI_COMMAND` set → use it. Inside an Orca terminal (`TERM_PROGRAM=Orca`) → `orca`.
  On Linux outside Orca → `orca-ide` (bare `orca` there is the GNOME screen reader).
- Run `orca status --json`. If not running: `orca open --json`.
- Run `orca skills get orchestration` and follow it; it is version-matched and wins over
  anything below if they disagree. Load
  `--reference references/placement-and-remote.md` before creating worktrees.
- Must be inside a git repo (`git rev-parse --show-toplevel`); that root is `<repo>`.
- Build the **project profile** from `<repo>/CLAUDE.md`, `AGENTS.md`, `CONTRIBUTING.md`,
  README and CI config (`.github/workflows/*`, `Makefile`, `justfile`, `package.json`
  scripts, `Cargo.toml`, `pyproject.toml`, …). Record:
  - **checks** — format, lint, typecheck, test (and dependency audit) commands CI runs;
  - **read-first docs** and **hard rules** (security, style, "never do X");
  - **domain docs** — `GLOSSARY.md` / `GLOSSARY-MAP.md`, `docs/adr/`;
  - **issue tracker + domain layout** — the `## Agent skills` block in CLAUDE.md /
    AGENTS.md and `docs/agents/*.md`, written by `/setup-matt-pocock-skills`. Missing →
    run the **repo bootstrap** below before designing anything;
  - **dev server** — command, default port, how to override the port;
  - **shared resources** workers must not touch (user's own dev server, real services,
    containers, databases) and how to create throwaway ones;
  - **conventions** — branch prefix (`git branch -r` history, else `<gh login>/<slug>`),
    commit style (`git log --oneline`), PR merge method (`gh repo view --json
    mergeCommitAllowed,squashMergeAllowed,rebaseMergeAllowed`), commit-message rules.
  - A section about parallel agents / orca-features in those files overrides the
    defaults below.
  Anything you cannot determine and that matters → ask the user in step 1.

### Repo bootstrap (first run in a repo only)

The Matt Pocock skills (`to-spec`, `to-tickets`, `code-review`, `triage`, …) read the
repo's tracker and domain-doc config; without it they stall or guess. If the repo has no
`## Agent skills` block:

1. Tell the user this repo isn't set up for the Matt Pocock skills yet and offer to set it
   up now (recommended) or skip.
2. **Set up** → read `~/.agents/skills/setup-matt-pocock-skills/SKILL.md` and follow it
   (it is user-only, so not via the Skill tool): explore, propose the issue tracker
   (GitHub/GitLab from the remote, else local markdown), triage labels, single- vs
   multi-context domain docs, confirm the drafts with the user, then write the
   `## Agent skills` block and `docs/agents/*.md` (plus `GLOSSARY.md` / `docs/adr/`
   when the domain-docs choice creates them).
3. These files go to the target branch through the step 1b docs PR, together with
   whatever the design phase adds, so workers' `code-review` can read them.
4. **Skip** → use local markdown for this run (layout below) and say so in the plan.

Local-markdown layout: spec at `.scratch/<feature-slug>/spec.md`, tickets at
`.scratch/<feature-slug>/issues/<NN>-<slug>.md`, a `Status:` line near the top of each,
comments under `## Comments`.

### Matt Pocock skills: how to run them

Several of them are user-only (`disable-model-invocation`), so the Skill tool refuses them.
Run them like this, never from memory:

| Step | How |
|---|---|
| grill (= `/grill-with-docs`) | Skill tool: `grilling`, then `domain-modeling` |
| prototype | Skill tool: `prototype` |
| research | Skill tool: `research` |
| module shape / seams | Skill tool: `codebase-design` |
| spec (`/to-spec`) | Read `~/.agents/skills/to-spec/SKILL.md` and follow it |
| tickets (`/to-tickets`) | Read `~/.agents/skills/to-tickets/SKILL.md` and follow it |

A file missing under `~/.agents/skills/` → tell the user the skill isn't installed
(`npx skills add mattpocock/skills -g`) and stop that step instead of improvising it.

## 1. Design with the user (ends at the plan gate)

Keep this whole step in **one unbroken context**: no compaction or clearing until the
tickets are approved.

1. **Grill.** Call the Skill tool with `grilling`, then `domain-modeling`, and run the
   interview over everything the user asked for. Rounds, recommended answers and
   "facts are your job, decisions are the user's" come from `grilling`. `domain-modeling`
   updates `GLOSSARY.md` and writes ADRs for hard-to-reverse decisions as you go.
   Look facts up with subagents; never ask the user something the repo can answer.
2. **Prototype detour (only if needed).** If a question can only be settled with
   runnable code (state model, business logic, a UI to look at), call the Skill tool with
   `prototype`, show it to the user, fold the verdict back into the grilling.
   Ask before starting a prototype; it costs a detour.
3. **Choose the path** and confirm it with the user in one question:
   - **Direct** — the work is one or a few small, independent pieces (a bug fix, a
     contained feature), each fitting one worker session. Skip spec and tickets: each
     piece becomes one ticket written by you from the grilling, in the to-tickets
     ticket shape (what to build, blocked by, acceptance criteria), kept in the scratchpad.
   - **Spec** — multi-ticket work or anything with dependencies. Follow `to-spec`
     (it confirms the **test seams** with the user and publishes the spec), then
     `to-tickets` (it quizzes the user on granularity and blocking edges, then
     publishes one ticket per slice). Both publish to the tracker from step 0.
   Several unrelated features in one request → each gets its own path and slug.
4. **Seams.** Workers build with `tdd`, which only tests at **pre-agreed seams**, and
   they cannot ask the user directly. Make sure every ticket has its seams settled
   (from `to-spec`, or ask now on the direct path).
5. **Orca plan.** For each ticket: slug (kebab-case → branch `<prefix>/<slug>`), files
   likely touched, dev port. Detect **overlap**: tickets touching the same files
   (routers, shared JS/CSS, central docs) will conflict at merge — propose ownership
   boundaries or add a blocking edge.
6. Confirm target branch (default: repo default branch, `gh repo view --json defaultBranchRef`),
   agent (default `claude`), and any model/effort override. Batch open questions in
   `AskUserQuestion` (≤4 per call, recommended option first). The user wants to decide
   design together — do not assume.
7. Show the final plan table (slug · ticket ref · goal · port · wave · blocked-by) and
   get an explicit "go".

## 1b. Land the design docs (before any worker starts)

Workers branch from the target, so they only see what is committed there. Check
`git status` for files the bootstrap and design phase produced: the `## Agent skills`
block, `docs/agents/*.md`, `GLOSSARY.md`, new ADRs, and the local spec/tickets if
`.scratch/` is not git-ignored.

- Nothing produced, or only ignored files → skip.
- Otherwise, with the user's approval (merge gate applies), land them first as a small
  docs PR: branch `<prefix>/<feature-slug>-design` off the target, commit in the
  project's style, push, PR, merge, then `git checkout <target> && git pull --ff-only`.
  If the user prefers not to, inline the relevant glossary terms and ADRs into each brief.

Local tickets/spec that stay ignored are still readable by workers through their
**absolute** path in the main checkout; put that path in each brief.

## 2. Write one brief per ticket

Build each brief in the scratchpad from `references/worker-brief.md`, filling every
placeholder from the ticket, the spec, the grilling decisions and the project profile.
Inline the full ticket text and the agreed seams; add a pointer (issue URL/number or
absolute path) to the ticket and spec so the worker's `code-review` can find them.
If the project is Rust (`Cargo.toml`), also inline the full text of
`references/rust-guidelines.md`; for other languages, inline nothing extra unless the
project ships its own guidelines. Workers run in other worktrees and cannot read this
skill folder — inline everything they need. The brief must satisfy the Task-spec
contract: Target, Change, Constraints, Ownership, Observable acceptance.

Per worker, unless the project says otherwise:

- dev port = project default port + 5 + i (never the default port itself — that is the
  user's own server); skip if the project has no dev server.
- throwaway resource prefix `<project>-<slug>-` (containers, temp DBs, etc.).

## 3. Spawn workers

```sh
orca orchestration run-create --objective "Tickets: <slug1>, <slug2>" --json
orca orchestration worker-start \
  --spec "$(cat <scratchpad>/brief-<slug>.md)" \
  --task-title "<slug>" \
  --worktree new-top-level --name <slug> --base-branch <target> \
  --repo path:<repo> --agent claude --setup run --json
```

- Start the whole **frontier** (tickets with no unmerged blockers) before waiting.
  Blocked tickets: start once all their blockers are merged, with `--base-branch` on
  the updated target.
- Record per ticket: ticket ref, task id, dispatch id, terminal handle, worktree path, branch.
- `worker-start` exits non-zero → do **not** relaunch; read `failedStage` /
  `residualResources` and load `references/recovery-and-cleanup.md` from the Orca guide.
- Tell the user which agents are running and where (worktree paths) so they can watch in the Orca app.

## 4. Supervise and relay doubts (doubt gate)

Loop:

```sh
orca orchestration check --wait --types "worker_done,escalation,question" --timeout-ms 900000 --json
```

For every message in the delivery, before `--ack`:

- **question** — classify:
  - Already decided in the grilling, spec, ticket, ADRs or project docs → reply citing
    the source.
  - Anything else (API shape, UX, naming visible to users, a new test seam, new
    dependency, new config/env var, scope change, trade-off) → `AskUserQuestion` to the
    user, prefixed with the slug, with the worker's options + your recommendation.
    Reply with the user's answer verbatim plus any context:
    `orca orchestration reply --id <message_id> --body "..." --json`.
    A decision that changes the design → also record it (ADR / glossary / ticket
    comment) so later waves inherit it.
  - Several questions pending at once → batch them in one `AskUserQuestion` call.
- **escalation** — summarize to the user, ask how to proceed.
- **worker_done** — validate it matches the active dispatch, then go to step 5 for that
  ticket. Do **not** release the worker yet (it may need follow-ups).

Timeouts/empty waits are checkpoints. After 3 empty waits run
`orca orchestration worker-list --run <run_id> --json` and act on `projection.nextAction`.
Never stop/abandon a worker without positive proof it exited.

## 5. Verify each finished branch yourself

In the worker's worktree (don't trust the summary alone):

```sh
git -C <wt> log --oneline <target>..HEAD
git -C <wt> status --short                       # must be clean
cd <wt> && <every check command from the project profile>
```

Also check: every acceptance criterion of the ticket is met, tests sit at the agreed
seams and test behavior (not internals), the worker's `code-review` findings were
addressed, the project's hard rules respected, docs/ADRs updated in the same branch
when a documented decision changed, roadmap/changelog ticked if the project keeps one,
commit style matches. For UI changes, take a screenshot on the worker's port (headless
browser, per the project's testing notes if any) and show it to the user.

Problems → send a follow-up to the **same terminal** as a new dispatch:

```sh
orca orchestration worker-start --spec "<fix list>" --terminal <handle> --worktree <selector> --json
```

## 6. User review (merge gate)

Present per ticket: commits, `git diff --stat <target>...<branch>`, check results,
code-review summary, screenshot if UI, deviations from the ticket, and how to try it
(exact command with the worker's port, from the brief).
Ask the user to approve, request changes (→ step 5 follow-up loop), or drop it.
Approval of one ticket does not approve the others.

## 7. PRs and merge (only approved tickets)

Merge order: blockers first, then smallest/least-overlapping first. For each:

```sh
git -C <wt> fetch origin
git -C <wt> merge origin/<target>   # only if behind; resolve conflicts, re-run step 5 checks
git -C <wt> push -u origin <branch>
gh pr create --base <target> --head <branch> --title "<commit-style title>" --body-file <scratchpad>/pr-<slug>.md
gh pr checks <pr> --watch            # CI must be green (skip if the repo has no CI)
gh pr merge <pr> --<merge|squash|rebase>   # the repo's method from the profile
```

PR body: write it with the `pr` skill (Skill tool) if installed. It must also carry:
Testing (exact commands + results), Screenshots if UI, decisions made with the user,
the ticket link with the tracker's closing keyword (e.g. `Closes #12`), then the
attribution line required by the session.

- Conflicts that need a judgment call → ask the user, don't guess.
- CI red → fix via follow-up dispatch to the worker, re-verify, push again.
- After each merge, the next branch must re-merge `origin/<target>` and re-run checks.
- After each merge: close the ticket the way the tracker doc says (local files: set
  `Status: done` and add the PR URL under `## Comments`), then start any ticket whose
  blockers are now all merged (back to step 2–3 for that wave).

## 8. Cleanup and report

- `orca orchestration worker-release --dispatch <id> --json` for each settled worker
  (or `worker-retain` if the user wants to keep it). Then
  `worker-list --run <run_id> --terminal-state reclaimable --json` must return none.
- Ask before removing merged worktrees (`orca worktree rm --help`).
- Locally: `git checkout <target> && git pull --ff-only`.
- Remove throwaway `<project>-<slug>-*` resources left behind.
- Spec path: once every ticket is merged, close the spec issue the tracker's way.
- Final report per ticket: PR URL, merge commit, outcome, anything dropped or deferred.
- Suggest the user run `/retro` in this session (it is user-only) if the build went
  sideways, to turn mistakes into checks or coding standards.
