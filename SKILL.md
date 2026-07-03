---
name: memory-optimizer
description: Optimize Claude Code memory and rules structure. Use when user mentions: memory optimization, CLAUDE.md cleanup, rules organization, token efficiency, reducing context, rules not being followed, duplicate rules, auto memory / MEMORY.md cleanup, or wants to clean up .claude/ directory. Also trigger when CLAUDE.md exceeds 200 lines or user complains about high token usage. Run this skill before reorganizing any Claude Code project's instruction structure.
compatibility: Requires Bash, Read, Write, Edit tools. Assumes Claude Code project with .claude/ directory.
---

# Memory Optimizer

Claude Code's memory system has two parts that must stay separate:

**Instruction memory** = Stable rules, policies, constraints (CLAUDE.md, .claude/rules/) — written by the user.
**Learning memory** = Experience, preferences, fixes — written by Claude. Two flavors coexist: Claude Code's official **auto memory** (`<config-dir>/projects/<project>/memory/`, MEMORY.md index) and project conventions like OpenWolf (`.wolf/cerebrum.md`, memory.md, buglog.json).

When these mix, rules bloat, conflicts appear, tokens waste. This skill fixes that.

## Key Concepts

**Scoped rules**: Files in `.claude/rules/` with `paths:` frontmatter (glob patterns). Load when Claude reads files matching the pattern, NOT at session start. Subdirectories inside `.claude/rules/` are officially supported — files are discovered recursively. Symlinks are supported too.

**Global rules**: Files without `paths:` frontmatter. Load once at session start.

**Auto memory**: Official Claude-written memory (stable, on by default since v2.1.59). Lives at `<config-dir>/projects/<project>/memory/` where config-dir = `$CLAUDE_CONFIG_DIR` or `~/.claude`; shared across all worktrees of the repo. Only the first 200 lines or 25KB of `MEMORY.md` load at startup; topic files load on demand. Toggle via `/memory` or `autoMemoryEnabled` in settings. It is NOT a substitute for CLAUDE.md — instructions stay user-written.

**Rule pollution**: Experience notes, preferences, lessons creeping into CLAUDE.md or rule files over time. Makes files huge, rules ignored.

**Shared rules**: Conventions used across multiple repos. Can be `@import`ed or symlinked. Symlinks better for 3+ repos.

**The deletion filter**: The single most reliable pruning test. For every line, ask: *"Would removing this cause Claude to make a mistake?"* If no, delete it. Line count is a symptom; this question is the cause. A 90-line file that survives this filter beats a 180-line file padded with lines that don't change behavior. Anthropic's own guidance: if the file is too long, Claude ignores half of it and important rules get buried.

**What to cut** (these waste tokens and bury real rules — flag them for removal):
- Self-evident practices Claude already follows: "write clean code", "add comments", "be terse", "prefer explicit over clever", "no hacky fixes". Claude does these unprompted.
- Instructions Claude already obeys correctly without being told.
- Occasional, specialized domain knowledge (a migration runbook, a deploy procedure, a one-off workflow). This belongs in a **Skill**, not in always-loaded memory — see "CLAUDE.md vs Skills" below.
- Overly specific schema/DB detail irrelevant to most tasks.
- Anything duplicated across sections or across scopes (global + project).
- Maintainer-only notes ("why this rule exists", changelog) — convert to block-level HTML comments (`<!-- ... -->`): Claude Code strips them before injection, so they cost zero context while staying visible to humans editing the file. (Comments inside code blocks are preserved.)
- Rules that MUST run at a fixed point (before every commit, after each edit) — memory is context, not enforcement. Recommend converting to a PreToolUse/lifecycle **hook** in settings; keep at most a one-line pointer in CLAUDE.md.

