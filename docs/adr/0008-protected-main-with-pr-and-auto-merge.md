# main 受保护：改动走 PR，CI 通过后 squash 自动合并

nightly 直接打包 main 的最新提交 (ADR-0007)，main 上任何一个坏提交都会直接发到装了尝鲜版的人手里。
参考 pingdotgg/t3code 的做法 (2026-11-11，Allen 定)：

- main 用仓库 ruleset 保护：不能直接推送、不能删除；只能通过 PR 合入，PR 不需要别人批准 (一个人开发)。
- 合入前两项检查必须通过 (`.github/workflows/ci.yml`)：
  - 核心测试：WageCore 全部单元测试。
  - App 编译与启动：按发布的配置编 Release，跑 `scripts/ci/smoke-test.sh`，确认签名完整、带着 Sparkle 与小组件扩展、App 启动 15 秒后还在运行。
- 只允许 squash 合并：一个 PR 在 main 上就是一个提交，标题即 PR 标题加编号，更新内容 (`release-notes.sh`) 一个 PR 一条。合并后自动删分支。
- 打开 auto-merge：开 PR 后执行 `gh pr merge --auto --squash`，检查通过就自动合入；检查失败不合，修好再推即可。
- 发布前 (`release.yml`) 也跑同一个启动检查，起不来的版本不会发出去。

日常流程：新建分支 → 提交 → 推送 → `gh pr create` → `gh pr merge --auto --squash`。
不设管理员绕过：紧急情况也走 PR，CI 大约 4 分钟。
检查的 job 名就是 ruleset 里的必需检查名，改名要同步改 ruleset，否则 PR 会一直等一个不存在的检查。
