import SwiftUI

struct ConnectionStatusView: View {
    let connection: ConnectionState
    var isStreaming = false

    private var title: String {
        switch connection {
        case .connected: "Connected to Hermes"
        case .connecting: "Connecting…"
        case .reconnecting: "Reconnecting…"
        case .disconnected: "Offline"
        }
    }

    var body: some View {
        HStack(spacing: 8) {
            if connection == .connecting || connection == .reconnecting {
                ProgressView().controlSize(.small).accessibilityHidden(true)
            } else if connection == .connected {
                Circle()
                    .fill(.green)
                    .frame(width: 6, height: 6)
                    .accessibilityHidden(true)
            } else {
                Image(systemName: "wifi.slash")
                    .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                if connection == .connected && isStreaming {
                    Text("Responding")
                        .font(.caption)
                }
            }
        }
        .font(.subheadline)
        .foregroundStyle(.secondary)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(connection == .connected && isStreaming ? "Connected to Hermes. Hermes is responding." : title)
    }
}