**CLAUDE.md vs Skills**: Two different loading models — keep content in the right one.
- **CLAUDE.md / rules** load *every session, automatically*. Best for universal rules that apply to most tasks (code style, build commands, safe-change rules). Risk: bloats context, buries key rules.
- **Skills** (SKILL.md) load *on demand, only when relevant* (descriptions load at start, full content on use). Best for occasional specialized workflows (deployment runbooks, migration guides, framework setup) and reference material (API docs, style guides). Risk: minimal, loaded selectively.
- **Rules** (`.claude/rules/` with `paths:`) sit in between: load automatically but only when matching files are touched. Best for language- or directory-specific guidelines.
- When a CLAUDE.md section is really an occasional procedure, recommend extracting it to a Skill. That removes per-session token cost without losing the knowledge. Add to change table: `EXTRACT | CLAUDE.md {section} → skill | occasional workflow, not universal rule`.
- Nested `.claude/skills/` directories load contextually when working on files in that subtree; name clashes appear as `<dir>:<name>`. Useful for monorepos — an app-specific deploy skill belongs in `apps/x/.claude/skills/`, not root CLAUDE.md.

## Critical Constraints

- Never auto-resolve rule conflicts. Report only.
- Always dry-run first. Show change summary table. Wait for confirmation.
- Rule files must stay under 100 lines. CLAUDE.md under 200 lines (under 100 is the ideal — Boris Cherny keeps his personal CLAUDE.md under 100; community consensus is 300 as a hard ceiling). But apply the deletion filter before counting lines — cutting low-signal lines matters more than hitting a number.
- Rules must be concrete and verifiable, not abstract.
- Experience notes belong in learning memory (auto memory or `.wolf/cerebrum.md`), NEVER in CLAUDE.md or rules.
- Subdirectories in `.claude/rules/` are officially supported (recursive discovery) — do NOT flatten as a "fix". Flatten only if the user prefers a flat convention, or on old Claude Code versions (<2.x) where nested rules didn't load.
- Never hand-edit auto memory content into CLAUDE.md wholesale. Auto memory is Claude-written learning memory; promoting an entry to CLAUDE.md is a deliberate user decision, one line at a time.
- Project root stays clean. Throwaway docs and test artifacts MUST live in `.scratch/` (gitignored). Committed docs go in `docs/`. Never let AI-generated reports/plans accumulate at root.
- Use `/bin/ls` or `find` for ALL detection commands, NEVER plain `ls`. User shells alias `ls` (rtk, exa, colorls) — aliases silently filter output → false-clean reports. Same applies to `cat`, `grep` if aliased; use `command cat` / `command grep` to bypass aliases (portable — note `/bin/grep` does NOT exist on macOS; grep is `/usr/bin/grep`).

## Required Checks (Run Every Time)

These checks are MANDATORY. Never skip them.

```bash
# File size checks — MUST run in Phase 1
wc -l .claude/rules/*.md 2>/dev/null | sort -n
wc -l CLAUDE.md

# Flag any file over 100 lines with specific trim suggestions
# Flag CLAUDE.md over 200 lines
```

**If file over 100 lines:** Suggest specific split points (by topic, section, feature).
**If CLAUDE.md over 200 lines:** Move sections to separate rule files or remove redundant content.

## Verification Checklist (run this after optimization)

After completing the workflow, verify ALL of these:

- [ ] All `.claude/rules/**/*.md` files under 100 lines
- [ ] No scoped rules appearing in `/memory` at session start
- [ ] No rule file appears twice in `/memory`
- [ ] If `CLAUDE.local.md` exists, it is in `.gitignore`
- [ ] No `globs:` frontmatter remaining (all converted to `paths:`)
- [ ] `CLAUDE.md` under 200 lines
- [ ] Auto memory `MEMORY.md` under 200 lines / 25KB (excess is silently NOT loaded at startup)
- [ ] No content duplicated between auto memory and CLAUDE.md
- [ ] Instruction memory and learning memory are in separate files (no experience notes in CLAUDE.md or rule files)
- [ ] If `$CLAUDE_CONFIG_DIR` ≠ `~/.claude`: sibling files (CLAUDE.md, RTK.md, etc.) in both scopes resolve to same inode via symlink
- [ ] Project root has no orphan `*.md` clutter (design docs, test reports, handover notes). `.scratch/` listed in `.gitignore`. CLAUDE.md contains a "Repository Hygiene" rule.

