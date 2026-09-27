import SwiftUI

struct QuotaPreferences: DynamicProperty {
    @AppStorage("fetch-codex-quota") var fetchCodex = true
    @AppStorage("fetch-claude-quota") var fetchClaude = true
    @AppStorage("fetch-grok-quota") var fetchGrok = true
}
