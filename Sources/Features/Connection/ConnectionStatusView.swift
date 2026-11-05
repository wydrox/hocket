import SwiftUI

struct ConnectionStatusView: View {
    let connection: ConnectionState
    var isStreaming = false

    private var title: String {
        switch connection {
        case .connected: isStreaming ? "Responding" : "Connected"
        case .connecting: "Connecting…"
        case .reconnecting: "Reconnecting…"
        case .disconnected: "Offline"
        }
    }

    var body: some View {
        HStack(spacing: 8) {
            if connection == .connecting || connection == .reconnecting {
                ProgressView().controlSize(.small)
            } else {
                Image(systemName: connection == .connected ? "point.topleft.down.to.point.bottomright.curvepath" : "wifi.slash")
            }
            Text(title)
        }
        .font(.subheadline)
        .foregroundStyle(.secondary)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(connection == .connected && isStreaming ? "Connected. Hermes is responding." : title)
    }
}
