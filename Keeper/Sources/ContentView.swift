import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct ContentView: View {
    @EnvironmentObject var p: Pipeline
    @State private var showLog = false
    @State private var dropTargeted = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                captureBox
                checkBox
                archiveBox
                installBox
                DisclosureGroup("Log", isExpanded: $showLog) {
                    ScrollView {
                        Text(p.log.isEmpty ? "Nothing yet." : p.log)
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(6)
                    }
                    .frame(height: 200)
                    .background(Color(nsColor: .textBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                }
            }
            .padding(20)
        }
        .dropDestination(for: URL.self) { urls, _ in
            guard !p.busy, !p.watching,
                  let url = urls.first(where: { $0.pathExtension.lowercased() == "pkg" }) else { return false }
            p.openPackage(url)
            return true
        } isTargeted: { dropTargeted = $0 }
        .overlay {
            if dropTargeted {
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.accentColor, lineWidth: 3)
                    .padding(4)
                    .allowsHitTesting(false)
            }
        }
    }

    // MARK: Sections

    private var captureBox: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                Text("Click Start watching, then request the version in the App Store with Proxyman and Frida. Keeper keeps the package before the App Store deletes it. You can also drop an archived .pkg on this window.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 10) {
                    if p.watching {
                        ProgressView().controlSize(.small)
                        Button("Stop") { p.stopWatching() }
                    } else {
                        Button("Start watching") { p.startWatching() }
                            .keyboardShortcut(.defaultAction)
                            .disabled(p.busy)
                        Button("Open package…") { openPackagePanel() }
                            .disabled(p.busy)
                    }
                    Spacer()
                }
                Toggle("Always watch as administrator", isOn: $p.alwaysAdmin)
                    .disabled(p.watching)
                Text(p.watchStatus)
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(6)
        } label: {
            Label("1. Capture", systemImage: "arrow.down.circle")
        }
    }

    private var checkBox: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                if let url = p.pkgURL {
                    Text(url.lastPathComponent).font(.headline)
                }
                StatusRow(title: "Signature", result: p.signature)
                StatusRow(title: "Gatekeeper", result: p.gatekeeper)
                StatusRow(title: "Contents", result: p.contents)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(6)
        } label: {
            Label("2. Check", systemImage: "checkmark.shield")
        }
    }

    private var archiveBox: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Folder:")
                    Text(p.archiveFolder.path)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer()
                    Button("Change…") { chooseArchiveFolder() }
                        .disabled(p.busy || p.watching)
                }
                StatusRow(title: "Saved", result: p.archive)
                if let archived = p.archivedURL {
                    Button("Show in Finder") {
                        NSWorkspace.shared.activateFileViewerSelecting([archived])
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(6)
        } label: {
            Label("3. Archive", systemImage: "archivebox")
        }
    }

    private var installBox: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                Text("Copies the app to /Applications. macOS asks for an administrator name and password.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 10) {
                    Button(installTitle) { p.installApp() }
                        .disabled(!p.canInstall || p.busy || p.watching)
                    if let installed = p.installedURL {
                        Button("Open \(installed.deletingPathExtension().lastPathComponent)") {
                            NSWorkspace.shared.open(installed)
                        }
                    }
                    Spacer()
                }
                StatusRow(title: "Install", result: p.install)
                StatusRow(title: "Verify", result: p.verify)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(6)
        } label: {
            Label("4. Install", systemImage: "square.and.arrow.down.on.square")
        }
    }

    private var installTitle: String {
        if let info = p.appInfo { return "Install \(info.name) \(info.version)" }
        return "Install"
    }

    // MARK: Panels

    private func openPackagePanel() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "pkg") ?? .data]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        if panel.runModal() == .OK, let url = panel.url {
            p.openPackage(url)
        }
    }

    private func chooseArchiveFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "Choose"
        panel.directoryURL = p.archiveFolder
        if panel.runModal() == .OK, let url = panel.url {
            p.archiveFolder = url
        }
    }
}

struct StatusRow: View {
    let title: String
    let result: CheckResult

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            icon.frame(width: 16)
            Text(title).frame(width: 80, alignment: .leading)
            Text(result.detail.isEmpty ? "–" : result.detail)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private var icon: some View {
        switch result.state {
        case .idle:
            Image(systemName: "circle").foregroundStyle(.tertiary)
        case .running:
            ProgressView().controlSize(.small)
        case .ok:
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        case .warning:
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
        case .failed:
            Image(systemName: "xmark.octagon.fill").foregroundStyle(.red)
        }
    }
}
