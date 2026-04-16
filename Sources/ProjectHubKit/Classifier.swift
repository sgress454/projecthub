import Darwin
import Foundation

/// Classifies the final assistant message of a Claude turn as one of three
/// categories via a `claude -p` subprocess, with `.failure` as the safe
/// fall-back on any error (bias per design D2).
public actor Classifier {
    public static let shared = Classifier()

    private var cachedClaudePath: String?
    private var hasResolvedClaudePath: Bool = false

    public init() {}

    /// Read the final assistant text from a transcript file and classify it.
    public func classify(transcriptPath: String) async -> ClassifierResult {
        let url = URL(fileURLWithPath: transcriptPath)
        guard let message = TranscriptReader.finalAssistantText(fromTranscriptAt: url) else {
            return .failure
        }
        return await classify(message: message)
    }

    /// Test-friendly entrypoint that skips the transcript read.
    public func classify(message: String) async -> ClassifierResult {
        guard let claudePath = resolveClaudePath() else { return .failure }
        let fullPrompt = """
        \(Self.classificationPrompt)

        MESSAGE:
        \(message)
        """
        let rawOutput = await runProcess(
            launchPath: claudePath,
            arguments: ["-p", fullPrompt],
            timeout: 3.0,
            environment: [
                "PATH": ClaudeCLI.augmentedPATH,
                "HOME": ProcessInfo.processInfo.environment["HOME"] ?? NSHomeDirectory(),
            ]
        )
        guard let rawOutput else { return .failure }
        return Self.parseClassifierOutput(rawOutput)
    }

    // MARK: - Prompt

    /// Fixed classification prompt. Three one-word outputs. Match design D2.
    public static let classificationPrompt: String = """
    You are classifying the FINAL assistant message in a Claude Code conversation to decide whether the user needs to look at it. Reply with exactly one word and nothing else — one of:

    QUESTION — the message asks the user to decide, approve, choose, or answer. Includes explicit questions AND cases where Claude is blocked and needs direction.
    REPORT — the message presents substantive findings, analysis, or multiple options. Worth the user's attention even though Claude isn't blocked.
    DONE — completion report with no open question and no content that demands review (e.g. "Fixed.", "Updated config.yaml.", "All tests pass.").

    Respond with only the single word. No explanation.
    """

    // MARK: - Output parsing

    public static func parseClassifierOutput(_ output: String) -> ClassifierResult {
        // Strip ANSI, trim, uppercase, look for the first recognized token.
        // Note: plain string literal so `\u{001B}` expands to the ESC byte
        // before NSRegularExpression parses the pattern.
        let ansiStripped = output.replacingOccurrences(
            of: "\u{001B}\\[[0-?]*[ -/]*[@-~]",
            with: "",
            options: .regularExpression
        )
        let trimmed = ansiStripped.trimmingCharacters(in: .whitespacesAndNewlines)
        let upper = trimmed.uppercased()

        if upper == "QUESTION" { return .question }
        if upper == "REPORT" { return .report }
        if upper == "DONE" { return .done }

        // Tolerate a leading punctuation / extra whitespace. Take the first
        // word-like token and see if it matches.
        let tokens = upper.split { !$0.isLetter }.map(String.init)
        if let first = tokens.first {
            switch first {
            case "QUESTION": return .question
            case "REPORT": return .report
            case "DONE": return .done
            default: break
            }
        }

        return .failure
    }

    // MARK: - claude CLI resolution

    /// Finds the `claude` CLI. Delegates to `ClaudeCLI.resolve()` which
    /// checks a list of known install paths and falls back to a shell
    /// lookup to handle the LaunchAgent-with-minimal-PATH scenario.
    func resolveClaudePath() -> String? {
        if hasResolvedClaudePath { return cachedClaudePath }
        hasResolvedClaudePath = true
        cachedClaudePath = ClaudeCLI.resolve()
        return cachedClaudePath
    }

    /// Test hook: force a specific `claude` path (or nil) without re-resolving.
    public func overrideClaudePath(_ path: String?) {
        cachedClaudePath = path
        hasResolvedClaudePath = true
    }

    // MARK: - Subprocess runners

    /// Full-featured runner with timeout. Returns captured stdout or nil on
    /// failure/timeout. `environment` overrides are merged on top of the
    /// current process environment.
    private func runProcess(
        launchPath: String,
        arguments: [String],
        timeout: TimeInterval,
        environment: [String: String] = [:]
    ) async -> String? {
        await withCheckedContinuation { (cont: CheckedContinuation<String?, Never>) in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: launchPath)
            process.arguments = arguments

            if !environment.isEmpty {
                var merged = ProcessInfo.processInfo.environment
                for (k, v) in environment { merged[k] = v }
                process.environment = merged
            }

            let outPipe = Pipe()
            let errPipe = Pipe()
            process.standardOutput = outPipe
            process.standardError = errPipe
            // Close stdin so the subprocess doesn't wait for input.
            process.standardInput = FileHandle.nullDevice

            let resumeLock = NSLock()
            var resumed = false
            let resumeOnce: (String?) -> Void = { value in
                resumeLock.lock()
                defer { resumeLock.unlock() }
                if resumed { return }
                resumed = true
                cont.resume(returning: value)
            }

            process.terminationHandler = { _ in
                let data = (try? outPipe.fileHandleForReading.readToEnd()) ?? Data()
                let text = String(data: data, encoding: .utf8)
                resumeOnce(text)
            }

            do {
                try process.run()
            } catch {
                resumeOnce(nil)
                return
            }

            // Arm a timeout that terminates the process if it hangs.
            let timer = DispatchSource.makeTimerSource(queue: .global())
            timer.schedule(deadline: .now() + timeout)
            timer.setEventHandler {
                if process.isRunning {
                    process.terminate()
                    DispatchQueue.global().asyncAfter(deadline: .now() + 0.5) {
                        if process.isRunning {
                            kill(process.processIdentifier, SIGKILL)
                        }
                    }
                }
                // Safety net in case terminationHandler is delayed.
                DispatchQueue.global().asyncAfter(deadline: .now() + 1.5) {
                    resumeOnce(nil)
                }
            }
            timer.resume()
        }
    }

    /// Fire-and-forget synchronous runner used only for `command -v`.
    /// 1.5 s ceiling; returns stdout or nil.
    private func runSimple(
        launchPath: String,
        arguments: [String],
        timeout: TimeInterval
    ) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: launchPath)
        process.arguments = arguments
        let out = Pipe()
        let err = Pipe()
        process.standardOutput = out
        process.standardError = err
        process.standardInput = FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            return nil
        }

        // Poll for completion up to timeout.
        let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning, Date() < deadline {
            Thread.sleep(forTimeInterval: 0.05)
        }
        if process.isRunning {
            process.terminate()
            return nil
        }
        guard let data = try? out.fileHandleForReading.readToEnd() else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
