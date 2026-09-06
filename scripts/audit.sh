#!/bin/sh
# memory-optimizer detection pass. Read-only: prints findings, changes nothing.
#
# Usage:  sh scripts/audit.sh [project-dir]     (defaults to CWD)
#
# Why a script: every invocation of this skill otherwise retypes the same find/wc
# incantations, and small mistakes there (a plain `ls`, a hardcoded ~/.claude)
# produce confidently wrong reports. Run this first, then interpret.

set -u
PROJ="${1:-$PWD}"
cd "$PROJ" 2>/dev/null || { echo "cannot cd to $PROJ"; exit 1; }

# User shells alias ls/cat/grep (rtk, exa, colorls). Aliases filter output
# silently and produce false-clean reports. Bypass them everywhere.
LS="/bin/ls"
GREP="command grep"
CAT="command cat"

CFG="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"

hr() { echo; echo "── $1"; }

# Rough token estimate. Bytes/4 is a heuristic, deliberately not a promise:
# models from Opus 4.7 onward use a tokenizer that yields roughly 30% more
# tokens for the same text, so any stored count drifts. Treat these as
# magnitudes for triage and get real numbers from /context.
est() { [ -f "$1" ] && awk 'END{printf "%d", (NR?FILESIZE:0)/4}' FILESIZE=$(wc -c <"$1") "$1" 2>/dev/null || echo 0; }

sizes() { # path -> "lines  ~tokens  path"
  for f in "$@"; do
    [ -f "$f" ] || continue
    l=$(wc -l <"$f" | tr -d ' ')
    b=$(wc -c <"$f" | tr -d ' ')
    printf "  %5s lines  ~%5s tok  %s\n" "$l" "$((b / 4))" "$f"
  done
}

echo "memory-optimizer audit"
echo "project:    $PROJ"
echo "config dir: $CFG$([ "$CFG" != "$HOME/.claude" ] && echo '   (relocated — dual-scope loading possible)')"

hr "Always-loaded instruction files"
sizes CLAUDE.md .claude/CLAUDE.md CLAUDE.local.md "$CFG/CLAUDE.md"
[ "$CFG" != "$HOME/.claude" ] && sizes "$HOME/.claude/CLAUDE.md"

hr "Rule files (recursive; no-paths = loads every session)"
find .claude/rules -name '*.md' -type f 2>/dev/null | while read -r f; do
  if head -20 "$f" | $GREP -q '^paths:'; then scope="scoped"; else scope="GLOBAL"; fi
  l=$(wc -l <"$f" | tr -d ' ')
  printf "  %5s lines  %-6s  %s\n" "$l" "$scope" "$f"
done
find "$CFG/rules" -name '*.md' -type f 2>/dev/null | while read -r f; do
  l=$(wc -l <"$f" | tr -d ' ')
  printf "  %5s lines  user    %s\n" "$l" "$f"
done

hr "Nested / ancestor CLAUDE.md (monorepo)"
find . -mindepth 2 -name CLAUDE.md -not -path '*/node_modules/*' 2>/dev/null | head -20

hr "Frontmatter key errors (globs: should be paths:)"
$GREP -rl 'globs:' .claude/rules 2>/dev/null || echo "  none"

hr "@imports (these load in full at session start — they do NOT defer cost)"
$GREP -hE '^@' CLAUDE.md .claude/CLAUDE.md "$CFG/CLAUDE.md" 2>/dev/null | sort | uniq -c | sort -rn || echo "  none"
echo "  (count >1 = same file imported from two scopes)"

