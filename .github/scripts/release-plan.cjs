// 发布计划 (ADR-0007)：决定这次要不要发、发哪个提交、版本号与 tag。由 release.yml 的 plan 任务通过 actions/github-script 调用。
// 做法照搬 pingdotgg/t3code：
// - nightly：定时每 30 分钟检查一次，离上一个 nightly 满 6 小时、且 main 比它有新提交才发，打包当时 main 的最新提交。
//   手动选 nightly 时不看间隔，直接发。
// - 正式版：手动触发，打包最新一个 nightly 用的那个提交 (只发 nightly 已经跑过的版本)，版本号默认取那个 nightly 的基础版本。
// 版本号：有正式版时为最新正式版的补丁号 +1，还没有正式版时取工程里的 MARKETING_VERSION；nightly 再加「-nightly.日期.运行序号」。
const fs = require("fs");

const MINIMUM_NIGHTLY_GAP_MS = 6 * 60 * 60 * 1000;
const NIGHTLY_TAG = /^v(\d+)\.(\d+)\.(\d+)-nightly\.\d+\.\d+$/;
const STABLE_TAG = /^v(\d+)\.(\d+)\.(\d+)$/;

/** "v1.2.3" 或 "1.2.3" → [1, 2, 3]。 */
function parseVersion(text) {
  return text.replace(/^v/, "").split(/[-.]/).slice(0, 3).map(Number);
}

function compareVersions(a, b) {
  for (let i = 0; i < 3; i++) {
    if (a[i] !== b[i]) return a[i] - b[i];
  }
  return 0;
}

/** 下一个版本的基础号：最新正式版补丁 +1；还没有正式版时取工程里的 MARKETING_VERSION。 */
function nextBaseVersion(latestStable) {
  if (latestStable) {
    const [major, minor, patch] = parseVersion(latestStable.tag_name);
    return `${major}.${minor}.${patch + 1}`;
  }
  const project = fs.readFileSync("WageTick.xcodeproj/project.pbxproj", "utf8");
  const match = /MARKETING_VERSION = ([0-9]+\.[0-9]+\.[0-9]+);/.exec(project);
  if (!match) throw new Error("工程里找不到 MARKETING_VERSION");
  return match[1];
}

/** 定时任务：离上一个 nightly 不足 6 小时，或 main 没有新提交时不发。 */
async function nightlyIsDue({ github, context, core, latestNightly }) {
  if (!latestNightly) {
    core.info("还没有 nightly，发第一个。");
    return true;
  }
  const age = Date.now() - Date.parse(latestNightly.published_at);
  if (age < MINIMUM_NIGHTLY_GAP_MS) {
    core.info(`${latestNightly.tag_name} 发布不足 6 小时，跳过。`);
    return false;
  }
  const { data } = await github.rest.repos.compareCommitsWithBasehead({
    ...context.repo,
    basehead: `${latestNightly.tag_name}...${context.sha}`,
    per_page: 1,
  });
  if (data.status !== "ahead") {
    core.info(`main 相对 ${latestNightly.tag_name} 为 ${data.status}，没有新提交，跳过。`);
    return false;
  }
  return true;
}

module.exports = async function plan({ github, context, core }) {
  const inputs = context.payload.inputs || {};
  const channel = context.eventName === "schedule" ? "nightly" : inputs.channel || "nightly";
  const releases = (await github.paginate(github.rest.repos.listReleases, { ...context.repo, per_page: 100 }))
    .filter((release) => !release.draft && release.published_at);
  const latestNightly = releases
    .filter((release) => NIGHTLY_TAG.test(release.tag_name))
    .sort((a, b) => Date.parse(b.published_at) - Date.parse(a.published_at))[0];
  const latestStable = releases
    .filter((release) => STABLE_TAG.test(release.tag_name))
    .sort((a, b) => compareVersions(parseVersion(b.tag_name), parseVersion(a.tag_name)))[0];

  const output = (values) => Object.entries(values).forEach(([key, value]) => core.setOutput(key, String(value)));

  if (channel === "nightly") {
    if (context.eventName === "schedule" && !(await nightlyIsDue({ github, context, core, latestNightly }))) {
      output({ release: false });
      return;
    }
    const date = new Date().toISOString().slice(0, 10).replaceAll("-", "");
    const version = `${nextBaseVersion(latestStable)}-nightly.${date}.${context.runNumber}`;
    output({
      release: true,
      channel: "nightly",
      ref: context.sha,
      version,
      tag: `v${version}`,
      title: `牛马鼓励器 Nightly ${version} (${context.sha.slice(0, 7)})`,
      prerelease: true,
      previous_tag: latestNightly ? latestNightly.tag_name : "",
    });
    return;
  }

  if (!latestNightly) throw new Error("还没有 nightly：正式版只打包最新 nightly 的那个提交。");
  const { data: commit } = await github.rest.repos.getCommit({ ...context.repo, ref: latestNightly.tag_name });
  const override = (inputs.version || "").trim().replace(/^v/, "");
  const version = override || parseVersion(latestNightly.tag_name).join(".");
  if (!/^\d+\.\d+\.\d+$/.test(version)) throw new Error(`正式版版本号不合法：${version}`);
  if (releases.some((release) => release.tag_name === `v${version}`)) throw new Error(`v${version} 已经发过了`);
  core.notice(`正式版 v${version} 打包 ${latestNightly.tag_name} 的提交 ${commit.sha}`);
  output({
    release: true,
    channel: "stable",
    ref: commit.sha,
    version,
    tag: `v${version}`,
    title: `牛马鼓励器 ${version}`,
    prerelease: false,
    previous_tag: latestStable ? latestStable.tag_name : "",
  });
};
