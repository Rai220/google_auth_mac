## What's new in 1.0.2

- English and Russian interfaces, including import, manual entry, settings, help text, and app-generated errors.
- Choose **Follow system**, **English**, or **Русский** in Settings. The choice takes effect immediately and survives restarts. Account names and authentication settings are preserved.
- English is now the primary README, with a Russian version and an actual app screenshot using only synthetic demo accounts.

Touch ID or macOS password protection remains optional and off by default. Settings close with **Done** or Escape; **Quit** in the sidebar or ⌘Q exits the app.

## Download and install

Requires **macOS 14 or later**. Choose **arm64** for Apple Silicon or **x86_64** for Intel. Open the DMG and drag Mac Authenticator into Applications, or extract the ZIP.

Builds are **ad-hoc signed**, without Apple Developer ID signing or notarization. macOS may require **System Settings → Privacy & Security → Open Anyway** after you verify the download source. Managed Macs may prohibit this.

Both architectures are built and tested in GitHub Actions. Download `SHA256SUMS.txt` alongside the archives and verify them with `shasum -a 256 -c SHA256SUMS.txt` (missing files produce missing-file messages).

The app runs locally and stores secrets in the macOS Keychain. No user QR codes or keys are included. Keep your original authenticator until you have checked the transfer. An independent application, not a Google product.

## По-русски

Добавлены русский и английский языки. Выбор в **Настройки → Язык** применяется сразу и сохраняется после перезапуска. README на английском стал основным; русская версия доступна по ссылке. Скриншот содержит только демонстрационные данные.
