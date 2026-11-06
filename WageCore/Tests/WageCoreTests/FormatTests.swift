import Foundation
import Testing
@testable import WageCore

/// 数字展示格式【D9】：滚动区域以外的金额有小数时固定 2 位、整数不带小数点；百分比固定 2 位。
struct FormatTests {
    @Test("金额：有小数时补足 2 位 (22.30 不写成 22.3)，整数不带小数点，四舍五入到 2 位", arguments: [
        ("22.3", "22.30"), ("1000", "1000"), ("952.380952", "952.38"), ("0.005", "0.01"), ("1999.999", "2000"), ("0", "0"),
    ])
    func amount(value: String, expected: String) throws {
        #expect(Format.amount(try #require(Decimal(string: value))) == expected)
    }

    @Test("百分比：固定 2 位小数", arguments: [("0", "0.00%"), ("0.5", "50.00%"), ("0.125", "12.50%"), ("0.571428", "57.14%")])
    func percent(ratio: String, expected: String) throws {
        #expect(Format.percent(try #require(Decimal(string: ratio))) == expected)
    }
}
