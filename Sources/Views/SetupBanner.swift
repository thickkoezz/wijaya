import SwiftUI
import AppKit

struct SetupBanner: View {
    let status: FuseStatus

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .font(.title2)

            VStack(alignment: .leading, spacing: 6) {
                Text(status.title)
                    .font(.headline)
                ForEach(status.detail, id: \.self) { line in
                    Text(line)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }

            Spacer()

            Button("Buka System Settings") {
                if let url = URL(string: "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension") {
                    NSWorkspace.shared.open(url)
                }
            }
            .controlSize(.small)
        }
        .padding(12)
        .background(Color.orange.opacity(0.12))
    }
}
