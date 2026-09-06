---
name: memory-optimizer
description: Optimize Claude Code memory and rules structure. Use when user mentions: memory optimization, CLAUDE.md cleanup, rules organization, token efficiency, reducing context, rules not being followed, duplicate rules, auto memory / MEMORY.md cleanup, or wants to clean up .claude/ directory. Also trigger when CLAUDE.md exceeds 200 lines or the user complains about high token usage, buried rules, or Claude repeating mistakes it was told not to make. Run this skill before reorganizing any Claude Code project's instruction structure.
compatibility: Requires Bash, Read, Write, Edit tools. Assumes a Claude Code project with a .claude/ directory.
---

# Memory Optimizer

Claude Code's memory has two halves that must stay separate:

**Instruction memory** — stable rules, policies, constraints. `CLAUDE.md`,
`.claude/rules/`. Written by the user.
**Learning memory** — experience, preferences, fixes. Written by Claude. Two
flavours coexist: official **auto memory**
(`<config-dir>/projects/<project>/memory/`, indexed by `MEMORY.md`) and project
conventions like OpenWolf (`.wolf/cerebrum.md`).

When they mix, rules bloat, conflicts appear, and tokens burn. This skill
separates them and prunes what's left.

## Start here

```bash
sh <skill-dir>/scripts/audit.sh [project-dir]
```

Read-only. It resolves the config dir, sizes every always-loaded file, finds
wrong frontmatter keys, duplicate imports, cross-scope double-loads, volatile
content, oversized auto memory, and hygiene problems — bypassing shell aliases
that would otherwise produce false-clean reports.

Interpret its output, then read
[references/procedures.md](references/procedures.md) for the specific fixes it
flagged. Don't read all the procedures — read the ones you need.

## The load-cost model

Five mechanisms with different costs. Content in the wrong one is the single
most common defect — and the last two are invisible to `/memory`, which is why
audits that rely on it conclude a bloated project is lean:

| | Loads | Best for | Risk |
|---|---|---|---|
| **CLAUDE.md / rules without `paths:`** | Every session, automatically | Universal rules — code style, build commands, safe-change rules | Bloats context, buries key rules |
| **Rules with `paths:`** | When matching files are touched | Language- or directory-specific guidelines | Low; wrong glob = never loads |
| **Skills** | Descriptions at start, body on demand | Occasional specialized workflows — deploy runbooks, migrations, framework setup | Minimal |
| **Mandated-read files** | Every session, because a protocol orders it | Nothing, past a point — see below | Costs exactly like an auto-loaded file while appearing in no audit |
| **The skill & plugin listing** | Every session, one entry per installed skill | — | Silently truncates past ~1% of the window; skills stop being selected |

**Mandated-read memory** is the one people miss. A project protocol says
*"before generating code, read `.wolf/cerebrum.md`"* — nothing auto-loads it, so
`/memory` doesn't list it and `/context` doesn't attribute it, but every session
pays for it in full. In a mature project this is routinely the single largest
token sink. Grep the protocol files for read directives; see
[procedures §12](references/procedures.md).

**The learning-memory paradox** follows from this skill's own advice. Memory
separation funnels experience notes *into* learning memory — and if that
destination has no ceiling, no routing rule and no archive, it grows until it
costs more than everything this skill just trimmed. "Move it to cerebrum" is
never the end of the story.

When a CLAUDE.md section is really an occasional procedure, extract it to a
Skill. That removes the per-session cost without losing the knowledge.
Change table: `EXTRACT | CLAUDE.md {section} → skill | occasional workflow, not universal rule`.

`@import` organizes content; it does **not** defer cost. Imported files load in
full at session start. Users routinely assume otherwise — correct it explicitly.

In a monorepo, nested `.claude/skills/` and `.claude/rules/` load contextually
for that subtree. An app-specific deploy skill belongs in
`apps/x/.claude/skills/`, not root CLAUDE.md.

## The deletion filter

The most reliable pruning test. For every line: *"would removing this cause
Claude to make a mistake?"* If no, delete it.

Line count is a symptom; this question is the cause. A 90-line file that
survives the filter beats a 180-line file padded with lines that don't change
behaviour.

**Why it beats a line budget:** *context rot*. Anthropic's context-window
documentation states that as token count grows, accuracy and recall degrade —
more context is not automatically better, and curating what's in context
matters as much as how much space is available. So every low-signal line does
double damage: it costs tokens *and* dilutes the lines that do change
behaviour. That's the argument to make when a user resists cutting a rule
they're attached to. Keeping it is not free.

