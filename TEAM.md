# TEAM.md · read this before any task

## Roles
- Lead (Fable 5.2): writes SPEC.md, splits work, takes the hardest slice. Runs `/lead`.
- Builders (Opus 5.5): one slice each, one worktree each, on homemac. see ./roles/DEV.md
- Playtester (Opus 5.5): read-only, on homemac. Reports bugs, never fixes them. see ./roles/QA.md
- Reviewer (Gemini 4 Neon): read-only. Reviews the code diff, never fixes it. see ./roles/REVIEWER.md
- Copywriter (Gemini 4 Neon): README.md only.

## Machines
- Lead's machine is Linux: no Swift, no Xcode. Read, write and commit code there; build, test and run nothing there.
- homemac (macOS, arm64) is the T3 linked environment for every build, test and app run.
  Find its `environmentId` with `t3_environment_links` (label `homemac`) and the project with `t3_project_list` on it (title `wage-tick`).
  It checks out from GitHub, so push the branch before delegating there.

## Rules
- Every handoff uses the BRIEF format below.
- A task is done only when its DONE WHEN check passes.
- Max 3 review rounds. Max 4 agent-to-agent handoffs without a human.
- Never touch .github/, scripts/ci/, Config/ (entitlements, Info.plist with the Sparkle key) or the signing setup without asking the human.
- Changes reach main only through the PR flow in CLAUDE.md.

## BRIEF format
BRIEF FOR: @<model>
ROLE:      <lead | builder | playtester | reviewer | copywriter>
GOAL:      <the outcome in one sentence>
CONTEXT:   <files, decisions made, link to SPEC.md>
DONE WHEN: <a test passes, a command returns 0, a checklist is true>
DO NOT:    <files to leave alone, commands never to run>
RETURN:    <exactly what to report back>
