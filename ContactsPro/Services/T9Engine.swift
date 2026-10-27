import Foundation

/// T9 九宫格检索引擎。
///
/// 老式手机的输入法映射：abc=2, def=3, ghi=4, jkl=5, mno=6, pqrs=7, tuv=8, wxyz=9。
/// 中文名先转拼音，所以「张三」可以这样找：
///   - 94264  → zhang（张）
///   - 726    → san（三）
///   - 97     → zs（首字母）
///   - 94264726 → 全拼连写
/// 另外号码本身也进键，输入 138 能直接命中号码。
enum T9Engine {

    /// 数字键 → 字母
    static let letterMap: [Character: Character] = [
        "a": "2", "b": "2", "c": "2",
        "d": "3", "e": "3", "f": "3",
        "g": "4", "h": "4", "i": "4",
        "j": "5", "k": "5", "l": "5",
        "m": "6", "n": "6", "o": "6",
        "p": "7", "q": "7", "r": "7", "s": "7",
        "t": "8", "u": "8", "v": "8",
        "w": "9", "x": "9", "y": "9", "z": "9"
    ]

    /// 键盘上每个键下面标注的字母
    static let keyHints: [(digit: String, letters: String)] = [
        ("2", "ABC"), ("3", "DEF"), ("4", "GHI"),
        ("5", "JKL"), ("6", "MNO"), ("7", "PQRS"),
        ("8", "TUV"), ("9", "WXYZ")
    ]

    // MARK: - 文本 → 数字串

    /// 字母转数字、数字原样保留、其他字符丢弃
    static func digits(from text: String) -> String {
        var out = ""
        out.reserveCapacity(text.count)
        for ch in text.lowercased() {
            if ch.isNumber {
                out.append(ch)
            } else if let mapped = letterMap[ch] {
                out.append(mapped)
            }
        }
        return out
    }

    // MARK: - 为联系人建立检索键

    /// 一个联系人生成一组数字串，输入只要是其中任意一个的前缀就算命中。
    static func buildKeys(name: String, organization: String, phones: [String]) -> [String] {
        var keys = Set<String>()

        func absorb(_ text: String) {
            let syllables = PinyinService.syllables(text)
            guard !syllables.isEmpty else { return }

            // 每个字/词单独成键 → 支持「输入名的部分」
            for s in syllables {
                let d = digits(from: s)
                if !d.isEmpty { keys.insert(d) }
            }

            // 连写（整名） → 支持「从头一直打」
            let joined = digits(from: syllables.joined())
            if !joined.isEmpty { keys.insert(joined) }

            // 首字母（整名 + 每个词） → 支持「zs」找张三
            let allInitials = syllables.compactMap { $0.first }.map(String.init).joined()
            let initialDigits = digits(from: allInitials)
            if !initialDigits.isEmpty { keys.insert(initialDigits) }
        }

        absorb(name)
        if !organization.isEmpty { absorb(organization) }

        // 号码：纯数字直接进键
        for phone in phones {
            let p = phone.filter { $0.isNumber }
            if !p.isEmpty { keys.insert(p) }
        }

        return Array(keys)
    }

    // MARK: - 匹配

    /// 输入为空时视为全匹配
    static func matches(keys: [String], input: String) -> Bool {
        guard !input.isEmpty else { return true }
        return keys.contains { $0.hasPrefix(input) }
    }

    /// 命中质量：数字越小排越前。完全命中 < 前缀命中 < 包含命中 < 不命中
    static func score(keys: [String], input: String) -> Int {
        guard !input.isEmpty else { return 100 }
        var best = Int.max
        for key in keys {
            if key == input {
                best = min(best, 0)
            } else if key.hasPrefix(input) {
                // 前缀越短（匹配得越完整）越靠前
                best = min(best, 1 + (key.count - input.count))
            } else if key.contains(input) {
                best = min(best, 500 + key.count)
            }
        }
        return best == Int.max ? 9999 : best
    }
}
