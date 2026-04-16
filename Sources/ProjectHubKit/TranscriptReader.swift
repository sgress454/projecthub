import Foundation

/// Reads Claude Code transcript jsonl files and extracts the final
/// assistant-turn message. Used to feed the classifier after a Stop event.
///
/// Transcript format (per line):
///   {"type":"user","message":{"role":"user","content":"..."}, ...}
///   {"type":"assistant","message":{"role":"assistant","content":[
///     {"type":"text","text":"..."},
///     {"type":"tool_use","name":"...","input":{...}}
///   ]}, ...}
///
/// We iterate from the END of the file backward, stopping at the first
/// assistant entry. `content` may be either a string or an array of blocks;
/// tool_use blocks are ignored — we only concatenate `text` blocks.
public enum TranscriptReader {
    public static func finalAssistantText(fromTranscriptAt url: URL) -> String? {
        guard let data = try? Data(contentsOf: url),
              let fullText = String(data: data, encoding: .utf8)
        else { return nil }
        let lines = fullText.split(separator: "\n", omittingEmptySubsequences: true)
        for line in lines.reversed() {
            guard let obj = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any]
            else { continue }
            let type = obj["type"] as? String
            let message = obj["message"] as? [String: Any]
            // Some transcript variants nest under "message"; others put role at
            // top level. Try both.
            let role = message?["role"] as? String ?? obj["role"] as? String
            guard type == "assistant" || role == "assistant" else { continue }
            if let extracted = extractText(from: message ?? obj) {
                return extracted
            }
        }
        return nil
    }

    /// Pulls plain-text content from a message object. Handles the two
    /// shapes we encounter: a bare string or an array of typed blocks.
    public static func extractText(from message: [String: Any]) -> String? {
        if let s = message["content"] as? String {
            return s.isEmpty ? nil : s
        }
        guard let blocks = message["content"] as? [[String: Any]] else { return nil }
        var pieces: [String] = []
        for block in blocks {
            if (block["type"] as? String) == "text",
               let text = block["text"] as? String, !text.isEmpty
            {
                pieces.append(text)
            }
        }
        return pieces.isEmpty ? nil : pieces.joined(separator: "\n")
    }
}
