import SwiftUI
import AuthenticatorCore

struct ImportView: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) var dismiss
    @State private var text = ""
    @State private var camera = false
    @State private var error: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                VStack(alignment: .leading, spacing: 6) { Text("Перенос из Google Authenticator").font(.title2.bold()); Text("Все данные обрабатываются только на этом Mac.").foregroundStyle(.secondary) }
                Spacer()
                Button { dismiss() } label: { Image(systemName: "xmark.circle.fill").font(.title3).foregroundStyle(.secondary) }.buttonStyle(.plain).keyboardShortcut(.cancelAction).accessibilityLabel("Закрыть импорт")
            }
            VStack(alignment: .leading, spacing: 8) {
                Text("1. Откройте Google Authenticator на телефоне.")
                Text("2. В меню выберите «Перенести аккаунты» → «Экспорт аккаунтов».")
                Text("3. Покажите QR-код камере Mac или откройте его изображение.")
            }.font(.callout).padding(16).frame(maxWidth: .infinity, alignment: .leading).background(.teal.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
            HStack(spacing: 12) {
                Button { store.openFiles() } label: { Label("Открыть файл…", systemImage: "photo") }
                Button { store.paste() } label: { Label("Из буфера", systemImage: "doc.on.clipboard") }
                Button { camera = true } label: { Label("Камера", systemImage: "camera") }
            }.controlSize(.large).disabled(store.busy)
            DisclosureGroup("Вставить ссылку экспорта или otpauth") {
                VStack(alignment: .leading, spacing: 10) {
                    SecureField("otpauth-migration://offline?data=…", text: $text).textFieldStyle(.roundedBorder)
                    Button("Прочитать ссылку") {
                        do { store.add(try OTPImport.parse(text: text)); text = ""; error = nil } catch { self.error = error.localizedDescription }
                    }.disabled(text.isEmpty)
                }.padding(.top, 8)
            }
            if let error { Text(error).foregroundStyle(.red).font(.callout) }
            if let failure = store.error {
                Text(failure).foregroundStyle(.red).font(.callout)
                Button("Скрыть ошибку") { store.error = nil }.buttonStyle(.link)
            }
            if store.busy { ProgressView("Распознаю QR-коды…") }
            if !store.session.accounts.isEmpty {
                Divider()
                HStack { Text("Найдено: \(store.session.accounts.count)").font(.headline); Spacer(); Text("Новых: \(store.newAccounts.count)").foregroundStyle(.secondary) }
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(store.session.accounts) { account in
                            HStack {
                                Image(systemName: "key.horizontal").foregroundStyle(.teal)
                                VStack(alignment: .leading, spacing: 4) { Text(account.issuer.isEmpty ? account.name : account.issuer).fontWeight(.medium); if !account.issuer.isEmpty { Text(account.name).font(.caption).foregroundStyle(.secondary) } }
                                Spacer()
                                if store.accounts.contains(where: { $0.sameCredential(as: account) }) { Text("Уже добавлен").font(.caption).foregroundStyle(.secondary) }
                                Text(account.kind.rawValue.uppercased()).font(.caption).foregroundStyle(.secondary)
                            }.padding(.vertical, 9)
                        }
                    }
                }.frame(maxHeight: 170)
                if store.session.missingParts > 0 {
                    Label("Добавьте оставшиеся QR-коды: \(store.session.missingParts)", systemImage: "qrcode").foregroundStyle(.orange)
                }
            }
            HStack {
                Text("QR-код содержит секретные ключи.\nХраните его так же бережно, как пароль.").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Отмена") { dismiss() }
                Button("Добавить: \(store.newAccounts.count)") { store.finishImport() }.buttonStyle(.borderedProminent).disabled(store.newAccounts.isEmpty || store.session.missingParts > 0 || store.busy).keyboardShortcut(.defaultAction)
            }
        }.padding(26).frame(width: 620)
        .sheet(isPresented: $camera) { CameraView().environmentObject(store) }
    }
}
struct ManualView: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) var dismiss
    @State private var name = ""
    @State private var issuer = ""
    @State private var secret = ""
    @State private var kind = OTPKind.totp
    @State private var algorithm = Algorithm.sha1
    @State private var digits = 6
    @State private var period = "30"
    @State private var counter = "0"
    @State private var error: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Добавить аккаунт").font(.title2.bold())
            Form {
                TextField("Сервис", text: $issuer)
                TextField("Аккаунт", text: $name)
                SecureField("Секретный ключ Base32", text: $secret)
                Picker("Тип", selection: $kind) { Text("По времени (TOTP)").tag(OTPKind.totp); Text("По счётчику (HOTP)").tag(OTPKind.hotp) }
                DisclosureGroup("Дополнительные параметры") {
                    Picker("Алгоритм", selection: $algorithm) { ForEach(Algorithm.allCases, id: \.self) { Text($0.rawValue).tag($0) } }
                    Picker("Количество цифр", selection: $digits) { Text("6").tag(6); Text("8").tag(8) }
                    if kind == .totp { TextField("Период, секунд", text: $period) } else { TextField("Счётчик", text: $counter) }
                }
            }.textFieldStyle(.roundedBorder)
            if let error { Text(error).foregroundStyle(.red) }
            HStack { Spacer(); Button("Отмена") { dismiss() }.keyboardShortcut(.cancelAction); Button("Добавить") { save() }.buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction).disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || secret.isEmpty) }
        }.padding(26).frame(width: 470)
    }
    private func save() {
        do {
            guard let period = Int(period), let counter = UInt64(counter) else { throw AuthError.invalid("Проверьте период и счётчик.") }
            let account = Account(name: name.trimmingCharacters(in: .whitespaces), issuer: issuer.trimmingCharacters(in: .whitespaces), secret: try Base32.decode(secret), algorithm: algorithm, digits: digits, kind: kind, counter: counter, period: period)
            try account.validate()
            guard !store.accounts.contains(where: { $0.sameCredential(as: account) }) else { throw AuthError.invalid("Этот ключ уже добавлен.") }
            try store.commit(store.accounts + [account]); dismiss()
        } catch { self.error = error.localizedDescription }
    }
}
struct EditView: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) var dismiss
    let account: Account
    @State private var name = ""
    @State private var issuer = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Название аккаунта").font(.title2.bold())
            Form { TextField("Сервис", text: $issuer); TextField("Аккаунт", text: $name) }.textFieldStyle(.roundedBorder)
            HStack { Spacer(); Button("Отмена") { dismiss() }.keyboardShortcut(.cancelAction); Button("Сохранить") { store.rename(account, name: name, issuer: issuer); if store.error == nil { dismiss() } }.buttonStyle(.borderedProminent).disabled(name.trimmingCharacters(in: .whitespaces).isEmpty) }
        }.padding(26).frame(width: 440).onAppear { name = account.name; issuer = account.issuer }
    }
}
