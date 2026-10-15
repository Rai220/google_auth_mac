import SwiftUI
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
                Button("Импортировать…") { store.importing = true }.keyboardShortcut("i", modifiers: .command).disabled(store.locked)
                Button("Открыть QR-код…") { store.openFiles() }.keyboardShortcut("o").disabled(store.locked)
                Button("Вставить QR-код или ссылку") { store.paste() }.keyboardShortcut("v", modifiers: [.command, .shift]).disabled(store.locked)
                Divider()
                Button("Заблокировать") { store.lock() }.keyboardShortcut("l", modifiers: [.command, .shift])
            }
        }
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
                        Text("Ваши коды").font(.system(size: 30, weight: .bold, design: .rounded))
                        Text(store.locked ? "Хранилище заблокировано" : "\(store.accounts.count) аккаунтов · Только на этом Mac").foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button { store.importing = true } label: { Label("Импорт", systemImage: "square.and.arrow.down") }.buttonStyle(.borderedProminent).controlSize(.large).disabled(store.locked)
                }.padding(28)
                if store.locked { lockedState }
                else if store.accounts.isEmpty { emptyState }
                else {
                    HStack { Image(systemName: "magnifyingglass").foregroundStyle(.secondary); TextField("Найти аккаунт или сервис", text: $search).textFieldStyle(.plain) }
                        .padding(12).background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10)).padding(.horizontal, 28).padding(.bottom, 18)
                    if filtered.isEmpty { ContentUnavailableView.search(text: search) }
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
                    Text(store.busy ? "Читаю QR-коды…" : (store.status ?? "Ключи защищены Связкой ключей macOS")).font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    if store.demo { Text("ДЕМО").font(.caption.bold()).foregroundStyle(.orange) }
                }.padding(.horizontal, 28).padding(.vertical, 16)
            }.background(Color(nsColor: .windowBackgroundColor))
        }
        .sheet(isPresented: $store.importing, onDismiss: { store.session = ImportSession() }) { ImportView().environmentObject(store) }
        .sheet(isPresented: $manual) { ManualView().environmentObject(store) }
        .sheet(item: $editing) { account in EditView(account: account).environmentObject(store) }
        .alert("Не удалось выполнить действие", isPresented: Binding(get: { store.error != nil }, set: { if !$0 { store.error = nil } })) { Button("OK") { store.error = nil } } message: { Text(store.error ?? "") }
        .alert("Удалить аккаунт?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })) {
            Button("Отмена", role: .cancel) { deleting = nil }
            Button("Удалить", role: .destructive) { if let deleting { store.remove(deleting) }; deleting = nil }
        } message: { Text("Коды для \(deleting?.issuer ?? "") \(deleting?.name ?? "") исчезнут с этого Mac. Убедитесь, что у вас есть другой способ входа.") }
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
                VStack(alignment: .leading, spacing: 2) { Text("Authenticator").font(.headline); Text("для Mac").font(.caption).foregroundStyle(.secondary) }
            }.padding(.top, 12)
            Label("Все аккаунты", systemImage: "square.grid.2x2.fill").font(.system(size: 13, weight: .semibold)).frame(maxWidth: .infinity, alignment: .leading).padding(12).background(.teal.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 16) {
                Button { store.importing = true } label: { Label("Перенести с телефона", systemImage: "iphone.and.arrow.forward") }
                Button { manual = true } label: { Label("Добавить вручную", systemImage: "plus.circle") }
            }.buttonStyle(.plain).disabled(store.locked)
            Spacer()
            VStack(alignment: .leading, spacing: 8) {
                Label("Работает офлайн", systemImage: "wifi.slash").font(.caption.bold())
                Text("Коды генерируются на устройстве. Без аккаунта и облака.").font(.caption).foregroundStyle(.secondary).lineSpacing(3)
            }
            Divider()
            Button { store.locked ? store.unlock() : store.lock() } label: { Label(store.locked ? "Разблокировать" : "Заблокировать", systemImage: store.locked ? "lock.open" : "lock") }.buttonStyle(.plain)
        }.padding(20).frame(width: 200).background(.ultraThinMaterial)
    }
    private var emptyState: some View {
        VStack(spacing: 18) {
            Image(systemName: "qrcode.viewfinder").font(.system(size: 62, weight: .light)).foregroundStyle(.teal).padding(24).background(.teal.opacity(0.08), in: RoundedRectangle(cornerRadius: 30))
            Text("Коды с телефона — на вашем Mac").font(.title2.bold())
            Text("Откройте экспорт Google Authenticator.\nПодойдёт QR-код, его изображение или ссылка.").multilineTextAlignment(.center).foregroundStyle(.secondary).lineSpacing(5)
            Button("Импортировать аккаунты") { store.importing = true }.buttonStyle(.borderedProminent).controlSize(.large)
            Button("Добавить ключ вручную") { manual = true }.buttonStyle(.link)
        }.frame(maxWidth: .infinity, maxHeight: .infinity).padding(28)
    }
    private var lockedState: some View {
        VStack(spacing: 20) { Image(systemName: "lock.shield").font(.system(size: 64, weight: .light)).foregroundStyle(.teal); Text("Ваши коды под замком").font(.title2.bold()); Button("Разблокировать с Touch ID или паролем") { store.unlock() }.buttonStyle(.borderedProminent).controlSize(.large) }.frame(maxWidth: .infinity, maxHeight: .infinity)
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
                        Text(account.issuer.isEmpty ? "Аккаунт" : account.issuer).font(.headline).lineLimit(1)
                        Text(account.name).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Spacer(minLength: 0)
                    Menu { Button("Изменить название", action: onEdit); Button("Удалить…", role: .destructive, action: onDelete) } label: { Image(systemName: "ellipsis") }.menuStyle(.borderlessButton).fixedSize()
                }
                HStack {
                    Button {
                        store.copy(account); copied = true
                        Task { try? await Task.sleep(for: .seconds(2)); copied = false }
                    } label: {
                        Text(formatted((try? account.code(at: timeline.date)) ?? "—")).font(.system(size: 32, weight: .medium, design: .monospaced)).foregroundStyle(remaining <= 5 && account.kind == .totp ? .orange : .primary).contentTransition(.numericText())
                    }.buttonStyle(.plain).help("Скопировать код").accessibilityLabel("Скопировать код для \(account.issuer) \(account.name)")
                    Spacer()
                    Image(systemName: copied ? "checkmark" : "doc.on.doc").foregroundStyle(copied ? .teal : .secondary).onTapGesture { store.copy(account); copied = true; Task { try? await Task.sleep(for: .seconds(2)); copied = false } }
                }
                if account.kind == .totp {
                    HStack(spacing: 10) { ProgressView(value: Double(remaining), total: Double(account.period)).tint(remaining <= 5 ? .orange : .teal); Text("\(remaining) с").font(.caption.monospacedDigit()).foregroundStyle(.secondary).frame(width: 35, alignment: .trailing) }
                } else {
                    HStack { Text("HOTP · \(account.counter)").font(.caption).foregroundStyle(.secondary); Spacer(); Button("Следующий код") { store.advance(account) }.font(.caption) }
                }
            }.padding(20).background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 16)).overlay(RoundedRectangle(cornerRadius: 16).stroke(.primary.opacity(0.06), lineWidth: 1))
        }
    }
    private func formatted(_ code: String) -> String { let middle = code.index(code.startIndex, offsetBy: code.count / 2); return String(code[..<middle]) + " " + code[middle...] }
}
