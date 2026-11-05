import SwiftUI

struct HelpView: View {
    var body: some View {
        Form {
            Section("Connect to Your Server") {
                Text("Use a secure HTTPS address reachable from your device and sign in to your Hermes server. If your server is private, connect your device to its VPN first.")
                Text("A connection can pause when hocket is in the background. Reopen the app to reconnect and check the latest state.")
            }
            Section("Messages and Attachments") {
                Text("Hermes responses are AI-generated and can contain mistakes. Check important information before acting on it.")
                Text("Choosing Upload Photo or Upload File uploads the selection to your Hermes server immediately. Send includes the uploaded attachment in your conversation. Removing it from the draft doesn’t delete the original or the server upload.")
                Text("Attach up to 10 files, each under 16 MB. Your server may apply additional format or size limits.")
                Text("Use your keyboard’s dictation control to dictate a message. hocket doesn’t record microphone audio.")
            }
            Section("Your Controls") {
                Text("Commands and session choices come from your server. Available controls can change by server version, model or provider.")
                Text("Review an approval request before answering. Leaving it open does not approve it.")
            }
            Section("Privacy") {
                Text("Your sign-in token is stored in this device’s Keychain. Messages and attachments are processed by your Hermes server and its configured providers.")
                Text("Disconnect removes saved access from this device. Revoke or rotate access on your server if a token is exposed. The server controls conversation retention.")
            }
        }
        .navigationTitle("Help and Privacy")
        .navigationBarTitleDisplayMode(.inline)
    }
}
