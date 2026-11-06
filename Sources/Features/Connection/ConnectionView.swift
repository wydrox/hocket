import SwiftUI

struct ConnectionView: View {
    @Bindable var store: HermesStore
    let isInitialSetup: Bool
    @Environment(\.dismiss) private var dismiss
    @State private var address = ""
    @State private var token = ""
    @State private var username = ""
    @State private var password = ""
    @State private var profileName = ""
    @State private var usesAccessToken = false
    @State private var isConnecting = false
    @State private var showsSetup = false
    @State private var hasLoadedEndpoint = false
    @State private var isChecking = false
    @State private var checkTask: Task<Void, Never>?
    @State private var checkID = UUID()
    @State private var checkedSignIn: GatewayPreflight.SignIn?
    @State private var checkError: String?
    @State private var validationError: String?
    @FocusState private var focusedField: Field?

    private enum Field: Hashable { case address, username, password, token, profile }

    private var endpoint: GatewayEndpoint? { try? GatewayEndpoint(address) }

    var body: some View {
        Form {
            Section {
                Label("Your Hermes, within reach.", systemImage: "bubble.left.and.bubble.right")
                    .font(.title2.bold())
                    .padding(.vertical, 8)
                Text("Connect to the Hermes running on your computer or server.")
                    .foregroundStyle(.secondary)
                Button { showsSetup = true } label: {
                    Label("Set Up Hermes", systemImage: "list.number")
                        .frame(minHeight: 44)
                }
                .accessibilityHint("Learn where to click in Hermes, how to reach it from this device, and which login to use.")
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
                Button(action: checkServer) {
                    HStack {
                        if isChecking { ProgressView() }
                        Text(isChecking ? "Checking…" : "Check Server")
                    }
                    .frame(minHeight: 44)
                }
                .disabled(isChecking || address.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                if let checkedSignIn {
                    serverCheckResult(checkedSignIn)
                }
                if let checkError {
                    Label(checkError, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.red)
                }
                if let endpoint {
                    Link("Open Server in Safari", destination: endpoint.origin)
                        .frame(minHeight: 44)
                }
            } header: {
                Text("1. Server Address")
            } footer: {
                Text("Use the HTTPS address of your Hermes gateway. For a private server, connect Tailscale or your VPN first.")
            }
            Section {
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
                Text("2. Sign In")
            } footer: {
                Text("Use your Hermes Username & Password login, not your Nous account or Telegram token. Messages and attachments go to this server. Sign-in tokens are stored in this device’s Keychain.")
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
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Profile Name (Optional)").font(.subheadline)
                        TextField("Profile Name", text: $profileName)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .focused($focusedField, equals: .profile)
                            .submitLabel(.go)
                            .onSubmit { connect() }
                        Text("Leave blank to use the server default. After signing in, choose from available profiles in Threads.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
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
        .accessibilityIdentifier("connection.form")
        .navigationTitle(isInitialSetup ? "hocket" : "Edit Connection")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !isInitialSetup {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
        }
        .sheet(isPresented: $showsSetup) {
            ConnectionGuideView(finishTitle: "Enter Server Details")
        }
        .onAppear {
            if !hasLoadedEndpoint {
                address = store.endpoint
                profileName = store.selectedProfileName ?? ""
                hasLoadedEndpoint = true
            }
        }
        .onChange(of: address) {
            clearCheck()
            clearSignInError()
        }
        .onChange(of: username) { clearSignInError() }
        .onChange(of: password) { clearSignInError() }
        .onChange(of: token) { clearSignInError() }
        .onChange(of: profileName) { clearSignInError() }
        .onChange(of: usesAccessToken) { clearSignInError() }
        .onDisappear { password = ""; token = ""; clearCheck() }
        .disabled(isConnecting)
        .interactiveDismissDisabled(isConnecting)
    }

    private func connect() {
        guard !isConnecting, hasCredentials else { return }
        guard endpoint != nil else {
            validationError = GatewayError.invalidEndpoint.localizedDescription
            focusedField = .address
            return
        }
        clearCheck()
        validationError = nil
        isConnecting = true
        focusedField = nil
        Task {
            let endpoint = address.trimmingCharacters(in: .whitespacesAndNewlines)
            let selectedProfile = profileName.trimmingCharacters(in: .whitespacesAndNewlines)
            if usesAccessToken {
                await store.connect(endpoint: endpoint, token: token, profileName: selectedProfile.isEmpty ? nil : selectedProfile)
            } else {
                await store.connect(endpoint: endpoint, username: username, password: password, profileName: selectedProfile.isEmpty ? nil : selectedProfile)
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

    @ViewBuilder
    private func serverCheckResult(_ result: GatewayPreflight.SignIn) -> some View {
        switch result {
        case .password:
            Label("Server reached. Username & Password is available.", systemImage: "checkmark.circle")
            Text("Sign in below to verify your account and load conversations.")
                .foregroundStyle(.secondary)
        case .otherProvider:
            Label("Server reached. Password sign-in is not available.", systemImage: "exclamationmark.circle")
            Text("This beta cannot use Nous browser sign-in. Ask the server owner to enable Hermes’s Username & Password provider, or use an issued native access token in Advanced Connection.")
        case .notConfigured:
            Label("Server reached. No sign-in provider is configured.", systemImage: "exclamationmark.circle")
            Text("Ask the server owner to enable authenticated access to the Hermes gateway before connecting.")
        }
    }

    private func checkServer() {
        guard !isChecking, !isConnecting else { return }
        guard let endpoint else {
            validationError = GatewayError.invalidEndpoint.localizedDescription
            focusedField = .address
            return
        }
        clearSignInError()
        clearCheck()
        focusedField = nil
        isChecking = true
        let id = checkID
        checkTask = Task {
            do {
                let result = try await GatewayPreflight().check(endpoint)
                guard !Task.isCancelled, checkID == id else { return }
                checkedSignIn = result
            } catch {
                guard !Task.isCancelled, checkID == id else { return }
                checkError = GatewayPreflight.message(for: error)
            }
            isChecking = false
            checkTask = nil
        }
    }

    private func clearCheck() {
        checkID = UUID()
        checkTask?.cancel()
        checkTask = nil
        isChecking = false
        checkedSignIn = nil
        checkError = nil
    }

    private func clearSignInError() {
        validationError = nil
        if !isConnecting { store.lastError = nil }
    }
}
