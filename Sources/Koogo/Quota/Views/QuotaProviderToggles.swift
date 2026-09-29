import SwiftUI

/// One toggle per provider with a quota; a switched-off provider is neither read nor shown.
struct QuotaProviderToggles: View {
    @Environment(QuotaModel.self) private var quotaModel

    var body: some View {
        ForEach(quotaModel.providers, id: \.self) { provider in
            Toggle(
                provider.title,
                isOn: Binding(
                    get: { quotaModel.isEnabled(provider) },
                    set: { quotaModel.setEnabled($0, for: provider) }
                )
            )
        }
    }
}
