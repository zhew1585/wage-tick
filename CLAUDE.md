## Agent skills

### Issue tracker

Issues 在本仓库的 GitHub Issues 里 (zhew1585/wage-tick)，用 `gh` CLI 操作。See `docs/agents/issue-tracker.md`.

### Triage labels

用默认的五个标签：needs-triage / needs-info / ready-for-agent / ready-for-human / wontfix。See `docs/agents/triage-labels.md`.

### Domain docs

Single-context：根目录一个 `GLOSSARY.md`，ADR 放 `docs/adr/`。See `docs/agents/domain.md`.

### Git 流程

main 受保护，不能直接推送 (ADR-0008)。改动一律：新建分支 → 提交 → 推送 → `gh pr create` → `gh pr merge --auto --squash`，CI 两项检查通过后自动 squash 合入。
PR 标题会成为 main 上的提交标题和 App 更新内容里的一条，用 `feat: 中文描述` 这类格式；关联 issue 时在 PR 描述里写 `Closes #N`。
