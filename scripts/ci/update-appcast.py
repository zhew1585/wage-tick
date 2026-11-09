#!/usr/bin/env python3
"""往 Sparkle 的 appcast.xml 里加一个版本 (ADR-0007)，由 release.yml 在发布后调用，结果推到 gh-pages。

App 只收正式版：nightly 条目带 <sparkle:channel>nightly</sparkle:channel>，Sparkle 默认不看带渠道的条目。
nightly 只留最近 10 个，正式版全部保留。Sparkle 按 <sparkle:version> (CI 构建号，一直递增) 比较新旧。

用法：
  update-appcast.py --appcast appcast.xml --version 0.1.1 --build 42 --channel stable \
      --url https://.../WageTick-0.1.1.zip --signature 'sparkle:edSignature="..." length="123"' \
      --link https://github.com/.../releases/tag/v0.1.1 --notes notes.txt

更新内容 (--notes，可选) 写进 <description sparkle:format="plain-text">，一行一条；App 的更新窗口按行显示。
"""
import argparse
import re
import xml.etree.ElementTree as ET
from email.utils import formatdate
from pathlib import Path

SPARKLE = "http://www.andymatuschak.org/xml-namespaces/sparkle"
MINIMUM_SYSTEM = "14.0"
KEEP_NIGHTLY = 10
ET.register_namespace("sparkle", SPARKLE)


def sparkle(tag: str) -> str:
    return f"{{{SPARKLE}}}{tag}"


def load(path: Path) -> ET.ElementTree:
    if path.exists():
        return ET.parse(path)
    rss = ET.Element("rss", {"version": "2.0"})
    channel = ET.SubElement(rss, "channel")
    ET.SubElement(channel, "title").text = "牛马鼓励器"
    return ET.ElementTree(rss)


def parse_signature(text: str) -> dict:
    """sign_update 的输出，如 `sparkle:edSignature="abc" length="123"`。"""
    pairs = dict(re.findall(r'([\w:]+)="([^"]*)"', text))
    if "sparkle:edSignature" not in pairs or "length" not in pairs:
        raise SystemExit(f"看不懂 sign_update 的输出：{text!r}")
    return {sparkle("edSignature"): pairs["sparkle:edSignature"], "length": pairs["length"]}


def main() -> None:
    parser = argparse.ArgumentParser()
    for name in ("appcast", "version", "build", "channel", "url", "signature", "link"):
        parser.add_argument(f"--{name}", required=True)
    parser.add_argument("--notes", help="更新内容文件，一行一条")
    args = parser.parse_args()

    path = Path(args.appcast)
    tree = load(path)
    channel = tree.getroot().find("channel")

    item = ET.Element("item")
    ET.SubElement(item, "title").text = args.version
    ET.SubElement(item, "pubDate").text = formatdate(usegmt=True)
    ET.SubElement(item, sparkle("version")).text = args.build
    ET.SubElement(item, sparkle("shortVersionString")).text = args.version
    ET.SubElement(item, sparkle("minimumSystemVersion")).text = MINIMUM_SYSTEM
    if args.channel == "nightly":
        ET.SubElement(item, sparkle("channel")).text = "nightly"
    ET.SubElement(item, "link").text = args.link
    if args.notes:
        notes = Path(args.notes).read_text(encoding="utf-8").strip()
        if notes:
            ET.SubElement(item, "description", {sparkle("format"): "plain-text"}).text = notes
    ET.SubElement(item, "enclosure", {"url": args.url, "type": "application/octet-stream", **parse_signature(args.signature)})

    # 新版本放在最前面；nightly 只留最近几个。
    items = [item] + channel.findall("item")
    nightly = [i for i in items if i.find(sparkle("channel")) is not None]
    for old in nightly[KEEP_NIGHTLY:]:
        items.remove(old)
    for old in channel.findall("item"):
        channel.remove(old)
    channel.extend(items)

    ET.indent(tree, space="  ")
    tree.write(path, encoding="utf-8", xml_declaration=True)


if __name__ == "__main__":
    main()
