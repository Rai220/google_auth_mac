import AuthenticatorCore
import SwiftUI
import AppKit
import AuthenticatorState

struct SettingsView: View {
    @EnvironmentObject var store: Store
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Picker(store.text("Language"), selection: Binding(get: { store.language }, set: { store.setLanguage($0) })) {
                Text(store.text("Follow system")).tag(AppLanguage.system)
                Text("English").tag(AppLanguage.en)
                Text("Русский").tag(AppLanguage.ru)
            }
            Text(store.text("App language changes immediately. macOS dialogs use your system language."))
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Divider()
            Label(store.text("Security"), systemImage: "lock.shield").font(.title2.bold())
            Toggle(store.text("Require Touch ID or macOS password"), isOn: Binding(
                get: { store.requiresAuthentication },
                set: { store.setRequiresAuthentication($0) }
            )).disabled(store.locked || store.authenticating)
            Text(store.text("Ask for confirmation when opening the app, after sleep or switching users, and when unlocking manually. Off by default."))
                .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            if store.locked {
                Label(store.text("Unlock the app before changing this setting."), systemImage: "lock")
                    .font(.callout).foregroundStyle(.secondary)
            }
            if let error = store.error {
                Text(error).font(.callout).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true)
            }
            Divider()
            Text(store.text("Keys are always stored in the macOS Keychain, regardless of this setting."))
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            HStack {
                Text(store.text("Changes are saved automatically."))
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button(store.text("Done")) { closeSettings() }
                    .keyboardShortcut(.cancelAction)
            }
        }.padding(24).frame(width: 440)
    }
    private func closeSettings() { NSApp.keyWindow?.performClose(nil) }
}
