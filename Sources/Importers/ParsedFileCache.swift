import Foundation
import TelemetryKit

/// The files read lately, as their importer parsed them, so that a file is read from disk once
/// however many windows open it (#482).
///
/// Reading a log is nearly all parsing: turning a 40 MB CSV into a `RawTable` takes seconds,
/// and building a session from that table a small fraction of one. The Logbook's import, a
/// project's compile and the Coaching and Replay windows each read the file for themselves, so
/// the same unchanged file was parsed three times within a minute. What they can share is the
/// table: it depends on the file and the importer alone. What each reads through — channel
/// mapping, resampling, the finish line, the trim — is applied when the session is built, which
/// every reader still does for itself, so nothing here can hand one reader another's settings.
///
/// A table is kept for the file as it was: its size, its modification date and its identity on
/// the volume are checked on every request, and a file that has changed or been replaced is read
/// again. Tables are dropped least recently used first past a budget, after a while unused, and
/// all at once when the system is short of memory.
public final class ParsedFileCache: @unchecked Sendable {
    public static let shared = ParsedFileCache()

    public struct Limits: Sendable {
        /// The most the kept tables may come to, by `ParsedFileCache.cost(of:)`. A table larger
        /// than this is not kept at all.
        public var bytes: Int
        public var files: Int
        /// How long a table is kept after it was last asked for.
        public var idleSeconds: Double

        public init(bytes: Int = 512 << 20, files: Int = 8, idleSeconds: Double = 600) {
            self.bytes = bytes
            self.files = files
            self.idleSeconds = idleSeconds
        }
    }

    /// How often the cache answered from memory, and how often it had to read.
    public struct Counts: Sendable, Equatable {
        public var hits = 0
        public var reads = 0
    }

    struct Key: Hashable {
        var path: String
        var importerID: String
    }

    /// The file as it was when it was read. A file edited in place has another date or size; one
    /// replaced by another — an atomic save, a copy over it — is another file on the volume.
    ///
    /// Asked of the file system each time, with `stat`: a `URL` remembers the resource values it
    /// was last asked for, and would go on describing the file as it was.
    struct Stamp: Equatable {
        var size: Int64
        var modifiedSeconds: Int
        var modifiedNanoseconds: Int
        var file: UInt64
        var volume: Int32

        init?(_ url: URL) {
            var info = stat()
            guard stat(url.path, &info) == 0, (info.st_mode & S_IFMT) == S_IFREG else { return nil }
            size = Int64(info.st_size)
            modifiedSeconds = info.st_mtimespec.tv_sec
            modifiedNanoseconds = info.st_mtimespec.tv_nsec
            file = UInt64(info.st_ino)
            volume = info.st_dev
        }
    }

    struct Entry {
        var stamp: Stamp
        var table: RawTable
        var cost: Int
        var lastUsed: Date
        /// How many times this file has been read while it has been kept: 1 unless it changed.
        var reads: Int
    }

    /// One reader at a time per file: a second reader that arrives while the first is still
    /// parsing waits for that table instead of parsing the file again.
    final class Gate {
        let lock = NSLock()
        var users = 0
    }

    public let limits: Limits
    private let now: @Sendable () -> Date
    private let lock = NSLock()
    private var entries: [Key: Entry] = [:]
    private var gates: [Key: Gate] = [:]
    private var tally = Counts()
    /// Whether a look for idle tables is already on its way.
    private var sweepPending = false
    private var pressure: (any DispatchSourceMemoryPressure)?

    public init(limits: Limits = Limits(), now: @escaping @Sendable () -> Date = { Date() }) {
        self.limits = limits
        self.now = now
        let source = DispatchSource.makeMemoryPressureSource(eventMask: [.warning, .critical], queue: .global())
        source.setEventHandler { [weak self] in self?.removeAll() }
        source.resume()
        pressure = source
    }

    deinit { pressure?.cancel() }

