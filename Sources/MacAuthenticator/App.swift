import SwiftUI
import AuthenticatorState
import AppKit
import AuthenticatorCore

@main struct MacAuthenticatorApp: App {
    @StateObject private var store = Store()
    var body: some Scene {
        WindowGroup("Mac Authenticator") {
            ContentView().environmentObject(store).frame(minWidth: 760, minHeight: 560)
                .onOpenURL { url in
                    if url.isFileURL { store.readFiles([url]) }
                    else { do { store.add(try OTPImport.parse(text: url.absoluteString)) } catch { store.error = error.localizedDescription } }
                }
        }.defaultSize(width: 1000, height: 720)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button(store.text("Import…")) { store.importing = true }.keyboardShortcut("i", modifiers: .command).disabled(store.locked)
                Button(store.text("Open QR code…")) { store.openFiles() }.keyboardShortcut("o").disabled(store.locked)
                Button(store.text("Paste QR code or link")) { store.paste() }.keyboardShortcut("v", modifiers: [.command, .shift]).disabled(store.locked)
                Divider()
                Button(store.text("Lock")) { store.lock() }.keyboardShortcut("l", modifiers: [.command, .shift])
            }
        }
        Settings { SettingsView().environmentObject(store) }
    }
}
struct ContentView: View {
    @EnvironmentObject var store: Store
    @State private var search = ""
    @State private var manual = false
    @State private var deleting: Account?
    @State private var editing: Account?
    var filtered: [Account] { store.accounts.filter { search.isEmpty || "\($0.name) \($0.issuer)".localizedCaseInsensitiveContains(search) } }
    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Divider()
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 7) {
                        Text(store.text("Your codes")).font(.system(size: 30, weight: .bold, design: .rounded))
                        Text(store.locked ? store.text("Vault locked") : store.text("Accounts: {0} · Only on this Mac", String(store.accounts.count))).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button { store.importing = true } label: { Label(store.text("Import"), systemImage: "square.and.arrow.down") }.buttonStyle(.borderedProminent).controlSize(.large).disabled(store.locked)
                }.padding(28)
                if store.locked { lockedState }
                else if store.accounts.isEmpty { emptyState }
                else {
                    HStack { Image(systemName: "magnifyingglass").foregroundStyle(.secondary); TextField(store.text("Search accounts or services"), text: $search).textFieldStyle(.plain) }
                        .padding(12).background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10)).padding(.horizontal, 28).padding(.bottom, 18)
                    if filtered.isEmpty { ContentUnavailableView(store.text("No matching accounts"), systemImage: "magnifyingglass", description: Text(store.text("Try another account or service name."))) }
                    else {
                        ScrollView {
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 260), spacing: 16)], spacing: 16) {
                                ForEach(filtered) { account in
                                    AccountCard(account: account, onDelete: { deleting = account }, onEdit: { editing = account })
                                }
                            }.padding(.horizontal, 28).padding(.bottom, 24)
                        }
                    }
                }
                Spacer(minLength: 0)
                HStack(spacing: 8) {
                    Image(systemName: store.busy ? "qrcode.viewfinder" : "lock.shield").foregroundStyle(.teal)
                    Text(store.busy ? store.text("Reading QR codes…") : (store.status ?? store.text("Keys protected by the macOS Keychain"))).font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    if store.demo { Text(store.text("DEMO")).font(.caption.bold()).foregroundStyle(.orange) }
                }.padding(.horizontal, 28).padding(.vertical, 16)
            }.background(Color(nsColor: .windowBackgroundColor))
        }
        .sheet(isPresented: $store.importing, onDismiss: { store.session = ImportSession() }) { ImportView().environmentObject(store) }
        .sheet(isPresented: $manual) { ManualView().environmentObject(store) }
        .sheet(item: $editing) { account in EditView(account: account).environmentObject(store) }
        .alert(store.text("Could not complete the action"), isPresented: Binding(get: { store.error != nil }, set: { if !$0 { store.error = nil } })) { Button("OK") { store.error = nil } } message: { Text(store.error ?? "") }
        .alert(store.text("Delete account?"), isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })) {
            Button(store.text("Cancel"), role: .cancel) { deleting = nil }
            Button(store.text("Delete"), role: .destructive) { if let deleting { store.remove(deleting) }; deleting = nil }
        } message: { Text(store.text("Codes for {0} {1} will be removed from this Mac. Make sure you have another way to sign in.", String(deleting?.issuer ?? ""), String(deleting?.name ?? ""))) }
        .onChange(of: store.locked) { _, locked in
            if locked { manual = false; editing = nil; deleting = nil; search = "" }
        }
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            guard !store.locked, !store.busy else { return false }
            Task { @MainActor in
                var urls: [URL] = []
                for provider in providers {
                    let url: URL? = await withCheckedContinuation { continuation in
                        _ = provider.loadObject(ofClass: URL.self) { url, _ in continuation.resume(returning: url) }
                    }
                    if let url { urls.append(url) }
                }
                if !urls.isEmpty { store.readFiles(urls) }
            }
            return true
        }
    }
    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack(spacing: 10) {
                Image(systemName: "shield.lefthalf.filled").font(.system(size: 27)).foregroundStyle(.teal)
                VStack(alignment: .leading, spacing: 2) { Text("Authenticator").font(.headline); Text(store.text("for Mac")).font(.caption).foregroundStyle(.secondary) }
            }.padding(.top, 12)
            Label(store.text("All accounts"), systemImage: "square.grid.2x2.fill").font(.system(size: 13, weight: .semibold)).frame(maxWidth: .infinity, alignment: .leading).padding(12).background(.teal.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 16) {
                Button { store.importing = true } label: { Label(store.text("Transfer from phone"), systemImage: "iphone.and.arrow.forward") }
                Button { manual = true } label: { Label(store.text("Add manually"), systemImage: "plus.circle") }
            }.buttonStyle(.plain).disabled(store.locked)
            Spacer()
            VStack(alignment: .leading, spacing: 8) {
                Label(store.text("Works offline"), systemImage: "wifi.slash").font(.caption.bold())
                Text(store.text("Codes are generated on your device. No account or cloud required.")).font(.caption).foregroundStyle(.secondary).lineSpacing(3)
            }
            Divider()
            SettingsLink { Label(store.text("Settings"), systemImage: "gearshape") }.buttonStyle(.plain)
            Button { store.locked ? store.unlock() : store.lock() } label: { Label(store.locked ? store.text("Unlock") : store.text("Lock"), systemImage: store.locked ? "lock.open" : "lock") }.buttonStyle(.plain)
            Button { NSApp.terminate(nil) } label: { Label(store.text("Quit"), systemImage: "power") }.buttonStyle(.plain).help(store.text("Quit the application (⌘Q)"))
        }.padding(20).frame(width: 200).background(.ultraThinMaterial)
    }
    private var emptyState: some View {
        VStack(spacing: 18) {
            Image(systemName: "qrcode.viewfinder").font(.system(size: 62, weight: .light)).foregroundStyle(.teal).padding(24).background(.teal.opacity(0.08), in: RoundedRectangle(cornerRadius: 30))
            Text(store.text("Your phone’s codes, on your Mac")).font(.title2.bold())
            Text(store.text("Open your Google Authenticator export.\nUse a QR code, an image, or a link.")).multilineTextAlignment(.center).foregroundStyle(.secondary).lineSpacing(5)
            Button(store.text("Import accounts")) { store.importing = true }.buttonStyle(.borderedProminent).controlSize(.large)
            Button(store.text("Add a key manually")) { manual = true }.buttonStyle(.link)
        }.frame(maxWidth: .infinity, maxHeight: .infinity).padding(28)
    }
    private var lockedState: some View {
        VStack(spacing: 20) { Image(systemName: "lock.shield").font(.system(size: 64, weight: .light)).foregroundStyle(.teal); Text(store.text("Your codes are locked")).font(.title2.bold()); Button(store.requiresAuthentication ? store.text("Unlock with Touch ID or password") : store.text("Show codes")) { store.unlock() }.buttonStyle(.borderedProminent).controlSize(.large).disabled(store.authenticating) }.frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
struct AccountCard: View {
    @EnvironmentObject var store: Store
    let account: Account
    var onDelete: () -> Void
    var onEdit: () -> Void
    @State private var copied = false
    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { timeline in
            let remaining = account.period - Int(timeline.date.timeIntervalSince1970) % account.period
            VStack(alignment: .leading, spacing: 18) {
                HStack(spacing: 10) {
                    Text(String((account.issuer.isEmpty ? account.name : account.issuer).prefix(1)).uppercased()).font(.title3.bold()).frame(width: 38, height: 38).background(.teal.opacity(0.12), in: RoundedRectangle(cornerRadius: 10)).foregroundStyle(.teal)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(account.issuer.isEmpty ? store.text("Account") : account.issuer).font(.headline).lineLimit(1)
                        Text(account.name).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Spacer(minLength: 0)
                    Menu { Button(store.text("Rename"), action: onEdit); Button(store.text("Delete…"), role: .destructive, action: onDelete) } label: { Image(systemName: "ellipsis") }.menuStyle(.borderlessButton).fixedSize()
                }
                HStack {
                    Button {
                        store.copy(account); copied = true
                        Task { try? await Task.sleep(for: .seconds(2)); copied = false }
                    } label: {
                        Text(formatted((try? account.code(at: timeline.date)) ?? "—")).font(.system(size: 32, weight: .medium, design: .monospaced)).foregroundStyle(remaining <= 5 && account.kind == .totp ? .orange : .primary).contentTransition(.numericText())
                    }.buttonStyle(.plain).help(store.text("Copy code")).accessibilityLabel(store.text("Copy code for {0} {1}", String(account.issuer), String(account.name)))
                    Spacer()
                    Image(systemName: copied ? "checkmark" : "doc.on.doc").foregroundStyle(copied ? .teal : .secondary).onTapGesture { store.copy(account); copied = true; Task { try? await Task.sleep(for: .seconds(2)); copied = false } }
                }
                if account.kind == .totp {
                    HStack(spacing: 10) { ProgressView(value: Double(remaining), total: Double(account.period)).tint(remaining <= 5 ? .orange : .teal); Text(store.text("{0} s", String(remaining))).font(.caption.monospacedDigit()).foregroundStyle(.secondary).frame(width: 35, alignment: .trailing) }
                } else {
                    HStack { Text("HOTP · \(account.counter)").font(.caption).foregroundStyle(.secondary); Spacer(); Button(store.text("Next code")) { store.advance(account) }.font(.caption) }
                }
            }.padding(20).background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 16)).overlay(RoundedRectangle(cornerRadius: 16).stroke(.primary.opacity(0.06), lineWidth: 1))
        }
    }
    private func formatted(_ code: String) -> String { let middle = code.index(code.startIndex, offsetBy: code.count / 2); return String(code[..<middle]) + " " + code[middle...] }
}