**What to cut:**

- Self-evident practices Claude already follows: "write clean code", "add
  comments", "be terse", "no hacky fixes"
- Instructions Claude already obeys correctly unprompted
- Occasional specialized knowledge — a deploy procedure, a migration runbook.
  That's a Skill, not always-loaded memory
- Overly specific schema or DB detail irrelevant to most tasks
- Anything duplicated across sections or scopes
- Maintainer notes ("why this rule exists", changelogs) — convert to
  block-level HTML comments (`<!-- … -->`). Claude Code strips them before
  injection, so they cost zero context while staying visible to humans editing
  the file. (Comments inside code blocks are preserved.)
- Rules that must fire at a fixed point — before every commit, after each edit.
  **Memory is context, not enforcement.** Convert to a hook; keep at most a
  one-line pointer.

## Volatile content

Anything in an always-loaded file that changes between or within sessions: a
date, a "last updated" stamp, a sprint number, a version string, a rotating
list of current work.

It costs more than its tokens. CLAUDE.md and rules sit in the **cached prefix**
of every request, and caching is byte-exact — the hierarchy runs
`tools → system → messages`, and a change at any level invalidates that level
*and everything after it*. One edited date line means the whole prefix is
re-processed instead of read from cache at roughly a tenth of the price.

Volatile facts belong in learning memory or the conversation. The same logic
applies to *when* you edit: rewriting a rule file mid-session invalidates the
prefix for the rest of that session, so batch memory edits at a natural
boundary rather than dribbling them out.

## Measuring

Line counts are a smell test, not a budget, and the proxy has drifted: models
from Opus 4.7 onward use a tokenizer that produces roughly **30% more tokens
for the same text**, so old line-based intuitions understate real cost. Where a
number matters, measure it.

More importantly, the markdown is often not the biggest consumer. Everything in
the request counts toward the window — system prompt, messages, images, and
**tool definitions**. A dozen MCP servers routinely outweigh every instruction
file combined, so a report of "CLAUDE.md is 180 lines ✓" can be true and
useless at the same time.

**Hand off for real numbers.** Before concluding that more trimming is the
answer, have the user run `/context`, or invoke the **`context-audit`** skill,
which reads `/context` and audits MCP servers, skills, settings and
permissions. This skill's job is the *structure and content* of memory files;
that skill's job is measuring everything that occupies the window. Use both.

## Constraints

- **Never auto-resolve rule conflicts.** Report them; the user decides.
- **Always dry-run first.** Show the change table, wait for confirmation.
- **Never delete an experience note — relocate it.** Learnings, preferences and
  "don't repeat this" notes are misfiled in CLAUDE.md, not worthless; they're
  often the most expensive content there. Write to the destination first, then
  remove. If the destination is unreachable, stage it in
  `.scratch/docs/lessons-to-promote.md` and say so in the report — but only when
  you actually hold a note that has nowhere else to go. The same care does not
  apply to filler — self-evident practices go straight in the bin.
- **Change nothing you cannot justify from a finding.** Every edit traces to
  something the audit surfaced. A repo that is already in good shape should end
  the pass with a report and no diff; inventing work to look useful is worse
  than reporting "nothing to do here", because the user now has to review it.
- **Learning memory is budgeted too.** Routing notes there without checking its
  size is how this skill fails at its own job. Any file a protocol mandates
  reading in full stays under 200 lines / 25KB — the same budget as `MEMORY.md`,
  for the same reason. Past that, either the protocol changes ("grep it", not
  "read it") or the file is split and archived.
- **Never delete learning memory — archive it.** Compaction moves resolved
  entries to `<memory-dir>/archive/<file>-<YYYY-MM>.md`; it never discards. The
  knowledge stays greppable, it just stops costing tokens every session.
  Deleting defeats the purpose; archiving preserves it. Entries describing an
  active hazard — deploy safety, credential handling, data-loss traps — stay in
  the live file regardless of age. Age is not the test; the deletion filter is.
- Rule files under 100 lines, CLAUDE.md under 200 (under 100 is the ideal; 300
  is a hard ceiling). Apply the deletion filter *before* counting — cutting
  low-signal lines matters more than hitting a number.
- Rules must be concrete and verifiable. "Run `php artisan test` after
  modifying business logic" beats "write good tests".