    /// The table of the file at `url` as `importerID` parses it: from memory when the file is as
    /// it was when it was last read, else from `read`, whose table is then kept. A read that
    /// throws keeps nothing.
    public func table(at url: URL, importerID: String, read: () throws -> RawTable) rethrows -> RawTable {
        // A file that cannot be described cannot be told from a changed one: read it, keep nothing.
        guard let stamp = Stamp(url) else { return try read() }
        let key = Self.key(url, importerID)
        let gate = enter(key)
        gate.lock.lock()
        defer {
            gate.lock.unlock()
            leave(key, gate)
        }
        if let table = kept(key, stamp) { return table }
        let table = try read()
        keep(table, key, stamp)
        return table
    }

    public var counts: Counts { lock.withLock { tally } }

    /// How many tables are kept, and what they come to.
    public var kept: (files: Int, bytes: Int) {
        lock.withLock { (entries.count, entries.values.reduce(0) { $0 + $1.cost }) }
    }

    /// How many times the file at `url` has been read while it has been kept; 0 when it is not.
    public func timesRead(_ url: URL, importerID: String) -> Int {
        lock.withLock { entries[Self.key(url, importerID)]?.reads ?? 0 }
    }

    public func removeAll() {
        lock.withLock { entries.removeAll() }
    }

    /// Drops the tables nobody has asked for in `limits.idleSeconds`.
    public func dropIdle() {
        lock.withLock { dropIdleLocked() }
    }

    /// What a table costs to keep: its samples, as the arrays hold them.
    public static func cost(of table: RawTable) -> Int {
        table.rowCount * (MemoryLayout<Double>.stride + table.columns.count * MemoryLayout<Double?>.stride)
    }

    // MARK: - Internals

    static func key(_ url: URL, _ importerID: String) -> Key {
        Key(path: url.resolvingSymlinksInPath().standardizedFileURL.path, importerID: importerID)
    }

    private func enter(_ key: Key) -> Gate {
        lock.withLock {
            let gate = gates[key] ?? Gate()
            gate.users += 1
            gates[key] = gate
            return gate
        }
    }

    private func leave(_ key: Key, _ gate: Gate) {
        lock.withLock {
            gate.users -= 1
            if gate.users == 0 { gates[key] = nil }
        }
    }

    private func kept(_ key: Key, _ stamp: Stamp) -> RawTable? {
        lock.withLock {
            dropIdleLocked()
            guard var entry = entries[key], entry.stamp == stamp else { return nil }
            entry.lastUsed = now()
            entries[key] = entry
            tally.hits += 1
            return entry.table
        }
    }

    private func keep(_ table: RawTable, _ key: Key, _ stamp: Stamp) {
        let cost = Self.cost(of: table)
        lock.withLock {
            tally.reads += 1
            let reads = (entries[key]?.reads ?? 0) + 1
            entries[key] = nil
            guard cost <= limits.bytes, limits.files > 0 else { return }
            entries[key] = Entry(stamp: stamp, table: table, cost: cost, lastUsed: now(), reads: reads)
            // Least recently used first, never the one just read.
            var total = entries.values.reduce(0) { $0 + $1.cost }
            while entries.count > limits.files || total > limits.bytes {
                guard let oldest = entries.filter({ $0.key != key }).min(by: { $0.value.lastUsed < $1.value.lastUsed })
                else { break }
                total -= oldest.value.cost
                entries[oldest.key] = nil
            }
        }
        scheduleSweep()
    }

    /// An idle app does not sit on what it read: looks again once the newest table could have
    /// gone idle, and keeps looking while anything is kept. One look is pending at a time.
    private func scheduleSweep() {
        let delay = limits.idleSeconds + 1
        guard delay.isFinite, delay < 86_400 else { return }
        let needed = lock.withLock {
            guard !sweepPending, !entries.isEmpty else { return false }
            sweepPending = true
            return true
        }
        guard needed else { return }
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self else { return }
            lock.withLock {
                sweepPending = false
                dropIdleLocked()
            }
            scheduleSweep()
        }
    }

    private func dropIdleLocked() {
        let cutoff = now().addingTimeInterval(-limits.idleSeconds)
        entries = entries.filter { $0.value.lastUsed >= cutoff }
    }
}
