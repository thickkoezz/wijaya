import SwiftUI
import AppKit
import Combine

struct ContentView: View {
    @StateObject private var vm = VolumeListViewModel()

    var body: some View {
        VStack(spacing: 0) {
            if !vm.fuseStatus.hasUsableBackend {
                SetupBanner(status: vm.fuseStatus)
                Divider()
            }
            if vm.needsFullDiskAccess {
                GuidanceBanner(
                    title: "Akses disk diblokir macOS (Full Disk Access)",
                    lines: [
                        "macOS (Sequoia+) memblokir akses /dev/disk walau sebagai root.",
                        "System Settings → Privacy & Security → Full Disk Access, tambahkan:",
                        "  • \(vm.fuseStatus.ntfs3gPath ?? "/usr/local/bin/ntfs-3g")",
                        "  • /bin/bash",
                        "  (dan aplikasi Wijaya)"
                    ]
                )
                Divider()
            }
            volumeList
            Divider()
            LogPane(entries: vm.logs)
        }
        .frame(minWidth: 780, minHeight: 560)
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Button {
                    vm.toggleAutoMount()
                } label: {
                    Label(
                        vm.autoMountEnabled ? "Auto-mount: ON" : "Auto-mount: OFF",
                        systemImage: vm.autoMountEnabled ? "bolt.fill" : "bolt.slash"
                    )
                }
                .disabled(vm.autoMountBusy)
                .help("Mount NTFS read-write otomatis saat HDD dicolok (latar belakang, tanpa prompt)")
            }
            ToolbarItem(placement: .automatic) {
                backendMenu
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    vm.refresh()
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .disabled(vm.isRefreshing)
                .help("Muat ulang daftar volume")
            }
        }
        .task { vm.bootstrap() }
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didMountNotification)) { _ in vm.refresh() }
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didUnmountNotification)) { _ in vm.refresh() }
        .onReceive(NotificationCenter.default.publisher(for: .wijayaRefresh)) { _ in vm.refresh() }
    }

    @ViewBuilder
    private var backendMenu: some View {
        let backends = vm.fuseStatus.availableBackends
        Menu {
            ForEach(backends) { backend in
                Button {
                    vm.selectBackend(backend)
                } label: {
                    if vm.selectedBackend == backend {
                        Label(backend.displayName, systemImage: "checkmark")
                    } else {
                        Text(backend.displayName)
                    }
                }
            }
        } label: {
            Label("Backend: \(vm.selectedBackend?.displayName ?? "—")", systemImage: "gearshape.2")
        }
        .disabled(backends.count < 2)
        .help("Pilih backend FUSE (macFUSE atau FUSE-T)")
    }

    private var volumeList: some View {
        Group {
            if vm.volumes.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "externaldrive")
                        .font(.system(size: 42))
                        .foregroundStyle(.secondary)
                    Text("Tidak ada volume yang terdeteksi")
                        .foregroundStyle(.secondary)
                    Text("Colok HDD/USB lalu tekan Refresh.")
                        .font(.callout)
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                // ScrollView + LazyVStack (bukan List): tooltip `.help()` pada tombol ikon
                // andal muncul di macOS. Di dalam List, tooltip kadang tidak tampil.
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(vm.volumes) { volume in
                            VolumeRow(
                                volume: volume,
                                isBusy: vm.busyVolumeID == volume.id,
                                onMount: { vm.mountReadWrite(volume) },
                                onForceMount: { vm.forceMountReadWrite(volume) },
                                onMountReadOnly: { vm.mountReadOnly(volume) },
                                onUnmount: { vm.unmount(volume) },
                                onEject: { vm.eject(volume) },
                                onRepair: { vm.repair(volume) },
                                onReveal: { vm.reveal(volume) }
                            )
                            .padding(.horizontal, 14)

                            Divider()
                        }
                    }
                    .padding(.vertical, 2)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
}
