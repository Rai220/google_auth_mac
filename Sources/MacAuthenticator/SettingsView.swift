import SwiftUI
import AppKit
import AuthenticatorState

struct SettingsView: View {
    @EnvironmentObject var store: Store
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Label("Безопасность", systemImage: "lock.shield").font(.title2.bold())
            Toggle("Запрашивать Touch ID или пароль macOS", isOn: Binding(
                get: { store.requiresAuthentication },
                set: { store.setRequiresAuthentication($0) }
            )).disabled(store.locked || store.authenticating)
            Text("Запрашивать подтверждение при открытии приложения, после сна или переключения пользователя и при ручной разблокировке. По умолчанию выключено.")
                .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            if store.locked {
                Label("Сначала разблокируйте приложение, чтобы изменить эту настройку.", systemImage: "lock")
                    .font(.callout).foregroundStyle(.secondary)
            }
            if let error = store.error {
                Text(error).font(.callout).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true)
            }
            Divider()
            Text("Ключи всегда хранятся в Связке ключей macOS, независимо от этой настройки.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            HStack {
                Text("Изменения сохраняются автоматически.")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Готово") { closeSettings() }
                    .keyboardShortcut(.cancelAction)
            }
        }.padding(24).frame(width: 440)
    }
    private func closeSettings() { NSApp.keyWindow?.performClose(nil) }
}
