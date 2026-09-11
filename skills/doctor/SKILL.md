---
name: doctor
description: Use when a user wants to check or troubleshoot the plugin setup, for example "is the plugin set up correctly", "why is my context or reminder not loading", or right after installing to confirm the environment and the project's .claude/ content are in place.
allowed-tools: Bash(${CLAUDE_SKILL_DIR}/scripts/doctor.sh)
---

# Setup doctor

Run the bundled `doctor.sh` to check the plugin setup and report what is missing.

```bash
${CLAUDE_SKILL_DIR}/scripts/doctor.sh
```

It discovers every check contributed across the plugin (the `*.doctor.sh` files),
runs them, and prints a grouped report with a one-line fix for each problem. It
never prints secret values. The engine check looks for `.claude/` from the current
directory up, the same walk the hooks do from the session cwd.

## Reading the output

- **✓** passes, **✗** needs fixing (the `→` under it is the fix), a lone **→** is a note.
- The final line says whether any **✗** is blocking (the plugin cannot work) or just worth fixing.
