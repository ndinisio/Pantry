import SwiftUI

/// Where the intelligence comes from, and what it costs the user in privacy.
///
/// The order of this screen is the order of the provider chain, so what you see is
/// what actually happens. The on-device model is first because it is the one that
/// sends nothing anywhere; the key field is last because shipping a key in an app is
/// the arrangement this screen is trying to talk people out of.
struct AISettingsView: View {

    @Environment(AppEnvironment.self) private var appEnvironment

    @State private var availableProviders: [String] = []
    @State private var onDeviceReason: String?
    @State private var groqKey: String = ""
    @State private var proxyURL: String = ""
    @State private var proxyToken: String = ""
    @State private var isEditingGroqKey = false
    @State private var isEditingProxy = false
    @AppStorage(DeveloperSettings.sampleAIResponsesKey) private var useSampleResponses = false

    var body: some View {
        Form {
            Section {
                if availableProviders.isEmpty {
                    Label(String(localized: "Nothing set up"), systemImage: "sparkles")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(Array(availableProviders.enumerated()), id: \.offset) { index, name in
                        LabeledContent {
                            Text(index == 0 ? String(localized: "Preferred") : String(localized: "Fallback"))
                                .foregroundStyle(.secondary)
                        } label: {
                            Text(name)
                        }
                    }
                }
            } header: {
                Text("In Use")
            } footer: {
                Text("Pantry tries these in order and stops at the first that answers. Everything else in the app works whether or not any of them are available.")
            }

            Section {
                if let onDeviceReason {
                    Label(onDeviceReason, systemImage: "iphone.slash")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else {
                    Label(String(localized: "Available"), systemImage: "checkmark.circle")
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("On Device")
            } footer: {
                Text("Apple's on-device model. Nothing leaves your iPhone, there's no key to set up and it works without a connection.")
            }

            Section {
                if isEditingProxy {
                    TextField(String(localized: "https://example.com/pantry-ai"), text: $proxyURL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                    SecureField(String(localized: "Token (optional)"), text: $proxyToken)
                    Button(String(localized: "Save")) {
                        SecretStore.set(proxyURL.trimmingCharacters(in: .whitespaces), for: .proxyURL)
                        SecretStore.set(proxyToken.isEmpty ? nil : proxyToken, for: .proxyToken)
                        isEditingProxy = false
                        proxyToken = ""
                        refresh()
                    }
                    .disabled(!proxyURL.lowercased().hasPrefix("https://"))
                    Button(String(localized: "Cancel"), role: .cancel) {
                        isEditingProxy = false
                        proxyToken = ""
                    }
                } else if let url = SecretStore.value(for: .proxyURL) {
                    LabeledContent(String(localized: "Endpoint"), value: url)
                    Button(String(localized: "Change")) {
                        proxyURL = url
                        isEditingProxy = true
                    }
                    Button(String(localized: "Remove"), role: .destructive) {
                        SecretStore.remove(.proxyURL)
                        SecretStore.remove(.proxyToken)
                        refresh()
                    }
                } else {
                    Button(String(localized: "Set Up a Proxy")) {
                        proxyURL = "https://"
                        isEditingProxy = true
                    }
                }
            } header: {
                Text("Your Own Backend")
            } footer: {
                Text("The arrangement to prefer: your app talks to a service you control, and that service holds the model credential. Nothing secret ships inside Pantry. HTTPS only.")
            }

            Section {
                if isEditingGroqKey {
                    SecureField(String(localized: "API key"), text: $groqKey)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Button(String(localized: "Save to Keychain")) {
                        SecretStore.set(groqKey.trimmingCharacters(in: .whitespaces), for: .groqAPIKey)
                        groqKey = ""
                        isEditingGroqKey = false
                        refresh()
                    }
                    .disabled(groqKey.trimmingCharacters(in: .whitespaces).isEmpty)
                    Button(String(localized: "Cancel"), role: .cancel) {
                        groqKey = ""
                        isEditingGroqKey = false
                    }
                } else if let masked = SecretStore.maskedValue(for: .groqAPIKey) {
                    LabeledContent(String(localized: "Key"), value: masked)
                    Button(String(localized: "Replace")) { isEditingGroqKey = true }
                    Button(String(localized: "Remove"), role: .destructive) {
                        SecretStore.remove(.groqAPIKey)
                        refresh()
                    }
                } else {
                    Button(String(localized: "Add a Key")) { isEditingGroqKey = true }
                }
            } header: {
                Text("Groq")
            } footer: {
                Text("Stored in the device Keychain, never in the app's code or settings files. Suitable for your own use; for anything you'd distribute, use a backend instead.")
            }

            #if DEBUG
            Section {
                Toggle(String(localized: "Use Sample Responses"), isOn: $useSampleResponses)
                    .onChange(of: useSampleResponses) { _, _ in
                        appEnvironment.reloadAIConfiguration()
                        refresh()
                    }
            } header: {
                Text("Development")
            } footer: {
                Text("Returns fixed sample content so AI screens can be reviewed without a key or a connection. Everything it produces is labelled as a sample in the interface. Debug builds only.")
            }
            #endif
        }
        .navigationTitle(Text("Intelligence"))
        .task { refresh() }
    }

    private func refresh() {
        onDeviceReason = FoundationModelsProvider().unavailableReason()
        Task {
            availableProviders = await appEnvironment.aiService.availableProviders()
        }
    }
}

#Preview {
    NavigationStack {
        AISettingsView()
    }
    .environment(AppEnvironment())
}
