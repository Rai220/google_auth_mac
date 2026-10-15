import SwiftUI
import AppKit
import LocalAuthentication
import AuthenticatorCore

@MainActor public final class Store: ObservableObject {
    @Published public var accounts: [Account] = []
    @Published public var locked = false
    @Published public var error: String?
    @Published public var status: String?
    @Published public var importing = false
    @Published public var session = ImportSession()
    @Published public var busy = false
    private let vault = Vault()
    private var loaded = false
    private var copiedChange: Int?
    private var pendingURLs: [URL] = []
    public let demo: Bool
    @Published public private(set) var requiresAuthentication: Bool
    @Published public private(set) var authenticating = false
    private let defaults: UserDefaults
    private let authenticate: () async throws -> Void
    private let authenticationAvailable: () -> Bool
    private var demoAccounts: [Account] = []
    public static let authenticationPreferenceKey = "requiresAuthentication"

    public init(demo: Bool? = nil, defaults: UserDefaults = .standard,
                authenticationAvailable: @escaping () -> Bool = {
                    LAContext().canEvaluatePolicy(.deviceOwnerAuthentication, error: nil)
                },
                authenticate: @escaping () async throws -> Void = {
                    let context = LAContext()
                    guard try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "Показать коды двухфакторной аутентификации") else { throw LAError(.authenticationFailed) }
                }) {
        self.demo = demo ?? ProcessInfo.processInfo.arguments.contains("--demo")
        self.defaults = defaults
        self.authenticate = authenticate
        self.authenticationAvailable = authenticationAvailable
        self.requiresAuthentication = defaults.bool(forKey: Self.authenticationPreferenceKey)
        if self.demo {
            accounts = [Account(name: "alex@example.com", issuer: "Google", secret: Data("12345678901234567890".utf8)), Account(name: "alex", issuer: "GitHub", secret: Data("demo-secret-github".utf8)), Account(name: "Рабочий аккаунт", issuer: "Cloud", secret: Data("demo-secret-cloud".utf8))]
            demoAccounts = accounts
            loaded = true
        } else {
            reload()
        }
        if requiresAuthentication && loaded && !accounts.isEmpty { lock() }
        NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.clearClipboard() }
        }
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.sessionDidResignActiveNotification, object: nil, queue: .main) { [weak self] _ in Task { @MainActor in self?.handleSessionInactive() } }
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in Task { @MainActor in self?.handleSessionInactive() } }
    }
    private func reload() {
        do { accounts = try vault.load(); loaded = true; locked = false }
        catch { loaded = false; locked = true; self.error = error.localizedDescription }
    }
    public func commit(_ updated: [Account]) throws {
        guard loaded, !locked else { throw AuthError.invalid("Сначала разблокируйте хранилище.") }
        if !demo {
            try vault.save(updated)
            guard try vault.load() == updated else { throw AuthError.invalid("Не удалось проверить сохранённые аккаунты.") }
        }
        accounts = updated
        if demo { demoAccounts = updated }
    }
    public func lock() {
        status = nil
        pendingURLs = []
        clearClipboard(); accounts = []; session = ImportSession(); importing = false; locked = true; loaded = false
    }
    public func setRequiresAuthentication(_ enabled: Bool) {
        guard !locked, !authenticating else { return }
        if enabled && !authenticationAvailable() {
            error = "Touch ID или пароль macOS недоступны. Настройте пароль входа в macOS."
            return
        }
        error = nil
        defaults.set(enabled, forKey: Self.authenticationPreferenceKey)
        requiresAuthentication = enabled
    }
    public func handleSessionInactive() {
        if requiresAuthentication { lock() } else { clearClipboard() }
    }
    public func unlock() { Task { await unlockVault() } }
    public func unlockVault() async {
        guard locked, !authenticating else { return }
        authenticating = true
        error = nil
        defer { authenticating = false }
        do {
            if requiresAuthentication { try await authenticate() }
            if demo { accounts = demoAccounts; loaded = true; locked = false }
            else { reload() }
        } catch { self.error = error.localizedDescription }
    }
    public func copy(_ account: Account) {
        do {
            let code = try account.code()
            NSPasteboard.general.clearContents(); NSPasteboard.general.setString(code, forType: .string)
            let change = NSPasteboard.general.changeCount; copiedChange = change
            status = "Код скопирован на 30 секунд"
            Task { try? await Task.sleep(for: .seconds(30)); if self.copiedChange == change { self.clearClipboard(); self.status = "Буфер обмена очищен" } }
        } catch { self.error = error.localizedDescription }
    }
    private func clearClipboard() {
        if let copiedChange, NSPasteboard.general.changeCount == copiedChange { NSPasteboard.general.clearContents() }
        copiedChange = nil
    }
    public func advance(_ account: Account) {
        guard let index = accounts.firstIndex(where: { $0.id == account.id }), account.counter < UInt64.max else { error = "Счётчик достиг максимума."; return }
        var updated = accounts; updated[index].counter += 1
        do { try commit(updated) } catch { self.error = error.localizedDescription }
    }
    public func remove(_ account: Account) { do { try commit(accounts.filter { $0.id != account.id }) } catch { self.error = error.localizedDescription } }
    public func rename(_ account: Account, name: String, issuer: String) {
        guard let index = accounts.firstIndex(where: { $0.id == account.id }) else { return }
        var updated = accounts; updated[index].name = name.trimmingCharacters(in: .whitespaces); updated[index].issuer = issuer.trimmingCharacters(in: .whitespaces)
        do { try commit(updated) } catch { self.error = error.localizedDescription }
    }
    public func add(_ parts: [ImportPart]) {
        guard !locked else { error = "Разблокируйте приложение перед импортом."; return }
        do { try session.add(parts); importing = true } catch { self.error = error.localizedDescription }
    }
    public var newAccounts: [Account] { session.accounts.filter { candidate in !accounts.contains { $0.sameCredential(as: candidate) } } }
    public func finishImport() {
        guard session.missingParts == 0 else { error = "Добавьте все QR-коды серии."; return }
        do {
            let additions = newAccounts
            try commit(accounts + additions)
            status = "Добавлено аккаунтов: \(additions.count)"
            session = ImportSession(); importing = false
        } catch { self.error = error.localizedDescription }
    }
    public func openFiles() {
        let panel = NSOpenPanel(); panel.allowsMultipleSelection = true; panel.canChooseDirectories = false
        panel.allowedContentTypes = [.image, .plainText]; panel.message = "Выберите изображения QR-кодов или текстовый файл со ссылками экспорта."
        if panel.runModal() == .OK { readFiles(panel.urls) }
    }
    public func readFiles(_ urls: [URL]) {
        guard !locked else { error = "Разблокируйте приложение перед открытием файла."; return }
        pendingURLs.append(contentsOf: urls)
        processNextFiles()
    }
    private func processNextFiles() {
        guard !busy, !locked, !pendingURLs.isEmpty else { return }
        let urls = pendingURLs
        pendingURLs = []
        busy = true
        Task {
            do {
                let parts = try await Task.detached(priority: .userInitiated) { try urls.flatMap { url in
                    let access = url.startAccessingSecurityScopedResource(); defer { if access { url.stopAccessingSecurityScopedResource() } }
                    return try QRImport.read(url: url)
                } }.value
                add(parts)
            } catch { self.error = error.localizedDescription }
            busy = false
            processNextFiles()
        }
    }
    public func paste() {
        guard !locked else { return }
        do {
            if let text = NSPasteboard.general.string(forType: .string), text.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("otpauth") { add(try OTPImport.parse(text: text)) }
            else if let data = NSPasteboard.general.data(forType: .png) ?? NSPasteboard.general.data(forType: .tiff) { add(try QRImport.messages(in: data).flatMap { try OTPImport.parse(text: $0) }) }
            else { error = "В буфере нет изображения QR-кода или ссылки otpauth." }
        } catch { self.error = error.localizedDescription }
    }
}
