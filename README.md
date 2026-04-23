# memory-optimizer — Claude Code Skill

Audits and fixes Claude Code memory/rules structure in one pass.

## What it does
- Flattens .claude/rules/ subdirectories (confirmed bug fix)
- Converts globs: → paths: frontmatter
- Removes duplicate @imports vs global ~/.claude/CLAUDE.md
- Enforces file size limits (rules <100 lines, CLAUDE.md <200 lines)
- Creates CLAUDE.local.md template
- Reports rule conflicts without auto-resolving

## Performance
| Iteration | With Skill | Baseline | Delta |
|-----------|-----------|----------|-------|
| Iter-1    | 79%       | 63%      | +16%  |
| Iter-2    | 86%       | 75%      | +11%  |
| Iter-3    | 94%       | 65%      | +29%  |

## Install
cp -r memory-optimizer ~/.claude/skills/

## Usage
Any project — mention token limits, CLAUDE.md bloat, 
or rules cleanup. Skill auto-triggers.

## Requirements
- Claude Code with skills support
- .claude/ directory in your project
