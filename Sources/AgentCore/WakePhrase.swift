import Foundation

public enum WakePhrase {
    public static func command(in transcript: String, name: String) -> String? {
        let words = transcript.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init)
        let wakeWords = name.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map { $0.lowercased() }
        guard !wakeWords.isEmpty, words.count >= wakeWords.count else { return nil }
        for start in 0...(words.count - wakeWords.count) {
            if words[start..<(start + wakeWords.count)].map({ $0.lowercased() }) == wakeWords {
                return words.dropFirst(start + wakeWords.count).joined(separator: " ")
            }
        }
        return nil
    }
}
