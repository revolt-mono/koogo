import SwiftUI

struct ProviderQuotaToggles: View {
    @Environment(ProviderPreferences.self) private var preferences

    var body: some View {
        ForEach(preferences.order.compactMap(\.quota), id: \.self) { provider in
            Toggle(
                provider.provider.title,
                isOn: Binding(
                    get: { preferences[quota: provider] },
                    set: { preferences[quota: provider] = $0 }
                )
            )
            .disabled(!preferences[usage: provider.provider])
        }
    }
}
