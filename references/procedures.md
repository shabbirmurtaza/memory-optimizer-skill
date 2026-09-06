# Procedures

The detailed steps behind the workflow in SKILL.md. Read the ones the audit
flagged rather than all of them.

## Contents

1. [Rules directory structure](#1-rules-directory-structure)
2. [Frontmatter keys](#2-frontmatter-keys)
3. [CLAUDE.md imports](#3-claudemd-imports)
4. [Cross-scope import deduplication](#4-cross-scope-import-deduplication)
5. [Duplicate global rules](#5-duplicate-global-rules)
6. [CLAUDE.local.md](#6-claudelocalmd)
7. [Conflicts](#7-conflicts)
8. [Memory separation](#8-memory-separation)
9. [Auto memory](#9-auto-memory)
10. [Session load verification](#10-session-load-verification)
11. [Repository hygiene](#11-repository-hygiene)

---

## 1. Rules directory structure

Subdirectories in `.claude/rules/` are officially supported — files are
discovered recursively and symlinks work. `rules/backend/models.md` is valid
organization, not an error. (Older versions of this skill mandated flattening;
that was a workaround for a pre-2.x loading bug that no longer exists.)

What to actually audit:

- **One topic per file** (`api-design.md`, `testing.md`). Flag grab-bag files
  mixing unrelated topics — they're impossible to scope with `paths:` and they
  bury their own contents.
- **Scoped vs global is a deliberate choice.** A file without `paths:` loads
  every session. For each one, confirm that's intended.
- **User-level rules** (`$CLAUDE_CONFIG_DIR/rules` or `~/.claude/rules`) are
  official and load before project rules; project wins on conflict. Personal
  preferences belong there, not copied into every repo.
- **Flatten only if** the user asks for a flat convention, or the project must
  support Claude Code <2.x. Never present flattening as a correctness fix.

If flattening is explicitly requested:

```bash
find .claude/rules -mindepth 2 -type f -exec mv -i {} .claude/rules/ \;
find .claude/rules -mindepth 1 -type d -delete
```

**Monorepos.** Ancestor `CLAUDE.md` files load at launch; nested ones load on
demand when Claude reads a file in that subtree. When another team's ancestor
CLAUDE.md loads irrelevantly, exclude it with `claudeMdExcludes` in
`.claude/settings.local.json` — it takes glob patterns, not absolute paths, and
a managed-policy CLAUDE.md cannot be excluded.

Change table: `SPLIT | rules/{file} | grab-bag, N topics`,
`FIX | rules/{file} add paths: | unintentionally global`

## 2. Frontmatter keys

`globs:` is wrong; the key is `paths:`. A rule with the wrong key silently
becomes global — it loads every session and the user never learns why.

```yaml
# wrong                # right
---                    ---
globs:                 paths:
  - app/**/*.php         - app/**/*.php
---                    ---
```

Also verify rules are **concrete and verifiable**, since an abstract rule
costs tokens without changing behaviour:

- Weak: "Keep code clean", "Write good tests", "Follow best practices"
- Strong: "Run `php artisan test` after modifying business logic"

Change table: `FIX | {file} globs→paths | wrong key, silently global`

## 3. CLAUDE.md imports

Import mechanics: max 4 hops of recursion; relative paths resolve against the
importing file, not the CWD; imports inside code spans or fenced blocks are
ignored (wrap `@name` in backticks to mention one without importing);
external imports need one-time user approval.

**Imported files load in full at session start.** `@import` organizes content;
it does not defer cost. Users routinely believe otherwise — say so plainly.

```bash
CFG="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
command grep -E "^@|shared-rules" "$CFG/CLAUDE.md" CLAUDE.md
```

Keep: `@.wolf/OPENWOLF.md` (OpenWolf projects), `@~/.claude/CLAUDE.md`,
shared rules not already imported globally.
Remove: shared rules already imported in the user-level CLAUDE.md.

For a shared rule used across 3+ repos, prefer a symlink over an import —
one canonical file, no drift:

```bash
ln -s ~/.claude/shared-rules/laravel/conventions/naming.md .claude/rules/naming.md
```

Change table: `REMOVE | @import {file} | already global`,
`SYMLINK | {target} → .claude/rules/{name}.md | shared across N repos`

## 4. Cross-scope import deduplication

When `$CLAUDE_CONFIG_DIR` differs from `~/.claude` (e.g. a `claude-pro` alias
setting `CLAUDE_CONFIG_DIR=~/.claude-sub`), Claude Code loads **both**
`~/.claude/CLAUDE.md` and `$CLAUDE_CONFIG_DIR/CLAUDE.md` every session. Each
`@import` resolves relative to its own CLAUDE.md, so sibling files with the
same name load twice from different inodes — double tokens, and two files
that drift apart.

`scripts/audit.sh` detects this. The fix is to make one canonical and symlink
the other:

```bash
CANON="$CLAUDE_CONFIG_DIR"
for f in CLAUDE.md RTK.md; do
  [ -f "$HOME/.claude/$f" ] && [ ! -L "$HOME/.claude/$f" ] && mv "$HOME/.claude/$f" "$HOME/.claude/$f.bak"
  ln -sf "$CANON/$f" "$HOME/.claude/$f"
done
stat -L -f "%i %N" ~/.claude/CLAUDE.md "$CLAUDE_CONFIG_DIR/CLAUDE.md"   # same inode
```

Plain `claude` then reads the symlink and gets canonical content; the aliased
`claude` reads both paths, which resolve to one inode. Worst case the content
loads twice, but there is only one file to maintain.

Change table: `SYMLINK | ~/.claude/{file} → $CLAUDE_CONFIG_DIR/{file} | cross-scope dedup`

## 5. Duplicate global rules

`paths: **/*` is a contradiction — it means "global" the long way round, and
it makes the rule look scoped in `/memory` when it isn't.

```bash
command grep -l "paths:\s*\*\*" .claude/rules/*.md
```

Either remove `paths:` entirely (truly global), or, if the file duplicates an
`@import` in CLAUDE.md, delete the rules/ copy.

## 6. CLAUDE.local.md

Still officially supported for personal, machine-specific instructions at the
project root, gitignored, loaded in full at session start.

**Worktree caveat:** a gitignored `CLAUDE.local.md` exists only in the
worktree where it was created. For users working across worktrees, prefer a
home-directory import instead: `@~/.claude/<project>-instructions.md`.

**Do not create one unconditionally.** Create it only when there is real
machine-specific content to move out of CLAUDE.md — local ports, personal
test accounts, experimental notes. An empty template is dead weight that
loads every session.

Ensure it's ignored:

```bash
command grep -q "CLAUDE.local.md" .gitignore || echo "CLAUDE.local.md" >> .gitignore
```

## 7. Conflicts

Read CLAUDE.md, every rule file, and every imported file, then look for the
same behaviour instructed two ways, overlapping `paths:` patterns with
contradictory instructions, and shared-rules conventions fighting project
rules.

Report, never auto-resolve — the user owns which one wins:

```markdown
### Naming convention conflict
- `rules/naming.md:15` — "Use camelCase for variables"
- `CLAUDE.md:42` — "Use snake_case for variables"
→ Which wins?
```

## 8. Memory separation

**The three-layer lens.** A well-formed CLAUDE.md covers three layers; check
each is present and none has drifted into noise:

- **What** — stack, project structure, key dependencies and versions.
- **Why** — purpose of key components, rationale for architectural choices
  ("Zustand over Redux because…").
- **How** — operational rules Claude can't infer: build/test/lint commands,
  file placement, safe-change rules, gotchas that have burned the team.

Belongs in CLAUDE.md: project description, stack, concrete operational rules,
`@import` statements, shared-rules references.

Does **not**: "user prefers X over Y", "lesson learned from bug Z", "don't
repeat mistake W", project history and narrative.

Move experience notes to learning memory — OpenWolf projects to
`.wolf/cerebrum.md` (preferences → `## User Preferences`, learnings →
`## Key Learnings`, mistakes → `## Do-Not-Repeat`); everything else to auto
memory.

Change table: `MOVE | experience note from CLAUDE.md → {learning memory} | memory separation`

## 9. Auto memory

Lives at `<config-dir>/projects/<project>/memory/`, where config-dir is
`$CLAUDE_CONFIG_DIR` if set, else `~/.claude` (custom location via
`autoMemoryDirectory`). Claude writes it; the user may edit or delete freely.

Check:

- **MEMORY.md over 200 lines or 25KB** → the excess is silently not loaded at
  startup. Trim the index: detail moves into topic files (loaded on demand),
  MEMORY.md keeps one line per fact.
- **Duplication with CLAUDE.md** → wastes tokens and lets the two drift.
  Instructions belong in CLAUDE.md, learnings in auto memory.
- **Stale entries** → facts contradicting current code (renamed files, removed
  flags). Flag for deletion; a confidently wrong memory is worse than none.
- **OpenWolf coexistence** → both systems may run, which is fine, but the same
  lesson shouldn't live in both. Flag duplicates, let the user pick a home.

Never promote auto memory into CLAUDE.md wholesale. Promotion is a deliberate
user decision, one line at a time.

## 10. Session load verification

Ask the user to run `/memory` and confirm:

- Only global rules and CLAUDE.md/CLAUDE.local.md appear at session start
- Scoped rules are absent (they load only when matching files are touched)
- Nothing appears twice
- The auto memory toggle is in the intended state

For harder cases, the `InstructionsLoaded` hook logs exactly which instruction
files loaded and why a scoped rule didn't — stronger evidence than eyeballing
`/memory`.

## 11. Repository hygiene

**Only for code repos.** In a docs site, knowledge vault, or notes repo,
root-level markdown is the product; calling it clutter destroys the audit's
credibility. `scripts/audit.sh` gates this check on a package manifest being
present — respect that gate.

Target structure for a code repo:

```
<repo-root>/
├── CLAUDE.md, README.md, manifests, configs
├── docs/        # committed documentation
├── .scratch/    # GITIGNORED — throwaway artifacts
│   ├── docs/    # drafts, AI-generated reports, planning notes
│   ├── tests/   # exploratory scripts, ad-hoc fixtures
│   └── data/    # sample payloads, debug captures
└── src/, apps/, packages/, …
```

The rule to add to CLAUDE.md:

> Project root stays clean. Only essential files at root (CLAUDE.md, README,
> manifests, configs, workspace folders). Throwaway docs and test artifacts go
> in `.scratch/` (gitignored); committed docs go in `docs/`. Before creating a
> file at root, ask: "will every contributor need this committed forever?"

```bash
command grep -q "^\.scratch/" .gitignore || printf '\n# throwaway artifacts\n.scratch/\n' >> .gitignore
```

**Never `git mv` automatically.** Produce a recommendation table — architecture
and API docs to `docs/`, AI-generated audits, plans and handovers to
`.scratch/docs/` — and let the user decide what's worth keeping.
