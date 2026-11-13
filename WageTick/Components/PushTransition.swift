import SwiftUI

/// 页面之间的推入动画 (像 iPhone 的导航)：下一页从右边滑进来盖在当前页上，返回时往右滑出去。
/// 用法：ZStack 里底下是当前页，`if 有下一页 { 下一页.pushed() }`，ZStack 上挂 `.animation(.push, value: 是否有下一页)`。
/// 推进来的页面要有不透明底色 (各页都是 `Palette.bg` 或头图铺满)。
extension View {
    func pushed(level: Double = 1) -> some View {
        transition(.asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .trailing)))
            .zIndex(level)
    }
}

extension Animation {
    /// 推入、退出页面的动画。
    static let push = Animation.smooth(duration: 0.32)
}