- Experience notes go in learning memory, never in CLAUDE.md or rules.
- Subdirectories in `.claude/rules/` are officially supported and discovered
  recursively. Do **not** flatten as a "fix" — only on explicit request, or for
  Claude Code <2.x.
- Never hand-edit auto memory into CLAUDE.md wholesale. Promotion is a
  deliberate user decision, one line at a time.
- Never hardcode `~/.claude`. Resolve `${CLAUDE_CONFIG_DIR:-$HOME/.claude}`.
- Use `/bin/ls`, `find`, `command grep`, `command cat` in detection. User shells
  alias these; aliases filter output silently and produce false-clean reports.
- Root-clutter checks apply to **code repos only**. In a docs site or knowledge
  vault, root-level markdown is the product — flagging it as litter costs the
  whole audit its credibility.

## Workflow

### Phase 1 — Analyze (read-only)

Run `scripts/audit.sh`, then report what it found:

```
## Analysis Report

### Current structure
- CLAUDE.md: N lines / ~N tokens (location)
- .claude/rules/: N files (N global, N scoped)
- User-level rules: N files
- Nested/ancestor CLAUDE.md: [list]
- Auto memory: MEMORY.md N lines / N KB

### Issues detected
- Over budget: [files with counts]
- Wrong frontmatter key: [list]
- Duplicate/cross-scope imports: [list]
- Volatile content in cached prefix: [list]
- Experience notes in instruction memory: [list]
- Conflicts: [list — report only]

### Not measured here
MCP tool definitions and total window usage — run /context or the
context-audit skill.
```

### Phase 2 — Dry run

One table, every proposed change, each with a reason:

| Action | File | Reason |
|--------|------|--------|
| REMOVE | @import naming.md from CLAUDE.md | already imported globally |
| EXTRACT | CLAUDE.md deploy section → skill | occasional workflow, not universal rule |
| FIX | rules/react.md globs→paths | wrong key, silently global |
| MOVE | "user prefers X" → auto memory | experience note in instruction memory |
| TRIM | MEMORY.md | over 200-line startup budget |
| HOOK | pre-commit rule → PreToolUse | memory is context, not enforcement |

**Wait for confirmation.** Then execute in order, reading
[references/procedures.md](references/procedures.md) for each flagged area.

### Phase 3 — Verify

- [ ] All rule files under 100 lines; CLAUDE.md under 200
- [ ] Every surviving line passes the deletion filter
- [ ] No scoped rules appear in `/memory` at session start; nothing appears twice
- [ ] No `globs:` frontmatter remains
- [ ] No volatile content in any always-loaded file
- [ ] Instruction and learning memory are separate — no experience notes in
      CLAUDE.md or rules
- [ ] `MEMORY.md` under 200 lines / 25KB; no content duplicated with CLAUDE.md
- [ ] Every mandated-read file under 200 lines / 25KB, or its read directive
      reworded to a targeted grep
- [ ] Learning memory has a ceiling and an archive, not just an inbox
- [ ] Skill and plugin listing within ~1% of the context window; zero-usage
      plugins disabled
- [ ] `CLAUDE.local.md` gitignored, if it exists
- [ ] If `$CLAUDE_CONFIG_DIR` ≠ `~/.claude`: sibling files resolve to one inode
- [ ] Code repos only: root clean, `.scratch/` gitignored, hygiene rule present
- [ ] User has run `/context` or `context-audit` for the numbers this skill
      doesn't measure

Close with what changed, in counts, and the before/after sizes. If the user's
original complaint was behavioural ("rules not being followed"), say which
structural defect explained it — that's the part they actually wanted.

## When the problem isn't memory

Three failure modes look like memory problems and aren't:

- **"Must always happen at point X"** → a hook, not a rule. Memory is context;
  Claude reads it and decides. A hook executes.
- **Token usage dominated by tool definitions** → `context-audit`, not more
  trimming.
- **Facts lost mid-session** → compaction dropped them. Anything that must
  survive belongs in a file, not the conversation. See
  [references/troubleshooting.md](references/troubleshooting.md).

## Reference

- [references/procedures.md](references/procedures.md) — the eleven detailed procedures
- [references/troubleshooting.md](references/troubleshooting.md) — symptom → cause → fix
- Memory & CLAUDE.md: https://code.claude.com/docs/en/memory
- Skills: https://code.claude.com/docs/en/skills
- Context windows (context rot, what counts): https://platform.claude.com/docs/en/build-with-claude/context-windows
- Prompt caching (why volatile content costs): https://platform.claude.com/docs/en/build-with-claude/prompt-caching