hr "Volatile content in always-loaded files (invalidates the cached prefix)"
# CLAUDE.md and rules sit in the cached prefix; caching is byte-exact, so a
# changing date or version line means the prefix is re-processed every session
# instead of read from cache at ~1/10th the price.
for f in CLAUDE.md .claude/CLAUDE.md "$CFG/CLAUDE.md"; do
  [ -f "$f" ] || continue
  # A date inside a path or filename (`specs/2026-09-04-design.md`) is a stable
  # reference, not volatile content — excluded, or the check cries wolf.
  $GREP -nEi '[0-9]{4}-[0-9]{2}-[0-9]{2}|last updated|as of |current sprint|this week|version [0-9]+\.[0-9]+' "$f" 2>/dev/null \
    | $GREP -vE '/[0-9]{4}-[0-9]{2}-[0-9]{2}|[0-9]{4}-[0-9]{2}-[0-9]{2}[^ ]*\.(md|json|ya?ml|txt)' \
    | sed "s|^|  $f:|"
done
find .claude/rules -name '*.md' -type f 2>/dev/null -exec $GREP -nEil 'last updated|current sprint' {} \; 2>/dev/null
echo "  (nothing listed = clean)"

hr "Auto memory (learning memory Claude writes)"
MEMDIR=$(find "$CFG/projects" -maxdepth 2 -type d -name memory 2>/dev/null | $GREP -i "$(basename "$PWD")" | head -1)
if [ -n "${MEMDIR:-}" ]; then
  echo "  $MEMDIR"
  [ -f "$MEMDIR/MEMORY.md" ] && {
    l=$(wc -l <"$MEMDIR/MEMORY.md" | tr -d ' '); b=$(wc -c <"$MEMDIR/MEMORY.md" | tr -d ' ')
    printf "  MEMORY.md: %s lines, %s bytes" "$l" "$b"
    { [ "$l" -gt 200 ] || [ "$b" -gt 25600 ]; } && printf "   ← OVER startup budget; excess silently not loaded"
    echo
  }
  find "$MEMDIR" -name '*.md' -type f 2>/dev/null | wc -l | sed 's/^/  topic files: /'
else
  echo "  none found for this project"
fi

hr "Cross-scope duplicate loads (relocated config dir only)"
if [ "$CFG" != "$HOME/.claude" ]; then
  for f in CLAUDE.md RTK.md; do
    a="$HOME/.claude/$f"; b="$CFG/$f"
    if [ -f "$a" ] && [ -f "$b" ]; then
      ia=$(stat -L -f "%i" "$a" 2>/dev/null || stat -Lc "%i" "$a")
      ib=$(stat -L -f "%i" "$b" 2>/dev/null || stat -Lc "%i" "$b")
      if [ "$ia" != "$ib" ]; then
        echo "  DUP: $a and $b differ by inode (both load every session)"
      else
        echo "  ok:  $f resolves to one inode"
      fi
    fi
  done
else
  echo "  n/a — config dir is ~/.claude"
fi

hr "Repository hygiene"
# Only meaningful for code repos. In a docs site, knowledge vault, or notes
# repo, markdown at the root IS the product — reporting it as clutter is a
# false positive that costs the whole audit its credibility.
if [ -f package.json ] || [ -f Cargo.toml ] || [ -f go.mod ] || [ -f pyproject.toml ] \
   || [ -f composer.json ] || [ -f pom.xml ] || [ -f Gemfile ] || [ -f build.gradle ]; then
  find . -maxdepth 1 -type f -name '*.md' \
    -not -name CLAUDE.md -not -name README.md -not -name LICENSE.md \
    -not -name CHANGELOG.md -not -name CONTRIBUTING.md -not -name SECURITY.md 2>/dev/null \
    | sed 's/^/  possible root clutter: /'
else
  echo "  skipped — no package manifest found; this looks like a content or docs"
  echo "  repo, where root-level markdown is the product rather than clutter."
fi
$GREP -q '^\.scratch/' .gitignore 2>/dev/null || echo "  .scratch/ NOT in .gitignore"
[ -f CLAUDE.local.md ] && { $GREP -q 'CLAUDE.local.md' .gitignore 2>/dev/null || echo "  CLAUDE.local.md NOT gitignored"; }

hr "Next"
echo "  Line counts above are a smell test, not a budget. For real numbers —"
echo "  what actually occupies the window, including MCP tool definitions —"
echo "  run /context, or invoke the context-audit skill."
