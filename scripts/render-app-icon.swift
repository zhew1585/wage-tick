#!/usr/bin/env swift
// 用打包的彩色小牛 (CowMascot 矢量 PDF，即设计稿 Mascot/Cow) 生成 macOS AppIcon 全套尺寸。
// 按 macOS 图标规范：1024 画布里 824 的圆角方块 (四周各留 100，圆角 185)，带一层轻投影；底色是设计 token accent-soft。
//
// 用法 (仓库根目录)：swift scripts/render-app-icon.swift
// 改了小牛或底色后重跑，输出覆盖 WageTick/Assets.xcassets/AppIcon.appiconset。

import AppKit

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let mascotURL = root.appendingPathComponent("WageTick/Assets.xcassets/CowMascot.imageset/cow-mascot.pdf")
let outputDir = root.appendingPathComponent("WageTick/Assets.xcassets/AppIcon.appiconset")

/// 设计 token accent-soft (#FDEBDD，见 WageTick/Theme/Palette.swift)。
let tileColor = NSColor(srgbRed: 0xFD / 255, green: 0xEB / 255, blue: 0xDD / 255, alpha: 1)
/// 以 1024 画布为基准的规范尺寸。
let canvas: CGFloat = 1024
let tileInset: CGFloat = 100
let tileRadius: CGFloat = 185
/// 小牛占方块宽度的比例 (PDF 自带约 8% 留白)。
let mascotScale: CGFloat = 0.8

guard let mascot = NSImage(contentsOf: mascotURL) else {
    fatalError("读不到小牛 PDF：\(mascotURL.path)")
}

/// 画出边长 `pixels` 的图标 PNG 数据。
func renderIcon(pixels: Int) -> Data {
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    ) else { fatalError("建位图失败") }
    rep.size = NSSize(width: pixels, height: pixels)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSGraphicsContext.current?.imageInterpolation = .high
    let unit = CGFloat(pixels) / canvas
    let tile = NSRect(x: tileInset, y: tileInset, width: canvas - tileInset * 2, height: canvas - tileInset * 2)
    let scaled = NSRect(x: tile.minX * unit, y: tile.minY * unit, width: tile.width * unit, height: tile.height * unit)
    let path = NSBezierPath(roundedRect: scaled, xRadius: tileRadius * unit, yRadius: tileRadius * unit)

    // 投影：规范模板是往下偏、柔和的一层。
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.28)
    shadow.shadowOffset = NSSize(width: 0, height: -10 * unit)
    shadow.shadowBlurRadius = 20 * unit
    shadow.set()
    tileColor.setFill()
    path.fill()
    NSGraphicsContext.restoreGraphicsState()

    let side = scaled.width * mascotScale
    let mascotRect = NSRect(x: scaled.midX - side / 2, y: scaled.midY - side / 2, width: side, height: side)
    mascot.draw(in: mascotRect, from: .zero, operation: .sourceOver, fraction: 1)
    NSGraphicsContext.restoreGraphicsState()
    guard let png = rep.representation(using: .png, properties: [:]) else { fatalError("编码 PNG 失败") }
    return png
}

struct Slot {
    let points: Int
    let scale: Int
    var filename: String { "icon_\(points)x\(points)\(scale == 2 ? "@2x" : "").png" }
}

let slots = [16, 32, 128, 256, 512].flatMap { [Slot(points: $0, scale: 1), Slot(points: $0, scale: 2)] }
try FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)
for slot in slots {
    try renderIcon(pixels: slot.points * slot.scale).write(to: outputDir.appendingPathComponent(slot.filename))
}

let images = slots.map { slot in
    """
        { "filename" : "\(slot.filename)", "idiom" : "mac", "scale" : "\(slot.scale)x", "size" : "\(slot.points)x\(slot.points)" }
    """
}
let contents = """
{
  "images" : [
\(images.joined(separator: ",\n"))
  ],
  "info" : { "author" : "xcode", "version" : 1 }
}

"""
try contents.write(to: outputDir.appendingPathComponent("Contents.json"), atomically: true, encoding: .utf8)
print("已生成 \(slots.count) 张图标到 \(outputDir.path)")
