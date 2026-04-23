---
name: memory-optimizer
description: Optimize Claude Code memory and rules structure. Use when user mentions: memory optimization, CLAUDE.md cleanup, rules organization, token efficiency, reducing context, rules not being followed, duplicate rules, or wants to clean up .claude/ directory. Also trigger when CLAUDE.md exceeds 200 lines or user complains about high token usage. Run this skill before reorganizing any Claude Code project's instruction structure.
compatibility: Requires Bash, Read, Write, Edit tools. Assumes Claude Code project with .claude/ directory.
---

# Memory Optimizer

Claude Code's memory system has two parts that must stay separate:

**Instruction memory** = Stable rules, policies, constraints (CLAUDE.md, .claude/rules/)
**Learning memory** = Experience, preferences, fixes (.wolf/cerebrum.md, memory.md, buglog.json)

When these mix, rules bloat, conflicts appear, tokens waste. This skill fixes that.

## Key Concepts

**Scoped rules**: Files in `.claude/rules/` with `paths:` frontmatter. Load only for matching files.

**Global rules**: Files without `paths:` frontmatter. Load once at session start.

**Rule pollution**: Experience notes, preferences, lessons creeping into CLAUDE.md or rule files over time. Makes files huge, rules ignored.

**Shared rules**: Conventions used across multiple repos. Can be `@import`ed or symlinked. Symlinks better for 3+ repos.

## Critical Constraints

- Never auto-resolve rule conflicts. Report only.
- Always dry-run first. Show change summary table. Wait for confirmation.
- Rule files must stay under 100 lines. CLAUDE.md under 200 lines.
- Rules must be concrete and verifiable, not abstract.
- Experience notes belong in `.wolf/cerebrum.md`, NEVER in CLAUDE.md or rules.
- Subdirectories in `.claude/rules/` are ALWAYS flattened, NEVER created.

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

- [ ] All `.claude/rules/*.md` files under 100 lines
- [ ] No scoped rules appearing in `/memory` at session start
- [ ] No rule file appears twice in `/memory`
- [ ] `CLAUDE.local.md` exists and is in `.gitignore`
- [ ] No `globs:` frontmatter remaining (all converted to `paths:`)
- [ ] No subdirectories remaining in `.claude/rules/`
- [ ] `CLAUDE.md` under 200 lines
- [ ] Instruction memory and learning memory are in separate files (no experience notes in CLAUDE.md or rule files)

## Workflow

### Phase 1: Analyze (READ-ONLY)

Always start here. Gather state, show what you found.

**MANDATORY: Run file size checks first**
```bash
# Check all rule files
wc -l .claude/rules/*.md 2>/dev/null | sort -n
# Check CLAUDE.md
wc -l CLAUDE.md
```

Flag any file over 100 lines immediately. Flag CLAUDE.md over 200 lines. These MUST be addressed.

```
## Analysis Report

### Current structure
- CLAUDE.md: N lines
- .claude/rules/: N files, M subdirectories
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
| MOVE | rules/backend/api-routes.md | flatten subdirectory |
| REMOVE | @import naming.md from CLAUDE | already in global CLAUDE |
| DELETE | rules/openwolf.md | duplicate of @import |
| CREATE | .claude/CLAUDE.local.md | machine-specific template |
| FIX | rules/react.md globs→paths | wrong frontmatter key |

**Ask for confirmation before proceeding.**

### Phase 3: Execute

After confirmation, execute each change in order:

1. **Flatten rules directory**
2. **Fix frontmatter keys**
3. **Clean CLAUDE.md imports**
4. **Fix duplicate global rules**
5. **Create CLAUDE.local.md**
6. **Audit for conflicts**
7. **Verify memory separation**
8. **Check gitignore**
9. **Run /memory to verify**
10. **Report file sizes**

## Step 1: Flatten Rules Directory

### CRITICAL: Subdirectory Behavior

**# Current (failing) framing:**
"Move .claude/rules/backend/*.md → .claude/rules/"
"I have subdirs to clean up"

**# Replace with target-state assertion:**
The ONLY valid structure for `.claude/rules/` is a flat directory.
No subdirectories are ever correct — regardless of how organized they look.

BEFORE touching anything, run:
```bash
find .claude/rules -type d
```

If output shows anything beyond `.claude/rules/` itself → those are invalid.
Flatten them. No exceptions. No judgment calls.

**Example before/after:**

BEFORE (invalid — nested):
```
.claude/rules/
├── backend/
│   ├── models.md
│   └── permissions.md
├── frontend/
│   └── javascript.md
└── features/
    └── datatables.md
