import SwiftUI

struct ConnectionGuideView: View {
    var finishTitle = "Done"
    @Environment(\.dismiss) private var dismiss
    @State private var step = 0

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Step \(step + 1) of 3")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Label(title, systemImage: symbol)
                        .font(.title2.bold())
                        .accessibilityAddTraits(.isHeader)
                }
                switch step {
                case 0: prepareHermes
                case 1: connectDevice
                default: signIn
                }
                Section {
                    Button(step == 2 ? finishTitle : "Continue") {
                        if step == 2 { dismiss() }
                        else { step += 1 }
                    }
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("setup.continue")
                }
            }
            // Start each step at its heading, including after returning from a long guide.
            .id(step)
            .navigationTitle("Set Up Hermes")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
                if step > 0 {
                    ToolbarItem(placement: .secondaryAction) {
                        Button("Previous Step", systemImage: "chevron.backward") { step -= 1 }
                    }
                }
            }
        }
    }

    private var title: String {
        switch step {
        case 0: "Prepare Hermes"
        case 1: "Connect Your Device"
        default: "Sign In to Hermes"
        }
    }

    private var symbol: String {
        switch step {
        case 0: "desktopcomputer"
        case 1: "network"
        default: "person.crop.circle.badge.checkmark"
        }
    }

    private var prepareHermes: some View {
        Group {
            Section("On the Computer Running Hermes") {
                Text("Keep Hermes running on your computer or server. hocket connects directly to that Hermes gateway; the agent and its tools stay there.")
                Text("You need its HTTPS address and a Hermes username and password. If these are already configured, continue to the next step.")
            }
            Section {
                DisclosureGroup("Where to Click in Hermes") {
                    Text("In Hermes Desktop, using its local connection, open Settings → Web access. This page is not available inside the browser version or a remote connection.")
                    Text("Web access uses a Nous account: sign in under Providers, choose My own URL, enter an existing HTTPS proxy address, then click Start. If Hermes shows Restart gateway, wait for active chats to finish before restarting.")
                    Text("Compatibility: Web access alone does not enable password login for hocket. This beta supports Hermes’s Username & Password provider or a native access token; Nous browser sign-in is not supported yet.")
                    Text("This network provides an HTTP address. hocket needs HTTPS, including on a private network. Hermes does not currently provide a hocket pairing or QR button.")
                }
            } footer: {
                Text("These labels are from Hermes Desktop’s Web access settings. Older versions may not include this page.")
            }
            Section {
                DisclosureGroup("Set Up Username & Password") {
                    Text("Hermes has no password-setup button in Web access. The person who runs the server configures the basic password provider. There is no default hocket username or password.")
                    Text("On that computer, run hermes config edit. Under dashboard.basic_auth, configure username, password_hash and a persistent secret. Use the hash_password helper from plugins.dashboard_auth.basic to generate the password hash. Existing HERMES_DASHBOARD_BASIC_AUTH_* environment settings take precedence.")
                    Text("Serve the canonical gateway through HTTPS with sign-in enabled. For a fixed listener, configure webapp.enabled, webapp.host, webapp.port and webapp.public_url. Apply changes with hermes gateway restart after chats finish, and point your HTTPS proxy to that listener. A standalone hermes serve process does not provide the required shared sessions.")
                    Text("If someone else manages Hermes, ask them for the HTTPS gateway address and Username & Password sign-in. If you already have them, keep the existing setup.")
                }
            }
        }
    }

    private var connectDevice: some View {
        Group {
            Section("Reach the Same Server") {
                Text("For a private Tailscale server, open Tailscale on this iPhone or iPad, sign in to the same tailnet as the Hermes computer, and turn the connection on. Keep it connected while using hocket.")
                Text("If your server uses a different VPN, connect that instead. A public HTTPS server does not require a VPN unless its owner says so.")
            }
            Section("Find the Server Address") {
                Text("Use the HTTPS address provided by the person who configured Hermes. With Tailscale Serve, it may look like https://your-computer.your-tailnet.ts.net:8443. Keep any port number.")
                Text("Open that address in Safari on this device. It should reach your Hermes sign-in page. Return to hocket and enter only the address, without /login, /api, or anything after a question mark.")
                Text("localhost and 127.0.0.1 refer to this device, not your Hermes computer. Use the computer’s reachable HTTPS address.")
            }
        }
    }

    private var signIn: some View {
        Group {
            Section("In hocket") {
                Text("Enter Server Address, then tap Check Server. hocket checks reachability and sign-in options without sending a password or starting a conversation.")
                Text("When Username & Password is available, enter the same credentials used for that option on your Hermes sign-in page, then tap Sign In.")
                Text("These credentials are configured by your server’s owner. A Telegram bot token, model API key, or Nous account password is not a Hermes password login.")
            }
            Section("If You Have an Access Token") {
                Text("Open Advanced Connection and enable Use an Access Token. Enter a native Hermes bearer token issued for this server. Keep it private.")
            }
            Section("After Sign-In") {
                Text("hocket loads the sessions exposed by your gateway. Choose a thread or start a new one. Your sign-in tokens are kept in this device’s Keychain; your password is not saved.")
                Text("Find this guide again in Settings → Help and Privacy → Set Up Hermes.")
            }
        }
    }
}
