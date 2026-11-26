# TEAM.md · read this before any task

## Roles
`roles/` is local-only (machine and environment details): it lives in the main checkout, never in git.

- Lead (Fable 5.2): writes SPEC.md, splits work, takes the hardest slice. Runs `/lead`.
- Designer (Opus 5.5): read-only on the repo. Mocks up every UI change in pencil before SPEC.md is written. see ./roles/DESIGNER.md
- Builders (Opus 5.5): one slice each, one worktree each. see ./roles/DEV.md
- Playtester (Opus 5.5): read-only. Reports bugs, never fixes them. see ./roles/QA.md
- Reviewer (Gemini 4 Neon): read-only. Reviews the code diff, never fixes it. see ./roles/REVIEWER.md
- Copywriter (Gemini 4 Neon): README.md only.

## Machines
- Builds, tests and app runs need macOS; which machine runs them is in ./roles/MACHINES.md.

## Rules
- Every handoff uses the BRIEF format below.
- A task is done only when its DONE WHEN check passes.
- A UI change is any change to what the user sees: layout, spacing, size, colour, type, icons or motion, in the app windows, widgets, menu bar or floating cow. Copy-only changes and fixes that leave the look unchanged are not UI changes.
- Every UI change starts with Designer mockups. No SPEC.md and no Builder work before the human approves the mockups; the approved mockups are the acceptance baseline.
- Mockups, `.pen` files and renders are local-only, like `docs/spec/`: never in git.
- Max 3 review rounds. Max 4 agent-to-agent handoffs without a human.
- Never touch .github/, scripts/ci/, Config/ (entitlements, Info.plist with the Sparkle key) or the signing setup without asking the human.
- Changes reach main only through the PR flow in CLAUDE.md.

## BRIEF format
BRIEF FOR: @<model>
ROLE:      <lead | designer | builder | playtester | reviewer | copywriter>
GOAL:      <the outcome in one sentence>
CONTEXT:   <files, decisions made, link to SPEC.md>
DONE WHEN: <a test passes, a command returns 0, a checklist is true>
DO NOT:    <files to leave alone, commands never to run>
RETURN:    <exactly what to report back>
