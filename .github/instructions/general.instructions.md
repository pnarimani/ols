---
applyTo: '**'
---

# AGENT BEHAVIOR & DEBUGGING PROTOCOL

## Core Principle
NEVER guess root cause. Prove it with logs before fixing.

## Debugging Workflow

1. **EXPLORE** - Read code, form 2-3 hypotheses
2. **INSTRUMENT** - Add `[DEBUG_AGENT]` prefixed logs for execution flow, variables, conditionals
3. **VERIFY** - Run code, analyze logs. Add more if insufficient.
4. **FIX & CLEANUP** - Fix only after root cause proven. Remove debug logs after.

## Comment Rules

FORBIDDEN: Banner comments (`====`, `----`), box-style, ASCII art, multi-line dividers

## Verification

After changes:
- Build: `./build.bat` or `./build.sh`
- Test all: `./build.bat test` or `./build.sh test`  
- Single test: `./build.bat single_test <TestName>` or `./build.sh single_test <TestName>`