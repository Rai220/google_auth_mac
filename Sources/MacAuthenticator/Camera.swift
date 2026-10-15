import AuthenticatorCore
import SwiftUI
import AuthenticatorState
import AVFoundation

final class CameraScanner: NSObject, ObservableObject, AVCaptureMetadataOutputObjectsDelegate {
    let session = AVCaptureSession()
    @Published var message = L10n.text("Allow camera access and show the QR code on your phone.")
    @Published var available = false
    private let queue = DispatchQueue(label: "local.macauthenticator.camera")
    private var seen = Set<String>()
    private var active = false
    var onCode: ((String) -> Void)?
    func start() {
        active = true
        AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
            guard let self else { return }
            DispatchQueue.main.async {
                guard self.active else { return }
                if granted { self.configure() }
                else { self.message = L10n.text("Camera access is denied. Allow it in macOS settings or open a QR code image.") }
            }
        }
    }
    private func configure() {
        guard session.inputs.isEmpty else { queue.async { self.session.startRunning() }; return }
        do {
            guard let device = AVCaptureDevice.default(for: .video) else { message = L10n.text("No camera found. Open a QR code image."); return }
            let input = try AVCaptureDeviceInput(device: device)
            let output = AVCaptureMetadataOutput()
            session.beginConfiguration()
            guard session.canAddInput(input), session.canAddOutput(output) else { session.commitConfiguration(); message = L10n.text("Could not connect to the camera."); return }
            session.addInput(input); session.addOutput(output)
            output.setMetadataObjectsDelegate(self, queue: .main)
            guard output.availableMetadataObjectTypes.contains(.qr) else { session.commitConfiguration(); message = L10n.text("This camera does not support QR scanning."); return }
            output.metadataObjectTypes = [.qr]; session.commitConfiguration()
            available = true; message = L10n.text("Show the export QR code. For a batch, show every code in sequence.")
            queue.async { self.session.startRunning() }
        } catch { message = L10n.text("Could not start the camera: {0}", String(error.localizedDescription)) }
    }
    func stop() { active = false; queue.async { self.session.stopRunning() } }
    func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput metadataObjects: [AVMetadataObject], from connection: AVCaptureConnection) {
        guard active else { return }
        for object in metadataObjects {
            guard let value = (object as? AVMetadataMachineReadableCodeObject)?.stringValue,
                  value.hasPrefix("otpauth://") || value.hasPrefix("otpauth-migration://"), seen.insert(value).inserted else { continue }
            onCode?(value)
        }
    }
}
struct CameraPreview: NSViewRepresentable {
    let session: AVCaptureSession
    class Preview: NSView {
        var preview: AVCaptureVideoPreviewLayer?
        override func layout() { super.layout(); preview?.frame = bounds }
    }
    func makeNSView(context: Context) -> Preview {
        let view = Preview(); view.wantsLayer = true
        let layer = AVCaptureVideoPreviewLayer(session: session); layer.videoGravity = .resizeAspectFill
        view.layer = layer; view.preview = layer; return view
    }
    func updateNSView(_ nsView: Preview, context: Context) {}
}
struct CameraView: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) var dismiss
    @StateObject private var scanner = CameraScanner()
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack { Text(store.text("Scan from your phone")).font(.title2.bold()); Spacer(); Button(store.text("Done")) { dismiss() }.keyboardShortcut(.cancelAction) }
            ZStack {
                RoundedRectangle(cornerRadius: 16).fill(.black)
                if scanner.available { CameraPreview(session: scanner.session).clipShape(RoundedRectangle(cornerRadius: 16)) }
                else { Image(systemName: "camera").font(.system(size: 48)).foregroundStyle(.white.opacity(0.6)) }
            }.frame(height: 310)
            Text(scanner.message).foregroundStyle(.secondary)
            Label(store.text("Accounts scanned: {0}", String(store.session.accounts.count)), systemImage: "qrcode.viewfinder")
            if store.session.missingParts > 0 { Text(store.text("QR codes remaining in the batch: {0}", String(store.session.missingParts))).foregroundStyle(.orange) }
        }.padding(24).frame(width: 540)
        .onAppear { scanner.onCode = { value in
            do { store.add(try OTPImport.parse(text: value)) } catch { scanner.message = error.localizedDescription }
        }; scanner.start() }
        .onDisappear { scanner.stop() }
    }
}
import AuthenticatorCore
