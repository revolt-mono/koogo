/// response history supplies server-applied effort per prompt and model, without billing any usage.
struct GrokHistoryLogParser: UsageLogParser {
    private var promptIndex: UInt64?
    private var counts: [UInt64: [String: [String: Int]]] = [:]

    mutating func parse(_ line: UnsafeRawBufferPointer) throws -> UsageLineOutcome? {
        do {
            guard JSONObjectReader(line) != nil else {
                return nil
            }
            let record = JSONValue(bytes: line)
            guard let kind = try record.member("type") else {
                return nil
            }
            switch kind {
            case "user":
                if let index = try record.member("prompt_index")?.integer(UInt64.self) {
                    promptIndex = index
                }
            case "assistant":
                guard let index = promptIndex,
                    let model = try record.member("model_id")?.string(), !model.isEmpty,
                    let effort = try record.member("reasoning_effort")?.string(), !effort.isEmpty
                else {
                    return nil
                }
                counts[index, default: [:]][model, default: [:]][effort, default: 0] += 1
            default: break
            }
            return nil
        } catch {
            promptIndex = nil
            throw error
        }
    }

    /// one effort vote per billed prompt, using the most frequent response effort for that model.
    func effort(for promptIndex: UInt64, model: String) -> String? {
        counts[promptIndex]?[model]?.max { lhs, rhs in
            lhs.value == rhs.value ? lhs.key > rhs.key : lhs.value < rhs.value
        }?.key
    }
}
