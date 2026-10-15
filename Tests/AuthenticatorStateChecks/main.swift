import Foundation
import AuthenticatorState
import AuthenticatorCore

@main struct StateChecks {
    @MainActor static func main() async {
        var assertions = 0
        var failures = 0
        func expect(_ condition: Bool, _ description: String) {
            assertions += 1
            if !condition { failures += 1; print("FAIL: \(description)") }
        }
        let suiteName = "local.macauthenticator.test.preferences." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        var requests = 0
        var deny = false
        enum TestError: Error { case denied }
        let authenticate: () async throws -> Void = {
            requests += 1
            if deny { throw TestError.denied }
        }
        func makeStore(available: Bool = true) -> Store {
            Store(demo: true, defaults: defaults, authenticationAvailable: { available }, authenticate: authenticate)
        }
        let initial = makeStore()
        expect(!initial.requiresAuthentication, "Authentication defaults to off")
        expect(!initial.locked && initial.accounts.count == 3, "Default startup displays accounts")
        initial.handleSessionInactive()
        expect(!initial.locked, "Sleep/user switch does not require authentication when disabled")
        initial.lock()
        expect(initial.locked && initial.accounts.isEmpty, "Manual lock hides account data")
        await initial.unlockVault()
        expect(!initial.locked && initial.accounts.count == 3, "Manual reveal restores accounts when authentication is disabled")
        expect(requests == 0, "Disabled setting never calls system authentication")
        initial.setRequiresAuthentication(true)
        expect(initial.requiresAuthentication, "Setting can be enabled")
        let protected = makeStore()
        expect(protected.requiresAuthentication, "Enabled setting survives restart")
        expect(protected.locked && protected.accounts.isEmpty, "Enabled startup hides accounts")
        protected.setRequiresAuthentication(false)
        expect(protected.requiresAuthentication, "Locked settings cannot bypass authentication")
        deny = true
        await protected.unlockVault()
        expect(requests == 1 && protected.locked && protected.accounts.isEmpty, "Denied authentication keeps vault locked")
        expect(!protected.authenticating && protected.error != nil, "Failed request resets busy state and reports error")
        deny = false
        await protected.unlockVault()
        expect(requests == 2 && !protected.locked && protected.accounts.count == 3, "Successful authentication restores accounts")
        await protected.unlockVault()
        expect(requests == 2, "Already unlocked vault does not prompt again")
        protected.handleSessionInactive()
        expect(protected.locked, "Enabled protection locks after session inactivity")
        await protected.unlockVault()
        protected.setRequiresAuthentication(false)
        expect(!protected.requiresAuthentication, "Setting can be disabled after unlocking")
        let reopened = makeStore()
        expect(!reopened.requiresAuthentication && !reopened.locked, "Disabled setting survives restart")
        let before = requests
        reopened.lock(); await reopened.unlockVault()
        expect(requests == before && !reopened.locked, "Disabled mode continues without biometric or password prompts")
        let unavailable = makeStore(available: false)
        unavailable.setRequiresAuthentication(true)
        expect(!unavailable.requiresAuthentication && unavailable.error != nil, "Unavailable system authentication cannot lock the user out")
        expect(!defaults.bool(forKey: Store.authenticationPreferenceKey), "Unavailable authentication does not persist enabled setting")
        expect(initial.language == .system, "Language defaults to system")
        expect(AppLanguage.system.resolved(preferredLanguages: ["ru-RU"]) == .ru, "Russian system locale")
        expect(AppLanguage.system.resolved(preferredLanguages: ["en-US"]) == .en, "English system locale")
        expect(AppLanguage.system.resolved(preferredLanguages: ["ja-JP"]) == .en, "Unsupported locale falls back to English")
        expect(AppLanguage.system.resolved(preferredLanguages: []) == .en, "Missing locale falls back to English")
        reopened.setLanguage(.en)
        expect(reopened.text("Your codes") == "Your codes", "English UI strings")
        expect(makeStore().language == .en, "English preference survives restart")
        reopened.setLanguage(.ru)
        expect(reopened.text("Your codes") == "Ваши коды", "Russian UI strings")
        expect(makeStore().language == .ru, "Russian preference survives restart")
        expect(reopened.text("Accounts added: {0}", "3") == "Добавлено аккаунтов: 3", "Translated count interpolation")
        expect(L10n.text("Copy code for {0} {1}", "{1}", "example", language: .en) == "Copy code for {1} example", "Account names are not interpreted as placeholders")
        let snapshot = reopened.accounts
        reopened.lock(); reopened.setLanguage(.en)
        expect(reopened.locked && reopened.accounts.isEmpty, "Changing language cannot unlock the vault")
        await reopened.unlockVault()
        expect(reopened.accounts == snapshot, "Language changes preserve account data")
        defaults.set("invalid", forKey: AppLanguage.preferenceKey)
        expect(makeStore().language == .system, "Invalid preference falls back to system")
        print("Authentication and language settings: \(assertions) assertions, \(failures) failures")
        exit(failures == 0 ? 0 : 1)
    }
}