```

AFTER (correct — flat):
```
.claude/rules/
├── models.md
├── permissions.md
├── javascript.md
└── datatables.md
```

### Implementation

Run verification first:
```bash
# Check current state
find .claude/rules -type d
# Expected output: only .claude/rules/
# If any subdirs listed → INVALID, must flatten
```

Then flatten:
```bash
# Move all files from subdirs to rules root
find .claude/rules -mindepth 2 -type f -exec mv -i {} .claude/rules/ \;
# Remove empty subdirs
find .claude/rules -mindepth 1 -type d -delete
```

Add to change table: `MOVE | {subdir}/{file} | INVALID subdirectory → flatten`

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

First check global rules:
```bash
cat ~/.claude/CLAUDE.md | grep -E "^@|shared-rules"
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

## Step 5: Create CLAUDE.local.md

Create empty template with commented placeholders:

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
- `CREATE | .claude/CLAUDE.local.md | machine-specific template`

Add to .gitignore:
```
.claude/CLAUDE.local.md
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

**CLAUDE.md should contain:**
- Project description
- Stack info
- Core principles
- @import statements
- Shared rules references

**NOT in CLAUDE.md:**
- "User prefers X over Y"
- "Lesson learned from bug Z"
- "Don't repeat mistake W"
- History/narrative of project

**Move experience notes to `.wolf/cerebrum.md`:**
- User preferences → `## User Preferences`
- Learnings → `## Key Learnings`
- Mistakes → `## Do-Not-Repeat`

Add to change table:
- `MOVE | experience note from CLAUDE.md → .wolf/cerebrum.md | memory separation`

## Step 8: Check Gitignore

Verify `.claude/CLAUDE.local.md` is in `.gitignore`:

```bash
grep -q "CLAUDE.local.md" .gitignore || echo ".claude/CLAUDE.local.md" >> .gitignore
```

## Step 9: Verify Session Load

After all changes, ask user to run `/memory` and check:
- Only global rules appear at session start
- Scoped rules NOT listed (only load when matching files accessed)
- No rule appears twice
- No shared-rules file appears twice
- CLAUDE.local.md is NOT in /memory (local only)

If issues found → add to conflicts report, fix.

## Step 10: Report File Sizes

Final report:

```bash
echo "## File Sizes After Optimization"
wc -l .claude/rules/*.md CLAUDE.md 2>/dev/null | tail -1
echo ""
echo "## Per-file breakdown"
wc -l .claude/rules/*.md CLAUDE.md 2>/dev/null | sort -n
```

Flag any files over 100 lines → need splitting.

## Completion Checklist

Before declaring done, verify ALL items in the Verification Checklist section.

Output final summary:
```
✅ Memory optimization complete

Changes applied: N
- Moved: N files from subdirectories
- Fixed: N frontmatter keys
- Removed: N duplicate @imports
- Created: CLAUDE.local.md
- Symlinks created: N
- Conflicts resolved: N

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
→ Duplication bug. Check: (1) @imported AND in rules/, (2) symlinked AND @imported, (3) global rule with `paths:` frontmatter.

**"Rules not being followed"**
→ File likely over 100 lines or rules are abstract. Split into smaller topic files or make rules concrete.

**"High token usage persists"**
→ Check for (1) huge monolithic rules (>200 lines), (2) too many global rules, (3) experience notes bloating CLAUDE.md. Move to .wolf/cerebrum.md.

**"Symlink doesn't resolve"**
→ Absolute paths work, relative may fail depending on CWD. Prefer absolute: `ln -s ~/.claude/shared-rules/...`

## References

- Claude Code official docs on memory structure
- OpenWolf protocol for learning memory
- Shared rules conventions (if applicable)
