import SwiftUI
import AuthenticatorState
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
                VStack(alignment: .leading, spacing: 6) { Text(store.text("Transfer from Google Authenticator")).font(.title2.bold()); Text(store.text("All data is processed only on this Mac.")).foregroundStyle(.secondary) }
                Spacer()
                Button { dismiss() } label: { Image(systemName: "xmark.circle.fill").font(.title3).foregroundStyle(.secondary) }.buttonStyle(.plain).keyboardShortcut(.cancelAction).accessibilityLabel(store.text("Close import"))
            }
            VStack(alignment: .leading, spacing: 8) {
                Text(store.text("1. Open Google Authenticator on your phone."))
                Text(store.text("2. In the menu, choose “Transfer accounts” → “Export accounts”."))
                Text(store.text("3. Show the QR code to your Mac’s camera or open its image."))
            }.font(.callout).padding(16).frame(maxWidth: .infinity, alignment: .leading).background(.teal.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
            HStack(spacing: 12) {
                Button { store.openFiles() } label: { Label(store.text("Open file…"), systemImage: "photo") }
                Button { store.paste() } label: { Label(store.text("From clipboard"), systemImage: "doc.on.clipboard") }
                Button { camera = true } label: { Label(store.text("Camera"), systemImage: "camera") }
            }.controlSize(.large).disabled(store.busy)
            DisclosureGroup(store.text("Paste an export or otpauth link")) {
                VStack(alignment: .leading, spacing: 10) {
                    SecureField("otpauth-migration://offline?data=…", text: $text).textFieldStyle(.roundedBorder)
                    Button(store.text("Read link")) {
                        do { store.add(try OTPImport.parse(text: text)); text = ""; error = nil } catch { self.error = error.localizedDescription }
                    }.disabled(text.isEmpty)
                }.padding(.top, 8)
            }
            if let error { Text(error).foregroundStyle(.red).font(.callout) }
            if let failure = store.error {
                Text(failure).foregroundStyle(.red).font(.callout)
                Button(store.text("Dismiss error")) { store.error = nil }.buttonStyle(.link)
            }
            if store.busy { ProgressView(store.text("Scanning QR codes…")) }
            if !store.session.accounts.isEmpty {
                Divider()
                HStack { Text(store.text("Found: {0}", String(store.session.accounts.count))).font(.headline); Spacer(); Text(store.text("New: {0}", String(store.newAccounts.count))).foregroundStyle(.secondary) }
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(store.session.accounts) { account in
                            HStack {
                                Image(systemName: "key.horizontal").foregroundStyle(.teal)
                                VStack(alignment: .leading, spacing: 4) { Text(account.issuer.isEmpty ? account.name : account.issuer).fontWeight(.medium); if !account.issuer.isEmpty { Text(account.name).font(.caption).foregroundStyle(.secondary) } }
                                Spacer()
                                if store.accounts.contains(where: { $0.sameCredential(as: account) }) { Text(store.text("Already added")).font(.caption).foregroundStyle(.secondary) }
                                Text(account.kind.rawValue.uppercased()).font(.caption).foregroundStyle(.secondary)
                            }.padding(.vertical, 9)
                        }
                    }
                }.frame(maxHeight: 170)
                if store.session.missingParts > 0 {
                    Label(store.text("Add the remaining QR codes: {0}", String(store.session.missingParts)), systemImage: "qrcode").foregroundStyle(.orange)
                }
            }
            HStack {
                Text(store.text("QR codes contain secret keys.\nKeep them as safe as a password.")).font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button(store.text("Cancel")) { dismiss() }
                Button(store.text("Add: {0}", String(store.newAccounts.count))) { store.finishImport() }.buttonStyle(.borderedProminent).disabled(store.newAccounts.isEmpty || store.session.missingParts > 0 || store.busy).keyboardShortcut(.defaultAction)
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
            Text(store.text("Add account")).font(.title2.bold())
            Form {
                TextField(store.text("Service"), text: $issuer)
                TextField(store.text("Account"), text: $name)
                SecureField(store.text("Base32 secret key"), text: $secret)
                Picker(store.text("Type"), selection: $kind) { Text(store.text("Time-based (TOTP)")).tag(OTPKind.totp); Text(store.text("Counter-based (HOTP)")).tag(OTPKind.hotp) }
                DisclosureGroup(store.text("Advanced options")) {
                    Picker(store.text("Algorithm"), selection: $algorithm) { ForEach(Algorithm.allCases, id: \.self) { Text($0.rawValue).tag($0) } }
                    Picker(store.text("Number of digits"), selection: $digits) { Text("6").tag(6); Text("8").tag(8) }
                    if kind == .totp { TextField(store.text("Period, seconds"), text: $period) } else { TextField(store.text("Counter"), text: $counter) }
                }
            }.textFieldStyle(.roundedBorder)
            if let error { Text(error).foregroundStyle(.red) }
            HStack { Spacer(); Button(store.text("Cancel")) { dismiss() }.keyboardShortcut(.cancelAction); Button(store.text("Add")) { save() }.buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction).disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || secret.isEmpty) }
        }.padding(26).frame(width: 470)
    }
    private func save() {
        do {
            guard let period = Int(period), let counter = UInt64(counter) else { throw AuthError.invalid(store.text("Check the period and counter.")) }
            let account = Account(name: name.trimmingCharacters(in: .whitespaces), issuer: issuer.trimmingCharacters(in: .whitespaces), secret: try Base32.decode(secret), algorithm: algorithm, digits: digits, kind: kind, counter: counter, period: period)
            try account.validate()
            guard !store.accounts.contains(where: { $0.sameCredential(as: account) }) else { throw AuthError.invalid(store.text("This key has already been added.")) }
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
            Text(store.text("Account name")).font(.title2.bold())
            Form { TextField(store.text("Service"), text: $issuer); TextField(store.text("Account"), text: $name) }.textFieldStyle(.roundedBorder)
            HStack { Spacer(); Button(store.text("Cancel")) { dismiss() }.keyboardShortcut(.cancelAction); Button(store.text("Save")) { store.rename(account, name: name, issuer: issuer); if store.error == nil { dismiss() } }.buttonStyle(.borderedProminent).disabled(name.trimmingCharacters(in: .whitespaces).isEmpty) }
        }.padding(26).frame(width: 440).onAppear { name = account.name; issuer = account.issuer }
    }
}
