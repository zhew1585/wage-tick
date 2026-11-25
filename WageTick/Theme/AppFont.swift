import AppKit
import CoreText
import OSLog
import SwiftUI

/// 字体 token：界面文字用 Noto Sans SC (设计稿 font-ui)，数字用 JetBrains Mono (font-num，等宽，滚动不抖)。
/// 两者都随 App 打包 (`Resources/Fonts`，SIL OFL 1.1，许可文件同目录)，启动时由 `register()` 注册到本进程。
/// Noto Sans SC 只保留 GB2312 汉字与常用符号 (约 4 MB)；子集外的字由系统自动回退到苹方。
/// 子集做法：`pyftsubset NotoSansSC[wght].ttf --text-file=<GB2312 + ASCII + 常用标点> --layout-features='*' --name-IDs='*'`。
/// 字体缺失 (注册失败) 时退回系统字体：界面文字用苹方/SF，数字用 SF Mono。
///
/// 用法：常用字号用预设 `AppFont.body`、`AppFont.numStat`；其他字号用 `AppFont.ui(15, .bold)`、`AppFont.num(40, .bold)`。
/// AppKit 里 (菜单栏、`NSDatePicker`) 用 `AppFont.nsFont(.num, size: 13, weight: .medium)`。
enum AppFont {
    enum Family {
        /// Noto Sans SC。
        case ui
        /// JetBrains Mono。
        case num

        fileprivate var name: String {
            switch self {
            case .ui: "Noto Sans SC"
            case .num: "JetBrains Mono"
            }
        }
    }

    /// 设计稿用到的字重，原始值是可变字体 wght 轴上的值。
    enum Weight: Int, Sendable {
        case regular = 400
        case medium = 500
        case semibold = 600
        case bold = 700
        /// 悬浮小牛气泡里的大字 (设计稿 800)。
        case extraBold = 800

        fileprivate var system: NSFont.Weight {
            switch self {
            case .regular: .regular
            case .medium: .medium
            case .semibold: .semibold
            case .bold: .bold
            case .extraBold: .heavy
            }
        }
    }

    // MARK: 界面文字预设 (font-ui)

    /// 空状态的大标题 22/700。
    static let title = ui(22, .bold)
    /// 引导页大标题 28/700 (设计稿 P1 引导 · 760)。
    static let display = ui(28, .bold)
    /// 引导页副标题、大号输入框的单位 14/400。
    static let lead = ui(14)
    /// 弹窗、子页面标题 15/700。
    static let sheetTitle = ui(15, .bold)
    /// 分组标题 14/600。
    static let section = ui(14, .semibold)
    /// 正文 13/400。
    static let body = ui(13)
    /// 次要按钮文字 13/500。
    static let bodyMedium = ui(13, .medium)
    /// 主按钮文字、强调正文 13/600。
    static let bodySemibold = ui(13, .semibold)
    /// 输入框里的文字 14/400。
    static let fieldText = ui(14)
    /// 输入框上方标签 12/500。
    static let label = ui(12, .medium)
    /// 说明文字 12/400。
    static let caption = ui(12)
    /// 强调说明 12/600。
    static let captionSemibold = ui(12, .semibold)
    /// 小字 11/400。
    static let small = ui(11)
    /// Chip 文字 11/600。
    static let chip = ui(11, .semibold)
    /// 最小字 10/400，图例、角注。
    static let tiny = ui(10)
    /// 子页面 (目标、历史、设置) 页头标题 17/700 (760 设计稿)。
    static let pageTitle = ui(17, .bold)

    // MARK: 数字预设 (font-num)

    /// 输入框里的数字 14/400。
    static let numField = num(14)
    /// 大号输入框里的数字 24/600 (引导页月薪)。
    static let numFieldLarge = num(24, .semibold)
    /// 中号输入框里的数字 17/600 (引导页时间)。
    static let numFieldMedium = num(17, .semibold)
    /// 汇总项数值 17/600。
    static let numStat = num(17, .semibold)
    /// 菜单栏数字 13/500。
    static let numMenuBar = num(13, .medium)
    /// 行内金额 12/600。
    static let numBody = num(12, .semibold)
    /// 说明里的数字 12/400。
    static let numCaption = num(12)
    /// 小号数字 11/400。
    static let numSmall = num(11)

    // MARK: 构造

    static func ui(_ size: CGFloat, _ weight: Weight = .regular) -> Font {
        cache.entry(.ui, size, weight).font
    }

    static func num(_ size: CGFloat, _ weight: Weight = .regular) -> Font {
        cache.entry(.num, size, weight).font
    }

    /// 按可变字体 wght 轴取精确字重 (JetBrains Mono 没有 600 的命名实例，按特征取会落到 700)。
    static func nsFont(_ family: Family, size: CGFloat, weight: Weight = .regular) -> NSFont {
        cache.entry(family, size, weight).nsFont
    }

    /// 同一字族、字号、字重只建一次字体对象。菜单栏和今日概览每 0.1 秒重算一遍 body，
    /// 每次都新建字体的话，CoreText 按字体对象缓存的排版结果全部命不中，每次刷新都要重新整形所有文字。
    private static let cache = FontCache()

    private static func makeFont(_ family: Family, size: CGFloat, weight: Weight) -> NSFont {
        let descriptor = NSFontDescriptor(fontAttributes: [
            .family: family.name,
            NSFontDescriptor.AttributeName(kCTFontVariationAttribute as String): [wghtAxis: weight.rawValue],
        ])
        if let font = NSFont(descriptor: descriptor, size: size), font.familyName == family.name {
            return font
        }
        return switch family {
        case .ui: NSFont.systemFont(ofSize: size, weight: weight.system)
        case .num: NSFont.monospacedSystemFont(ofSize: size, weight: weight.system)
        }
    }

    /// 注册打包的字体，只对本进程生效。须在任何视图取字体之前调用 (见 `Main`)。
    static func register() {
        let urls = Bundle.main.urls(forResourcesWithExtension: "ttf", subdirectory: nil) ?? []
        if urls.isEmpty {
            logger.error("没找到打包的字体，退回系统字体")
        }
        for url in urls {
            var error: Unmanaged<CFError>?
            if !CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error) {
                let message = error?.takeRetainedValue().localizedDescription ?? "未知错误"
                logger.error("注册字体失败 \(url.lastPathComponent, privacy: .public)：\(message, privacy: .public)")
            }
        }
    }

    /// 字体缓存，加锁，任何线程都能取。
    private final class FontCache: @unchecked Sendable {
        struct Entry {
            let nsFont: NSFont
            let font: Font
        }

        private struct Key: Hashable {
            let family: Family
            let size: CGFloat
            let weight: Weight
        }

        private let lock = NSLock()
        private var entries: [Key: Entry] = [:]

        func entry(_ family: Family, _ size: CGFloat, _ weight: Weight) -> Entry {
            let key = Key(family: family, size: size, weight: weight)
            return lock.withLock {
                if let entry = entries[key] { return entry }
                let nsFont = makeFont(family, size: size, weight: weight)
                let entry = Entry(nsFont: nsFont, font: Font(nsFont as CTFont))
                entries[key] = entry
                return entry
            }
        }
    }

    /// OpenType 'wght' 轴的标识。
    private static let wghtAxis = NSNumber(value: 0x7767_6874)
    private static let logger = Logger(subsystem: AppIdentity.bundleID, category: "Font")
}
