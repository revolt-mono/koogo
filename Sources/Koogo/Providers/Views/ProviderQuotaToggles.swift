import SwiftUI

struct ProviderQuotaToggles: View {
    @Environment(ProviderPreferences.self) private var preferences

    var body: some View {
        ForEach(preferences.order.compactMap(\.quota), id: \.self) { provider in
            Toggle(
                provider.provider.title,
                isOn: Binding(
                    get: { preferences.quotaEnabled.contains(provider) },
                    set: { preferences.setQuota($0, for: provider) }
                )
            )
        }
    }
}
