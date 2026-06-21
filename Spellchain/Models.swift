import Foundation
import SwiftData

/// One completed daily round. All properties have defaults and there are no unique constraints,
/// so the schema is CloudKit-mirroring compatible (SwiftData + CloudKit requirement).
///
/// `dateKey` ("yyyy-MM-dd") is how we de-dupe a day's result and drive streaks. `wordsJoined`
/// stores the found words as a newline string (CloudKit-friendly scalar) rather than an array.
@Model
final class DailyResult {
    var id: UUID = UUID()
    var date: Date = Date.now
    var dateKey: String = ""
    var letters: String = ""
    var score: Int = 0
    var wordCount: Int = 0
    var bestWord: String = ""
    var bestChain: Int = 0
    var wordsJoined: String = ""

    init(id: UUID = UUID(), date: Date = .now, dateKey: String = "", letters: String = "",
         score: Int = 0, wordCount: Int = 0, bestWord: String = "", bestChain: Int = 0,
         words: [String] = []) {
        self.id = id
        self.date = date
        self.dateKey = dateKey
        self.letters = letters
        self.score = score
        self.wordCount = wordCount
        self.bestWord = bestWord
        self.bestChain = bestChain
        self.wordsJoined = words.joined(separator: "\n")
    }

    var words: [String] {
        wordsJoined.split(separator: "\n").map(String.init)
    }
}