## Workflow

### Phase 1: Analyze (READ-ONLY)

Always start here. Gather state, show what you found.

**MANDATORY: Run file size checks first**
```bash
# User config dir may be relocated (claude-pro alias etc.) — NEVER hardcode ~/.claude
CFG="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"

# Rule files (recursive) + user-level rules
find .claude/rules -name "*.md" -exec wc -l {} + 2>/dev/null | sort -n
find "$CFG/rules" -name "*.md" -exec wc -l {} + 2>/dev/null | sort -n
# If CFG differs from ~/.claude, also check ~/.claude/rules for strays
# (plain `claude` sessions still read it)
[ "$CFG" != "$HOME/.claude" ] && find "$HOME/.claude/rules" -name "*.md" -exec wc -l {} + 2>/dev/null | sort -n

# Project CLAUDE.md — BOTH valid locations (project-relative, NOT affected by CLAUDE_CONFIG_DIR)
wc -l CLAUDE.md .claude/CLAUDE.md 2>/dev/null
# Nested + ancestor CLAUDE.md files (monorepo): ancestors load at launch,
# nested ones load on demand when Claude reads files in that subtree
find . -mindepth 2 -name "CLAUDE.md" -not -path "*/node_modules/*" 2>/dev/null
```

Flag any file over 100 lines immediately. Flag CLAUDE.md over 200 lines. These MUST be addressed.

**Monorepo note:** if ancestor/other-team CLAUDE.md files load irrelevantly, recommend `claudeMdExcludes` (glob patterns vs absolute paths) in `.claude/settings.local.json` — managed-policy CLAUDE.md cannot be excluded.

```
## Analysis Report

### Current structure
- CLAUDE.md: N lines (location: ./CLAUDE.md or ./.claude/CLAUDE.md)
- .claude/rules/: N files, M subdirectories
- ~/.claude/rules/ (user-level): N files
- Nested/ancestor CLAUDE.md files: [list]
- Global rules: [list]
- Scoped rules: [list]

### Issues detected
- Files over 100 lines: [list with specific line counts]
- CLAUDE.md over 200 lines: YES/NO (N lines)
- Subdirectories in rules/: [list]
- glob: frontmatter: [list]
- Potential duplicates: [list]
- Shared rules @imports: [list]
```

### Phase 2: Dry-Run Plan

Create change summary table. Show exactly what will happen.

| Action | File | Reason |
|--------|------|--------|
| REMOVE | @import naming.md from CLAUDE | already in global CLAUDE |
| DELETE | rules/openwolf.md | duplicate of @import |
| EXTRACT | CLAUDE.md deploy section → skill | occasional workflow, not universal rule |
| FIX | rules/react.md globs→paths | wrong frontmatter key |
| TRIM | <config-dir>/projects/<project>/memory/MEMORY.md | over 200-line startup budget |

**Ask for confirmation before proceeding.**

### Phase 3: Execute

After confirmation, execute each change in order:

1. **Audit rules directory structure**
2. **Fix frontmatter keys**
3. **Clean CLAUDE.md imports**
4. **Fix duplicate global rules**
5. **Handle CLAUDE.local.md (optional)**
6. **Audit for conflicts**
7. **Verify memory separation**
8. **Audit auto memory**
9. **Check gitignore**
10. **Run /memory to verify**
11. **Report file sizes**

## Step 1: Audit Rules Directory Structure

**Subdirectories in `.claude/rules/` are officially supported** — files are discovered recursively, and symlinks work. Nesting like `rules/backend/models.md` is valid organization, NOT an error. (Older skill versions mandated flattening; that was a workaround for a pre-2.x loading bug that no longer exists.)

What to actually audit:

```bash
# Inventory the full tree (recursive)
find .claude/rules -type f -name "*.md"
find .claude/rules -type d
```

