import SwiftUI

struct VolumeRow: View {
    let volume: Volume
    let isBusy: Bool
    let onMount: () -> Void
    let onForceMount: () -> Void
    let onMountReadOnly: () -> Void
    let onUnmount: () -> Void
    let onEject: () -> Void
    let onRepair: () -> Void
    let onReveal: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: "externaldrive.fill")
                .font(.title2)
                .foregroundStyle(volume.isExternal ? Color.accentColor : Color.secondary)
                .frame(width: 26)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(volume.displayName)
                        .font(.headline)
                        .lineLimit(1)
                    fsBadge
                }
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer(minLength: 8)

            stateChip

            if isBusy {
                ProgressView().controlSize(.small)
            } else {
                actions
            }
        }
        .padding(.vertical, 4)
    }

    private var subtitle: String {
        var parts = [volume.deviceNode, volume.sizeText]
        if let mountPoint = volume.mountPoint { parts.append(mountPoint) }
        return parts.joined(separator: "  ·  ")
    }

    private var fsBadge: some View {
        Text(volume.fileSystem.displayName)
            .font(.caption2.weight(.bold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color.secondary.opacity(0.15), in: RoundedRectangle(cornerRadius: 4))
    }

    private var stateChip: some View {
        Text(volume.mountState.label)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(chipColor.opacity(0.18), in: Capsule())
            .foregroundStyle(chipColor)
            .fixedSize()
    }

    private var chipColor: Color {
        switch volume.mountState {
        case .ntfsReadWrite, .mountedReadWrite: return .green
        case .appleReadOnly, .ntfsReadOnly, .mountedReadOnly: return .orange
        case .unmounted: return .gray
        case .unsupported: return .red
        }
    }

    @ViewBuilder
    private var actions: some View {
        HStack(spacing: 6) {
            if volume.needsRemountForWrite {
                Button(action: onMount) {
                    Label("Mount Read-Write", systemImage: "pencil.and.outline")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .help("Mount volume NTFS ini sebagai read-write (tanpa prompt setelah akses disiapkan)")

                if volume.isNTFS {
                    Menu {
                        Button("Hapus hiberfil & mount") { onForceMount() }
                        Button("Mount Read-Only") { onMountReadOnly() }
                    } label: {
                        icon("ellipsis.circle")
                    }
                    .menuStyle(.borderlessButton)
                    .controlSize(.small)
                    .menuIndicator(.hidden)
                    .help("Opsi lain: hapus hiberfil (Windows fast-startup), atau mount read-only")
                }
            }
            iconButtonGroup
        }
    }

    /// Ikon dengan area hover yang cukup besar supaya tooltip mudah muncul.
    private func icon(_ name: String) -> some View {
        Image(systemName: name)
            .frame(width: 22, height: 20)
            .contentShape(Rectangle())
    }

    private func iconButton(_ name: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { icon(name) }
            .buttonStyle(.borderless)
            .help(help)
            .accessibilityLabel(help)
    }

    @ViewBuilder
    private var iconButtonGroup: some View {
        HStack(spacing: 4) {
            if volume.mountState.isMounted {
                iconButton("folder", help: "Buka isi volume di Finder", action: onReveal)
                iconButton("eject.circle", help: "Unmount volume (tanpa mencabut disk)", action: onUnmount)
            }
            if volume.isNTFS {
                iconButton("wrench.and.screwdriver", help: "Perbaiki NTFS (ntfsfix) — untuk volume 'dirty'", action: onRepair)
            }
            if volume.isExternal {
                iconButton("eject", help: "Eject disk dengan aman sebelum dicabut", action: onEject)
            }
        }
    }
}
