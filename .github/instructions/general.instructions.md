---
applyTo: '**'
---

# AGENT BEHAVIOR & DEBUGGING PROTOCOL

## Core Principle: Evidence-Based Debugging
You must NEVER guess the root cause of a bug. You must prove it with logs.
Do not attempt to fix a bug until you have confirmed the issue with a reproduction script or log output.

## Debugging Workflow
When presented with a bug or error, follow these steps strictly:

1. **EXPLORE & HYPOTHESIZE**
   - Read the relevant code files.
   - Formulate 2-3 hypotheses about why the bug is occurring.
   - Do NOT write a fix yet.

2. **INSTRUMENTATION (Mandatory)**
   - Add extensive logging to the codebase to trace execution flow and variable state.
   - Use distinct prefixes for your logs (e.g., `[DEBUG_AGENT]`) so they are easy to grep.
   - Log entry/exit of functions, API response payloads, and conditional logic branches.

3. **VERIFY**
   - Run the code/tests to generate the logs.
   - Analyze the log output to confirm which hypothesis is correct.
   - If the logs are insufficient, add MORE logs.

4. **FIX & CLEANUP**
   - Only implement the fix once the root cause is proven by log data.
   - After the fix is verified, remove the temporary `[DEBUG_AGENT]` logs (unless instructed to keep them).