- **One topic per file** (`api-design.md`, `testing.md`) — flag grab-bag files mixing topics.
- **Every file under 100 lines** — flag with split suggestions.
- **Scoped vs global is intentional** — a file without `paths:` loads every session; verify that's deliberate for each.
- **User-level rules** (`<config-dir>/rules/`, i.e. `$CLAUDE_CONFIG_DIR/rules` or `~/.claude/rules`) are official too — loaded before project rules (project wins). Audit them for size/duplication against project rules; personal preferences belong there, not copied into every repo.
- **Flatten ONLY if** the user asks for a flat convention, or the project must support Claude Code <2.x. Never present flattening as a correctness fix.

If flattening is explicitly requested:
```bash
find .claude/rules -mindepth 2 -type f -exec mv -i {} .claude/rules/ \;
find .claude/rules -mindepth 1 -type d -delete
```

Add to change table only for real problems: `SPLIT | rules/{file} | over 100 lines`, `FIX | rules/{file} add paths: | unintentionally global`

## Step 2: Fix Frontmatter Keys

Find any `globs:` in frontmatter, replace with `paths:`.

Example bad frontmatter:
```yaml
---
globs:
  - app/**/*.php
---
```

Correct:
```yaml
---
paths:
  - app/**/*.php
---
```

Check each file:
```bash
grep -l "globs:" .claude/rules/*.md
```

Add to change table: `FIX | {file} globs→paths | wrong frontmatter key`

Also verify rules are concrete:
- BAD: "Keep code clean", "Write good tests", "Follow best practices"
- GOOD: "Run `php artisan test` after modifying business logic"

Abstract rules → flag in conflicts report.

## Step 3: Clean CLAUDE.md Imports

**Import mechanics (official):** max 4 hops of recursion; relative paths resolve against the importing file, not CWD; imports inside code spans/fenced blocks are ignored (wrap `@name` in backticks to mention without importing); external imports require one-time user approval. Imported files still load at session start — @imports organize content, they do NOT reduce context cost.

First check global rules (config-dir aware):
```bash
CFG="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
grep -E "^@|shared-rules" "$CFG/CLAUDE.md"
```

Then check project CLAUDE.md:
```bash
cat CLAUDE.md | grep -E "^@|shared-rules"
```

**Keep these @imports:**
- `@.wolf/OPENWOLF.md` (if present — OpenWolf protocol)
- `@~/.claude/CLAUDE.md` (if present — global user rules)
- shared-rules NOT in ~/.claude/CLAUDE.md (unique to project)

**Remove these:**
- shared-rules already in ~/.claude/CLAUDE.md (global duplicates)

Add to change table for each removal:
- `REMOVE | @import {file} from CLAUDE.md | duplicate of global CLAUDE.md`

**Symlinks alternative:** If shared rule used across 3+ repos, offer symlink instead of @import:
```bash
ln -s ~/.claude/shared-rules/laravel/conventions/naming.md .claude/rules/naming.md
```

Then remove the @import. Add to change table:
- `SYMLINK | {target} → .claude/rules/{name}.md | shared rule across N repos`

## Step 3b: Cross-Scope Import Deduplication

Claude Code may load multiple CLAUDE.md scopes when `$CLAUDE_CONFIG_DIR` differs from `~/.claude` (e.g. `claude-pro` alias setting `CLAUDE_CONFIG_DIR=~/.claude-sub`). In that case Claude Code loads BOTH `~/.claude/CLAUDE.md` AND `$CLAUDE_CONFIG_DIR/CLAUDE.md` every session. Each `@import` resolves relative to its own CLAUDE.md → sibling files (e.g. `RTK.md`) get loaded twice with different inodes.

### Detection

```bash
# Detect dual-scope duplicate loads
if [ -n "$CLAUDE_CONFIG_DIR" ] && [ "$CLAUDE_CONFIG_DIR" != "$HOME/.claude" ]; then
  for f in CLAUDE.md RTK.md; do
    a="$HOME/.claude/$f"; b="$CLAUDE_CONFIG_DIR/$f"
    if [ -f "$a" ] && [ -f "$b" ]; then
      ia=$(stat -L -f "%i" "$a"); ib=$(stat -L -f "%i" "$b")
      if [ "$ia" != "$ib" ]; then
        diff -q "$a" "$b" >/dev/null 2>&1 && echo "DUP (same content, diff inode): $a vs $b"
      fi
    fi
  done
fi
```

