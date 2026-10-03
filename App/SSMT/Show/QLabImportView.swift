import AppKit
import SSMTCore
import SwiftUI
import UniformTypeIdentifiers

/// Import of a QLab show: from a running QLab (exact) or from a .qlab4 / .qlab5 file (best effort).
struct QLabImportView: View {
    @EnvironmentObject var show: ShowStore
    @EnvironmentObject var loc: Localizer
    @State private var host = "127.0.0.1"
    @State private var passcode = ""
    @State private var client: QLabClient?
    @State private var workspaces: [QLabClient.Workspace] = []
    @State private var chosen: QLabClient.Workspace?
    @State private var busy = false
    @State private var progress: (Int, Int)?
    @State private var error: String?
    @State private var report: QLabImport.Report?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(loc.t("qlab.title")).font(Theme.heading(17))
                Spacer()
                Button(loc.t("settings.done")) { client?.close(); show.showQLabImport = false }
                    .buttonStyle(SSMTButtonStyle(kind: .primary))
            }
            if let report {
                reportView(report)
            } else {
                Text(loc.t("qlab.intro")).font(.system(size: 12)).foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                live
                file
                if let error {
                    Label(error, systemImage: "exclamationmark.triangle.fill").font(.system(size: 12))
                        .foregroundStyle(Theme.statusError).fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(20)
        .frame(width: 600, height: 560, alignment: .topLeading)
        .background(Backdrop())
        .onAppear {
            if let url = show.pendingQLabFile {
                show.pendingQLabFile = nil
                importFile(url)
            }
        }
    }

    // MARK: From a running QLab

    private var live: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(loc.t("qlab.live"), systemImage: "antenna.radiowaves.left.and.right").font(.system(size: 14, weight: .semibold))
            Text(loc.t("qlab.live.howto")).font(.system(size: 12)).foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                TextField("127.0.0.1", text: $host).textFieldStyle(.roundedBorder).frame(width: 160)
                SecureField(loc.t("qlab.passcode"), text: $passcode).textFieldStyle(.roundedBorder).frame(width: 140)
                Button(loc.t("qlab.connect")) { connect() }.buttonStyle(SSMTButtonStyle()).disabled(busy)
                if busy && progress == nil { ProgressView().controlSize(.small) }
            }
            if !workspaces.isEmpty {
                Picker(loc.t("qlab.workspace"), selection: $chosen) {
                    ForEach(workspaces) { Text($0.name).tag(Optional($0)) }
                }
                .frame(width: 400)
                HStack {
                    Button(loc.t("qlab.import")) { importLive() }.buttonStyle(SSMTButtonStyle(kind: .primary)).disabled(busy || chosen == nil)
                    if let p = progress {
                        ProgressView(value: Double(p.0), total: Double(max(1, p.1))).frame(width: 180)
                        Text("\(p.0) / \(p.1)").font(Theme.mono(11)).foregroundStyle(Theme.textSecondary)
                    }
                }
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white.opacity(0.04)))
    }

    private func connect() {
        error = nil
        busy = true
        client?.close()
        let c = QLabClient(host: host.trimmingCharacters(in: .whitespaces))
        client = c
        Task {
            do {
                try await c.connect()
                let list = try await c.workspaces()
                workspaces = list
                chosen = list.first
                if list.isEmpty { error = loc.t("qlab.noWorkspaces") }
            } catch {
                self.error = loc.t("qlab.connectFailed") + " (\(error.localizedDescription))"
            }
            busy = false
        }
    }

    private func importLive() {
        guard let c = client, let ws = chosen else { return }
        busy = true
        error = nil
        progress = (0, 0)
        let code = passcode
        Task {
            do {
                let lists = try await c.readWorkspace(ws, passcode: code) { done, total in
                    Task { @MainActor in progress = (done, total) }
                }
                show.showMode = false
                report = show.adoptImported(lists, name: (ws.name as NSString).deletingPathExtension, baseFolder: nil)
            } catch {
                self.error = loc.t("qlab.readFailed") + " (\(error.localizedDescription))"
            }
            busy = false
            progress = nil
        }
    }

    // MARK: From a file

    private var file: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(loc.t("qlab.file"), systemImage: "doc").font(.system(size: 14, weight: .semibold))
            Text(loc.t("qlab.file.hint")).font(.system(size: 12)).foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Button(loc.t("qlab.file.open")) { openFile() }.buttonStyle(SSMTButtonStyle())
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white.opacity(0.04)))
    }

    private func openFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = ["qlab5", "qlab4", "qlab3"].compactMap { UTType(filenameExtension: $0) } + [.data, .package]
        panel.treatsFilePackagesAsDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        importFile(url)
    }

    private func importFile(_ url: URL) {
        error = nil
        var candidates: [URL] = []
        var isDir: ObjCBool = false
        if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue {
            // A package: try its files, largest first.
            let files = (FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey])?.allObjects as? [URL]) ?? []
            candidates = files.sorted {
                ((try? $0.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) > ((try? $1.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
            }
        } else {
            candidates = [url]
        }
        for f in candidates {
            guard let data = try? Data(contentsOf: f), let lists = QLabImport.lists(fromFile: data) else { continue }
            show.showMode = false
            report = show.adoptImported(lists, name: url.deletingPathExtension().lastPathComponent, baseFolder: url.deletingLastPathComponent())
            return
        }
        error = loc.t("qlab.file.unknown")
    }

    // MARK: Report

    private func reportView(_ r: QLabImport.Report) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(loc.t("qlab.done"), systemImage: "checkmark.circle.fill").font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.statusGood)
            Text(String(format: loc.t("qlab.done.counts"), r.cues, r.audio, r.lists, r.banks)).font(.system(size: 13))
            if !r.unsupported.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text(loc.t("qlab.unsupported")).font(.system(size: 12, weight: .semibold))
                    ForEach(r.unsupported.sorted { $0.key < $1.key }, id: \.key) { k, v in
                        Text("• \(k): \(v)").font(.system(size: 12)).foregroundStyle(Theme.textSecondary)
                    }
                }
            }
            if r.lostTargets > 0 {
                Text(String(format: loc.t("qlab.lostTargets"), r.lostTargets)).font(.system(size: 12)).foregroundStyle(Theme.statusWarning)
            }
            if !show.missingFiles.isEmpty {
                HStack {
                    Text(String(format: loc.t("show.missing"), show.missingFiles.count)).font(.system(size: 12)).foregroundStyle(Theme.statusWarning)
                    Button(loc.t("show.relink")) { show.relinkMissing() }.buttonStyle(SSMTButtonStyle())
                }
            }
            Text(loc.t("qlab.checkAfter")).font(.system(size: 12)).foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
