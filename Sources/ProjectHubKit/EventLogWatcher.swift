import Darwin
import Dispatch
import Foundation

/// Watches `events.jsonl` for appends and invokes the handler for each new
/// parsed `HookEvent`. Handles startup replay, file rotation, and incomplete
/// tail lines.
///
/// Usage:
///   let w = EventLogWatcher(fileURL: EventLog.logURL) { event in
///       // apply event
///   }
///   w.startWithReplay()
public final class EventLogWatcher {
    private let fileURL: URL
    private let handler: (HookEvent) -> Void

    private var watchFD: Int32 = -1
    private var source: DispatchSourceFileSystemObject?
    private var readOffset: UInt64 = 0
    /// Residue when the last chunk ended mid-line; prepend to the next chunk.
    private var partialLine: String = ""

    private let queue: DispatchQueue

    public init(
        fileURL: URL,
        queue: DispatchQueue = .main,
        handler: @escaping (HookEvent) -> Void
    ) {
        self.fileURL = fileURL
        self.queue = queue
        self.handler = handler
    }

    deinit {
        stop()
    }

    /// Replay everything currently in the file, THEN attach to catch future
    /// appends. A subsequent `drainAvailableLines()` call closes the tiny race
    /// window between replay and attach.
    public func startWithReplay() {
        EventLog.ensureExists()

        // 1. Read everything present and dispatch as replay events.
        var endOfReplay: UInt64 = 0
        if let handle = try? FileHandle(forReadingFrom: fileURL) {
            if let data = try? handle.readToEnd() {
                endOfReplay = UInt64(data.count)
                dispatchLines(in: data, flushPartial: true)
            }
            try? handle.close()
        }

        // 2. Start watching for future writes from that point on.
        readOffset = endOfReplay
        partialLine = ""
        attach()

        // 3. Drain once more to catch any writes that slipped in between.
        drainAvailableLines()
    }

    public func stop() {
        source?.cancel()
        source = nil
    }

    // MARK: - Internals

    private func attach() {
        watchFD = open(fileURL.path, O_EVTONLY)
        guard watchFD >= 0 else { return }

        let src = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: watchFD,
            eventMask: [.write, .extend, .rename, .delete],
            queue: queue
        )
        src.setEventHandler { [weak self] in
            guard let self else { return }
            let mask = src.data
            if mask.contains(.rename) || mask.contains(.delete) {
                // Rotation or manual deletion — drop watcher and re-attach.
                self.stop()
                self.queue.asyncAfter(deadline: .now() + 0.2) { [weak self] in
                    self?.reattachAfterRotation()
                }
                return
            }
            self.drainAvailableLines()
        }
        src.setCancelHandler { [weak self] in
            if let self, self.watchFD >= 0 {
                close(self.watchFD)
                self.watchFD = -1
            }
        }
        src.resume()
        self.source = src
    }

    private func reattachAfterRotation() {
        // After rotation, the live file is a fresh empty inode. Start reading
        // from 0 on the new file.
        readOffset = 0
        partialLine = ""
        EventLog.ensureExists()
        attach()
    }

    private func drainAvailableLines() {
        guard let handle = try? FileHandle(forReadingFrom: fileURL) else { return }
        defer { try? handle.close() }
        do {
            try handle.seek(toOffset: readOffset)
        } catch {
            // File likely shorter than offset (was rotated or truncated). Restart from 0.
            readOffset = 0
            partialLine = ""
            try? handle.seek(toOffset: 0)
        }
        guard let data = try? handle.readToEnd(), !data.isEmpty else { return }
        readOffset += UInt64(data.count)
        dispatchLines(in: data, flushPartial: false)
    }

    /// Parses `data` as UTF-8 and emits one `HookEvent` per complete line.
    /// `flushPartial: true` means "no more data coming" — emit even the
    /// trailing unterminated line (used during startup replay).
    private func dispatchLines(in data: Data, flushPartial: Bool) {
        guard let s = String(data: data, encoding: .utf8) else { return }
        partialLine += s
        while let nl = partialLine.firstIndex(of: "\n") {
            let line = String(partialLine[..<nl])
            partialLine.removeSubrange(...nl)
            if let event = EventLog.decode(line: line) {
                handler(event)
            }
        }
        if flushPartial, !partialLine.isEmpty {
            if let event = EventLog.decode(line: partialLine) {
                handler(event)
            }
            partialLine = ""
        }
    }
}
