# Troubleshooting

Symptom → cause → fix. Most of these look like "Claude is being dumb" and are
actually a memory-structure defect, which means they're fixable.

## Diagnostic signals

Read the symptom precisely — it tells you which failure mode you have, and the
two common ones need opposite fixes:

- Claude **repeats a mistake** a rule forbids → the rule is *buried*. The file
  is too long or the rule is too far down. Prune with the deletion filter, or
  move the rule up. Adding more words makes it worse.
- Claude **asks about something already answered** in CLAUDE.md → the rule is
  *ambiguous*, not missing. Rewrite that one rule concretely. Adding lines
  makes it worse here too.

A good CLAUDE.md is one where Claude never has to ask what it should already
know.

## Scoped rules appear at session start

The file is missing `paths:` frontmatter, uses `globs:` (wrong key, silently
global), or has `paths: **/*` which matches everything. Add specific paths, or
remove `paths:` deliberately if it really should be global.

## A rule file appears twice in /memory

Four causes, in rough order of likelihood:

1. It's both `@import`ed and present in `.claude/rules/`
2. It's symlinked *and* imported
3. It's a global rule that also carries `paths:` frontmatter
4. `$CLAUDE_CONFIG_DIR` differs from `~/.claude`, so both scopes load — see
   procedures §4 for the symlink fix

## A rule never fires, and its frontmatter looks correct

This is the most common real cause of "I wrote a rule weeks ago and Claude has
never once followed it" — and the hardest to see, because nothing looks wrong.
The key is `paths:`, the YAML parses, the file is short and concrete. The
pattern simply matches nothing that exists.

Typical shapes: `**/*.jsx` in a codebase that is entirely `.tsx`; `**/*.tex` in
a vault of `.md` notes; `src/**` in a repo that keeps its code in `app/`; a
path that was accurate before a directory was renamed.

```bash
# For each rule, confirm its glob matches at least one real file
command grep -A3 '^paths:' .claude/rules/*.md
find . -path ./node_modules -prune -o -name '*.jsx' -print | head   # substitute the extension
```

A scoped rule only loads when a matching file enters context, so a dead pattern
is indistinguishable from a rule that does not exist. Fix the pattern against
the real tree, and check the whole set at once — a stack that was written for
an earlier layout usually has more than one stale entry.

## Rules aren't being followed

First check length and concreteness: over ~100 lines, or abstract phrasing
("write clean code"), and the rule is effectively invisible.

If the rule is "this must ALWAYS happen at point X" — a pre-commit check, a
format-after-edit — no wording will fix it. **Memory is context, not
enforcement.** Claude reads it and decides; a hook executes regardless.
Convert it to a `PreToolUse` or lifecycle hook in settings and leave at most a
one-line pointer in CLAUDE.md.

## Instructions lost after /compact

Root CLAUDE.md is re-read and re-injected after compaction. **Nested CLAUDE.md
files are not** — they reload only when Claude next reads a file in that
subtree. Instructions given only in conversation don't survive at all.

This is the general shape of it: compaction summarises earlier context and
drops what came before, so anything that must outlive a long session has to
live in a *file*. If it's an instruction, promote it to CLAUDE.md. If it's a
learning, let auto memory hold it. A `PostCompact` hook can re-assert
project-specific context that must survive every time.

## Claude forgot something it knew last session

Work through auto memory:

- Is it enabled? (`/memory` toggle, or `autoMemoryEnabled` in settings)
- Is the fact past line 200 / 25KB of MEMORY.md? Everything after that is
  silently not loaded at startup.
- Is it in a topic file Claude never had reason to open?

Promote genuinely critical facts into the first 200 lines of MEMORY.md, or
into CLAUDE.md if it's actually an instruction rather than a learning.

## High token usage persists after optimization

The markdown was probably never the biggest consumer. Everything in the
request counts toward the context window — system prompt, messages, images,
and **tool definitions**. A dozen MCP servers routinely outweigh every
instruction file combined.

Run `/context`, or invoke the `context-audit` skill, before assuming more
trimming will help. Then check, in order:

1. MCP servers loading tools the user never invokes
2. Too many global (unscoped) rule files
3. `@import`s mistaken for lazy loading — imported files load in full
4. An oversized auto memory MEMORY.md
5. Experience notes bloating CLAUDE.md

## Cache seems to re-process everything each session

Look for volatile content in always-loaded files — a date, a "last updated"
stamp, a sprint number, a version string. The cached prefix is byte-exact, so
one changing line invalidates it and everything after it. Move volatile facts
into learning memory or the conversation.

Mid-session churn does the same thing: rewriting a rule file in the middle of
a session invalidates the prefix for the rest of it. Batch memory edits at a
natural boundary instead.

## Detection says a directory is empty but files visibly exist

The user's shell aliases `ls` (rtk, exa, colorls, a custom wrapper). Aliased
`ls` can filter or fail silently, producing a false-clean report. Re-run with
`/bin/ls` or `find <path> -maxdepth 1 -type f`. Never accept a plain `ls`
empty result as authoritative — `scripts/audit.sh` already bypasses aliases
for exactly this reason.

Same applies to `cat` and `grep`; use `command cat` / `command grep`. Note
`/bin/grep` does not exist on macOS (it's `/usr/bin/grep`), so prefer
`command grep` for portability.

## Symlink doesn't resolve

Relative paths resolve against the CWD at read time and may fail. Use absolute
paths: `ln -s ~/.claude/shared-rules/... .claude/rules/...`.

## Rules in subdirectories not loading

On current Claude Code, `.claude/rules/` is discovered recursively — subdirs
are fine and flattening is not a fix. If they genuinely don't load: check the
frontmatter key is `paths:` not `globs:`, check the glob actually matches the
files being edited, and check the Claude Code version (<2.x didn't recurse).
