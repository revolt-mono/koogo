import SwiftUI

/// One toggle per provider with a quota, in the given order; a switched-off provider is neither read
/// nor shown.
struct QuotaProviderToggles: View {
    @Environment(QuotaModel.self) private var quotaModel

    let order: [Provider]

    var body: some View {
        ForEach(order.filter(quotaModel.providers.contains), id: \.self) { provider in
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