Also grep `@imports` inside each CLAUDE.md — siblings with same name in both dirs are likely dupes.

### Fix: symlink to canonical

Pick canonical dir (usually `$CLAUDE_CONFIG_DIR` since alias points there). Replace siblings in `~/.claude` with symlinks:

```bash
CANON="$CLAUDE_CONFIG_DIR"  # e.g. ~/.claude-sub
for f in CLAUDE.md RTK.md; do
  [ -f "$HOME/.claude/$f" ] && [ ! -L "$HOME/.claude/$f" ] && mv "$HOME/.claude/$f" "$HOME/.claude/$f.bak"
  ln -sf "$CANON/$f" "$HOME/.claude/$f"
done
```

Verify:
```bash
stat -L -f "%i %N" ~/.claude/CLAUDE.md $CLAUDE_CONFIG_DIR/CLAUDE.md
# Both must print SAME inode
```

### Why this works

- Plain `claude` (no alias): reads `~/.claude/CLAUDE.md` → symlink → canonical content. Single load tree.
- `claude-pro` (alias): reads both paths, both resolve to same inode. Claude Code @-import resolver typically dedupes by realpath. Worst case content loads twice but only one file to maintain → no content drift.

### Change table entry

`SYMLINK | ~/.claude/{file} → $CLAUDE_CONFIG_DIR/{file} | cross-config-dir dedup`

## Step 4: Fix Duplicate Global Rules

Check for rules with `paths: **/*`:
```bash
grep -l "paths:\s*\*\*" .claude/rules/*.md
```

These conflict with being "global" (no paths = global). Two options:
- Remove `paths:` entirely → becomes truly global
- If duplicates @import in CLAUDE.md → delete the rules/ version, keep @import

Add to change table:
- `DELETE | {file} | duplicate of @import in CLAUDE.md`
- `FIX | {file} remove paths: | make truly global (no paths = global)`

## Step 5: Handle CLAUDE.local.md (Optional)

`CLAUDE.local.md` (project root, gitignored) is still officially supported for personal, machine-specific instructions. It loads in full at session start alongside CLAUDE.md.

**Worktree caveat:** a gitignored CLAUDE.local.md exists only in the worktree where it was created. If the user works across git worktrees, prefer a home-directory import in CLAUDE.md instead: `@~/.claude/<project>-instructions.md`.

**Do not create one unconditionally.** Only create it if the user has machine-specific content to move into it (local ports, personal test accounts, experimental notes currently polluting CLAUDE.md). An empty template is dead weight.

If creating, use this template:

```markdown
# Local Configuration

# This file contains machine-specific configuration that must NOT be committed to Git.

# Local dev ports
# DEV_PORT=3000
# DB_PORT=5432

# Personal test accounts
# TEST_USER=local@example.com
# TEST_PASSWORD=changeme

# Machine-specific runtime notes
# Docker requires rosseta for ARM Mac
# npm must use node v18, not v20

# Experimental workflows (not ready to share)
# TODO: experimental feature X
```

Add to change table:
- `CREATE | CLAUDE.local.md | machine-specific content moved out of CLAUDE.md`

Ensure gitignored (official location is project root, not .claude/):
```bash
grep -q "CLAUDE.local.md" .gitignore || echo "CLAUDE.local.md" >> .gitignore
```

Add to change table:
- `UPDATE | .gitignore | add CLAUDE.local.md`

## Step 6: Audit for Conflicts

