#if DEBUG
import AppKit
import CoreText

/// 报出 App 进程里 `AppFont` 实际取到的字体，给界面检查的 FONT-BUNDLED 用 (`scripts/checks/ui_font.py`)。只在 Debug 构建里。
/// 每个字族、每个字重各取一个 14 号字，报出字体文件路径、PostScript 名、wght 轴上的实际值，
/// 以及子集外的汉字 (「龘」不在 GB2312 里) 回退到的字体。另报出 App 包的路径，检查按它判断字体文件在不在包内。
/// 入口是 C 符号 `wagetick_font_report()`，返回 JSON 字符串 (调用方 free)。由注入库在渲染完或驱动时调用，
/// 必须在 `AppFont.register()` 之后调用，否则取到的是退回的系统字体。
@_cdecl("wagetick_font_report")
public func appFontReport() -> UnsafeMutablePointer<CChar> {
    let weights: [AppFont.Weight] = [.regular, .medium, .semibold, .bold, .extraBold]
    var fonts: [[String: Any]] = []
    for (family, name) in [(AppFont.Family.ui, "ui"), (.num, "num")] {
        for weight in weights {
            let font = AppFont.nsFont(family, size: 14, weight: weight)
            fonts.append([
                "family": name,
                "weight": weight.rawValue,
                "path": fontPath(font),
                "postScriptName": font.fontName,
                "wght": wghtValue(font) ?? NSNull(),
            ])
        }
    }
    let ui = AppFont.nsFont(.ui, size: 14)
    let fallback = CTFontCreateForString(ui as CTFont, "龘" as CFString, CFRange(location: 0, length: 1))
    let report: [String: Any] = [
        "bundle": Bundle.main.bundleURL.resolvingSymlinksInPath().path,
        "fonts": fonts,
        "fallback": ["postScriptName": CTFontCopyPostScriptName(fallback) as String, "path": fontPath(fallback)],
    ]
    let data = (try? JSONSerialization.data(withJSONObject: report, options: [.sortedKeys])) ?? Data("{}".utf8)
    return strdup(String(decoding: data, as: UTF8.self))!
}

/// 字体文件的路径 (解开符号链接)；取不到时为空串。
private func fontPath(_ font: CTFont) -> String {
    guard let url = CTFontCopyAttribute(font, kCTFontURLAttribute) as? URL else { return "" }
    return url.resolvingSymlinksInPath().path
}

/// 字体在 wght 轴上的实际值 (取的是默认实例时 CoreText 不报变化，按轴的默认值算)；没有 wght 轴时为 nil。
private func wghtValue(_ font: CTFont) -> Double? {
    let wght = NSNumber(value: 0x7767_6874)
    if let value = (CTFontCopyVariation(font) as? [NSNumber: NSNumber])?[wght] {
        return value.doubleValue
    }
    let axes = CTFontCopyVariationAxes(font) as? [[String: Any]] ?? []
    let axis = axes.first { ($0[kCTFontVariationAxisIdentifierKey as String] as? NSNumber) == wght }
    return (axis?[kCTFontVariationAxisDefaultValueKey as String] as? NSNumber)?.doubleValue
}
#endif
