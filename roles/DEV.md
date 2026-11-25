# dev guidelines

## Code
- MUST use /tdd skill.
- Business rules and every piece of UI text live in `WageCore` with tests; the `WageTick/` and `WageTickWidgets/` shells only lay things out.
  A new rule or label goes into `WageCore` first, test-first.
- Name domain concepts with the terms in `GLOSSARY.md`.

## Checks before reporting done
- `swift test --package-path WageCore` is green.
- If the slice touches `WageTick/`, `WageTickWidgets/` or the Xcode project, the Release build from the CI `App 编译与启动` job compiles.

## Comments
- Write comments in Chinese, matching the existing code.
- Do not comment line by line. Only put a short description above types, functions and properties where it helps.
- The goal is to let a reader quickly understand what a type or function does.
- Comments must be self-explanatory.
- ADR numbers are fine to cite (`docs/adr/` is tracked). Specs under `docs/spec/` are local-only: never cite them or their section numbers.
