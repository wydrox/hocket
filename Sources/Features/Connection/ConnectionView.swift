import SwiftUI

struct ConnectionView: View {
    @Bindable var store: HermesStore
    let isInitialSetup: Bool
    @Environment(\.dismiss) private var dismiss
    @State private var address = ""
    @State private var token = ""
    @State private var username = ""
    @State private var password = ""
    @State private var usesAccessToken = false
    @State private var isConnecting = false
    @State private var validationError: String?
    @FocusState private var focusedField: Field?

    private enum Field: Hashable { case address, username, password, token }

    private var validAddress: Bool {
        guard let url = URL(string: address.trimmingCharacters(in: .whitespacesAndNewlines)) else { return false }
        return url.scheme?.lowercased() == "https" && url.host != nil && url.user == nil && url.password == nil && url.query == nil && url.fragment == nil
    }

    var body: some View {
        Form {
            Section {
                Label("Your Hermes, within reach.", systemImage: "bubble.left.and.bubble.right")
                    .font(.title2.bold())
                    .padding(.vertical, 8)
                Text("Connect to your Hermes server to continue your conversations.")
                    .foregroundStyle(.secondary)
            }
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Server Address").font(.subheadline)
                    TextField("Server Address", text: $address, prompt: Text("https://hermes.example.com"))
                        .keyboardType(.URL)
                        .textContentType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($focusedField, equals: .address)
                        .submitLabel(.next)
                        .onSubmit { focusedField = usesAccessToken ? .token : .username }
                }
                if !usesAccessToken {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Username").font(.subheadline)
                        TextField("Username", text: $username)
                            .textContentType(.username)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .focused($focusedField, equals: .username)
                            .submitLabel(.next)
                            .onSubmit { focusedField = .password }
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Password").font(.subheadline)
                        SecureField("Password", text: $password)
                            .textContentType(.password)
                            .focused($focusedField, equals: .password)
                            .submitLabel(.go)
                            .onSubmit { connect() }
                    }
                }
            } header: {
                Text("Connection")
            } footer: {
                Text("Messages and attachments are sent to this server. Your sign-in token is stored in this device’s Keychain.")
            }
            Section {
                DisclosureGroup("Advanced Connection") {
                    Toggle("Use an Access Token", isOn: $usesAccessToken)
                    if usesAccessToken {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Access Token").font(.subheadline)
                            SecureField("Access Token", text: $token)
                                .textContentType(.password)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .focused($focusedField, equals: .token)
                                .submitLabel(.go)
                                .onSubmit { connect() }
                        }
                    }
                }
            }
            if let error = validationError ?? store.lastError {
                Section {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.red)
                        .accessibilityAddTraits(.isStaticText)
                }
            }
            Section {
                Button(action: connect) {
                    HStack {
                        if isConnecting { ProgressView() }
                        Text(isConnecting ? "Connecting…" : usesAccessToken ? "Connect" : "Sign In")
                            .frame(maxWidth: .infinity)
                    }
                    .frame(minHeight: 44)
                }
                .buttonStyle(.borderedProminent)
                .disabled(isConnecting || !hasCredentials)
            }
        }
        .navigationTitle(isInitialSetup ? "Hermes Pocket" : "Edit Connection")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !isInitialSetup {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
        }
        .onAppear { address = store.endpoint }
        .onDisappear { password = ""; token = "" }
        .disabled(isConnecting)
        .interactiveDismissDisabled(isConnecting)
    }

    private func connect() {
        guard !isConnecting, hasCredentials else { return }
        guard validAddress else {
            validationError = "Enter a valid HTTPS server address without credentials or query parameters."
            focusedField = .address
            return
        }
        validationError = nil
        isConnecting = true
        focusedField = nil
        Task {
            let endpoint = address.trimmingCharacters(in: .whitespacesAndNewlines)
            if usesAccessToken {
                await store.connect(endpoint: endpoint, token: token)
            } else {
                await store.connect(endpoint: endpoint, username: username, password: password)
            }
            isConnecting = false
            if store.connection == .connected {
                token = ""
                password = ""
                if !isInitialSetup { dismiss() }
            }
        }
    }

    private var hasCredentials: Bool {
        usesAccessToken ? !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty : !username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !password.isEmpty
    }
}
