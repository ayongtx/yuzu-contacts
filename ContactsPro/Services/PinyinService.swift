import Foundation

/// 汉字转拼音。
/// 用系统自带的 CFStringTransform 完成，零依赖、不联网、离线也准。
enum PinyinService {

    private static var cache: [String: String] = [:]
    private static let lock = NSLock()

    /// 整串转拼音（不带声调、小写、字之间留空格）
    /// "张三" -> "zhang san"
    static func fullPinyin(_ text: String) -> String {
        guard !text.isEmpty else { return "" }

        lock.lock()
        if let hit = cache[text] {
            lock.unlock()
            return hit
        }
        lock.unlock()

        let mutable = NSMutableString(string: text) as CFMutableString
        // 1. 先转成带声调的拉丁字母
        CFStringTransform(mutable, nil, kCFStringTransformToLatin, false)
        // 2. 去掉声调符号
        CFStringTransform(mutable, nil, kCFStringTransformStripDiacritics, false)

        let result = (mutable as String)
            .replacingOccurrences(of: "  ", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        lock.lock()
        // 简单限容，防止极端情况下无限增长
        if cache.count > 4000 { cache.removeAll(keepingCapacity: true) }
        cache[text] = result
        lock.unlock()

        return result
    }

    /// 每个字的首字母连起来
    /// "张三" -> "zs"
    static func initials(_ text: String) -> String {
        fullPinyin(text)
            .split(separator: " ")
            .compactMap { $0.first }
            .map(String.init)
            .joined()
    }

    /// 列表右侧索引字母。英文取首字母，中文取拼音首字母，其余归到 #
    static func indexLetter(for text: String) -> String {
        guard let first = text.first else { return "#" }

        if first.isASCII, first.isLetter {
            return String(first).uppercased()
        }
        let py = initials(text)
        if let c = py.first, c.isASCII, c.isLetter {
            return String(c).uppercased()
        }
        return "#"
    }

    /// 按字切分的拼音数组
    /// "张三丰" -> ["zhang", "san", "feng"]（英文单词保持完整）
    static func syllables(_ text: String) -> [String] {
        fullPinyin(text)
            .split(separator: " ")
            .map(String.init)
            .filter { !$0.isEmpty }
    }
}
