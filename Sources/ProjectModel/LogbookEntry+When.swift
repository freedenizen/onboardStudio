import Foundation

extension LogbookEntry {
    /// The year the session was driven, for grouping: its own date's, else its day's; `nil` when
    /// neither is known.
    public var year: Int? {
        (date ?? dayDate).map { Calendar(identifier: .gregorian).component(.year, from: $0) }
    }

    /// When the session was driven, for counting visits and putting sessions in order (#656): its
    /// own date; else the date of the day it is on; else — on no day, as an entry not read from a
    /// logbook is — the day it was added. A clip with no clock, added with a day's files, used
    /// to count as a second visit to the circuit on the day of the import.
    public var when: Date { date ?? dayDate ?? added }
}
