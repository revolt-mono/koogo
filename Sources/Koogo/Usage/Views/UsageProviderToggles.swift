import SwiftUI

/// One toggle per provider; a disabled provider is left out of every refresh.
struct UsageProviderToggles: View {
    @Environment(UsageModel.self) private var usageModel

    var body: some View {
        ForEach(UsageProvider.allCases, id: \.self) { provider in
            Toggle(
                provider.title,
                isOn: Binding(
                    get: { usageModel.enabledProviders.contains(provider) },
                    set: { usageModel.setEnabled($0, for: provider) }
                )
            )
        }
    }
}