Check all loaded files for contradictions:
1. Read CLAUDE.md
2. Read all .claude/rules/*.md
3. Read all @imported files
4. Look for:
   - Same behavior instructed differently
   - Overlapping path patterns with conflicting instructions
   - shared-rules conventions vs project-level rules

**Report format:**
```markdown
## Conflicts Found

### Naming convention conflict
- `rules/naming.md` line 15: "Use camelCase for variables"
- `CLAUDE.md` line 42: "Use snake_case for variables"
→ Resolution needed: which wins?

### Duplicate @import
- `CLAUDE.md` imports `@shared-rules/laravel/conventions/naming.md`
- `~/.claude/CLAUDE.md` also imports same file
→ Resolution: remove from project CLAUDE.md (already global)
```

**DO NOT auto-resolve.** Let user decide.

## Step 7: Verify Memory Separation

Check for experience notes in wrong places:

**The three-layer lens** — a well-formed CLAUDE.md covers three layers; check each is present and none has drifted into noise:
- **What** — tech stack, project structure, key dependencies and versions.
- **Why** — purpose of key components, rationale for architectural choices (e.g. "Zustand over Redux because…").
- **How** — explicit operational rules: build/test/lint commands Claude can't infer, code style, file-placement conventions, safe-change rules, non-obvious gotchas that have burned the team.

Run every candidate line through the deletion filter and "What to cut" list (see Key Concepts). If a section is an occasional workflow, recommend extracting it to a Skill.

**CLAUDE.md should contain:**
- Project description
- Stack info
- Concrete operational rules (build/test/lint commands, file-placement conventions, safe-change rules)
- @import statements
- Shared rules references

**NOT in CLAUDE.md:**
- "User prefers X over Y"
- "Lesson learned from bug Z"
- "Don't repeat mistake W"
- History/narrative of project

**Move experience notes to learning memory.** Destination depends on the project:
- OpenWolf project (`.wolf/` exists) → `.wolf/cerebrum.md`: preferences → `## User Preferences`, learnings → `## Key Learnings`, mistakes → `## Do-Not-Repeat`
- Otherwise → official auto memory (`<config-dir>/projects/<project>/memory/MEMORY.md` + topic files)

Add to change table:
- `MOVE | experience note from CLAUDE.md → {learning memory} | memory separation`

## Step 8: Audit Auto Memory

Official auto memory lives at `<config-dir>/projects/<project>/memory/` — the config dir is `$CLAUDE_CONFIG_DIR` if set, else `~/.claude` (custom location via `autoMemoryDirectory` in settings). Claude writes it; the user may edit or delete it freely.

```bash
# Locate and size the auto memory index (config-dir aware)
CFG="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
MEMDIR=$(find "$CFG/projects" -maxdepth 2 -type d -name memory 2>/dev/null | grep -i "$(basename "$PWD")")
wc -l -c "$MEMDIR/MEMORY.md" 2>/dev/null
find "$MEMDIR" -type f -name "*.md" 2>/dev/null
```

Check:
- **MEMORY.md over 200 lines or 25KB** → the excess is silently NOT loaded at startup. Trim the index: move detail into topic files (loaded on demand), keep MEMORY.md as a one-line-per-fact index.
- **Duplication with CLAUDE.md** → a fact in both places wastes tokens and can drift. Instructions belong in CLAUDE.md; learnings stay in auto memory.
- **Stale entries** → flag facts contradicting current code (renamed files, removed flags) for deletion.
- **OpenWolf coexistence** → if the project uses `.wolf/`, both learning-memory systems may run. That's acceptable, but the same lesson shouldn't live in both; flag duplicates and let the user pick a canonical home.

Add to change table: `TRIM | MEMORY.md | over startup budget`, `DELETE | memory/{fact}.md | stale/contradicted`

## Step 9: Check Gitignore

Verify `CLAUDE.local.md` is in `.gitignore` (official location is project root):

```bash
grep -q "CLAUDE.local.md" .gitignore || echo "CLAUDE.local.md" >> .gitignore
```

## Step 10: Verify Session Load

After all changes, ask user to run `/memory` and check:
- Only global (unscoped) rules and CLAUDE.md/CLAUDE.local.md files appear at session start
- Scoped rules NOT listed (only load when matching files accessed)
- No rule appears twice
- No shared-rules file appears twice
- Auto memory toggle state is as intended (`/memory` shows and controls it)

If issues found → add to conflicts report, fix.

## Step 11: Report File Sizes

Final report:

```bash
echo "## File Sizes After Optimization"
wc -l .claude/rules/*.md CLAUDE.md 2>/dev/null | tail -1
echo ""
echo "## Per-file breakdown"
wc -l .claude/rules/*.md CLAUDE.md 2>/dev/null | sort -n
```

Flag any files over 100 lines → need splitting.

## Step 12: Repository Hygiene

Keep project root clean. AI sessions, scratch experiments, and one-off documents tend to litter the root over time — design docs, test reports, audit reports, handover notes, debug scripts. These bloat git history, confuse new contributors, and signal "this repo is unmaintained."

### Detection

**CRITICAL: use `/bin/ls`, NOT plain `ls`.** Many user shells alias `ls` (rtk, exa, colorls, custom wrappers) — aliases silently return empty for some directories, producing false-clean reports. `/bin/ls` is unaliased. `find` works too. Never trust plain `ls` in detection.

```bash
# Count *.md files at project root (excluding CLAUDE.md, README.md, LICENSE, CHANGELOG)
/bin/ls *.md 2>/dev/null | grep -viE "^(CLAUDE|README|LICENSE|CHANGELOG|CONTRIBUTING|SECURITY)\.md$" | wc -l
# Anything > 0 → flag for migration

# Detect throwaway scripts/data at root
/bin/ls *.sh *.sql *.json *.log 2>/dev/null | grep -viE "(package|tsconfig|wrangler|pnpm-lock|yarn.lock)" | head

# Alternative (most portable): find -maxdepth 1
find . -maxdepth 1 -type f -name "*.md" -not -name "CLAUDE.md" -not -name "README.md" -not -name "LICENSE.md" -not -name "CHANGELOG.md"
```

Flag any matches in the Analysis Report under "Root clutter".

### Target structure

```
<repo-root>/
├── CLAUDE.md            # instructions
├── README.md            # public-facing
├── package.json, configs, lockfiles
├── docs/                # committed documentation (architecture, API specs, runbooks)
├── .scratch/            # GITIGNORED — throwaway artifacts
│   ├── docs/            # drafts, AI-generated reports, planning notes
│   ├── tests/           # exploratory scripts, ad-hoc fixtures
│   ├── data/            # sample payloads, debug captures
│   └── scripts/         # one-off shell/node scripts
└── apps/, packages/, src/, ...
```

### Required CLAUDE.md rule

CLAUDE.md must contain a "Repository Hygiene" section with this rule (paraphrased):

> Project root stays clean. Only essential files at root (CLAUDE.md, README, manifests, configs, workspace folders). Throwaway docs/test artifacts go in `.scratch/` (gitignored). Committed docs go in `docs/`. Before creating any file at root, ask: "Will every contributor need this committed forever?" If no → `.scratch/`.

If missing → add it. Change table entry: `ADD | CLAUDE.md Repository Hygiene section | prevent root clutter`.

### Required .gitignore entry

```bash
grep -q "^\.scratch/" .gitignore || echo -e "\n# throwaway / exploratory artifacts\n.scratch/" >> .gitignore
```

Change table entry: `UPDATE | .gitignore | add .scratch/`.

### Migration (do NOT auto-execute — recommend only)

For each root-level orphan `*.md` listed in detection:
- If it documents architecture/API/runbooks the team needs → suggest `docs/<file>`.
- If it's an AI-generated audit, plan, draft, handover, or one-off report → suggest `.scratch/docs/<file>`.

Output as recommendation table:

| File | Suggested destination | Reason |
|------|----------------------|--------|
| DESIGN.md | docs/design.md | architectural — committed |
| TEST_REPORT.md | .scratch/docs/test-report-YYYY-MM-DD.md | one-off AI output |
| handover.md | .scratch/docs/handover.md | session-specific |

**Never `git mv` automatically.** User decides which to keep vs trash.

## Completion Checklist

Before declaring done, verify ALL items in the Verification Checklist section.

Output final summary:
```
✅ Memory optimization complete

Changes applied: N
- Fixed: N frontmatter keys
- Removed: N duplicate @imports
- Extracted to skills: N sections
- Trimmed: auto memory MEMORY.md (N → N lines)
- Symlinks created: N
- Conflicts reported: N (user to resolve)

File sizes:
- CLAUDE.md: N lines (was N)
- Largest rule file: N lines (was N)
- Total rules: N files

Next: Run /memory to verify clean session load.
```

## Troubleshooting

**"/memory shows scoped rules at session start"**
→ File missing `paths:` frontmatter or has `paths: **/*`. Add specific paths or remove `paths:` entirely for truly global.

**"Rule file appears twice in /memory"**
→ Duplication bug. Check: (1) @imported AND in rules/, (2) symlinked AND @imported, (3) global rule with `paths:` frontmatter, (4) `$CLAUDE_CONFIG_DIR` ≠ `~/.claude` causes both scopes to load — see Step 3b for symlink fix.

**"Rules not being followed"**
→ File likely over 100 lines or rules are abstract. Split into smaller topic files or make rules concrete. These are CLAUDE.md failures, not Claude failures — always fixable.
→ If the rule is "must ALWAYS happen at point X" (pre-commit check, post-edit format): CLAUDE.md is context, not enforcement — no wording fixes that. Convert it to a hook (PreToolUse or the relevant lifecycle event); hooks execute regardless of what Claude decides.
→ To see exactly which instruction files loaded (and why a scoped rule didn't), suggest the `InstructionsLoaded` hook for logging — stronger evidence than eyeballing `/memory`.

**"Instructions lost after /compact"**
→ Root CLAUDE.md is re-read and re-injected after compaction; NESTED CLAUDE.md files are not — they reload only when Claude next reads a file in that subtree. Instructions given only in conversation don't survive at all: promote them to CLAUDE.md (instruction) or let auto memory keep them (learning).

**Diagnostic signals (which failure mode is it?)**
→ Claude *repeats a mistake* despite a rule against it = the rule is buried; the file is too long. Prune with the deletion filter, or move the rule higher.
→ Claude *asks questions already answered* in CLAUDE.md = the phrasing is ambiguous, not missing. Rewrite that rule concretely; don't add more lines.
A great CLAUDE.md is one where Claude never has to ask what it should already know.

**"High token usage persists"**
→ Check for (1) huge monolithic rules (>200 lines), (2) too many global (unscoped) rules, (3) experience notes bloating CLAUDE.md — move to learning memory, (4) @imports mistaken for lazy loading — imported files load in full at session start, (5) oversized auto memory MEMORY.md.

**"Claude forgot something it knew last session"**
→ Check auto memory: is it enabled (`/memory` toggle, `autoMemoryEnabled`)? Is the fact past line 200 / 25KB of MEMORY.md (not loaded)? Is it in a topic file Claude never opened? Promote critical facts into the first 200 lines of MEMORY.md, or into CLAUDE.md if it's actually an instruction.

**"Rules in subdirectories not loading"**
→ On current Claude Code, `.claude/rules/` is discovered recursively — subdirs are fine. If rules genuinely don't load: check frontmatter (`paths:` not `globs:`), check the glob actually matches the files being edited, and update Claude Code if on an old version.

**"Symlink doesn't resolve"**
→ Absolute paths work, relative may fail depending on CWD. Prefer absolute: `ln -s ~/.claude/shared-rules/...`

**"Detection says directory is empty but files visibly exist"**
→ User shell aliases `ls` (rtk/exa/colorls/custom wrapper). Aliased `ls` filters or fails silently. Re-run with `/bin/ls` or `find <path> -maxdepth 1 -type f`. NEVER trust a plain `ls` empty result as authoritative.

## References

- Memory & CLAUDE.md: https://code.claude.com/docs/en/memory
- CLAUDE.md vs Rules vs Skills decision matrix: https://code.claude.com/docs/en/features-overview
- .claude directory layout: https://code.claude.com/docs/en/claude-directory
- Skills: https://code.claude.com/docs/en/skills
- OpenWolf protocol for learning memory (project-local convention)
- Shared rules conventions (if applicable)
