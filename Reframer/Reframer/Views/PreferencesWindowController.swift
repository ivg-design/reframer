import Cocoa

class PreferencesWindowController: NSWindowController {

    // MARK: - Singleton

    static let shared = PreferencesWindowController()

    // MARK: - UI Elements

    private let mpvCheckbox = NSButton(checkboxWithTitle: "Enable extended format support (WebM, MKV, OGV, FLV)",
                                          target: nil, action: nil)
    private let installButton = NSButton(title: "Install MPV", target: nil, action: nil)
    private let uninstallButton = NSButton(title: "Uninstall", target: nil, action: nil)
    private let statusLabel = NSTextField(labelWithString: "")
    private let progressIndicator = NSProgressIndicator()
    private let sizeLabel = NSTextField(labelWithString: "")

    // MARK: - Initialization

    private init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 200),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Preferences"
        window.center()

        super.init(window: window)

        setupUI()
        updateState()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - UI Setup

    private func setupUI() {
        guard let contentView = window?.contentView else { return }

        contentView.wantsLayer = true

        // Main container
        let container = NSStackView()
        container.orientation = .vertical
        container.alignment = .leading
        container.spacing = 16
        container.translatesAutoresizingMaskIntoConstraints = false
        container.edgeInsets = NSEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)
        contentView.addSubview(container)

        NSLayoutConstraint.activate([
            container.topAnchor.constraint(equalTo: contentView.topAnchor),
            container.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            container.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            container.bottomAnchor.constraint(equalTo: contentView.bottomAnchor)
        ])

        // Section header
        let headerLabel = NSTextField(labelWithString: "Extended Format Support")
        headerLabel.font = .systemFont(ofSize: 14, weight: .semibold)
        container.addArrangedSubview(headerLabel)

        // Description
        let descLabel = NSTextField(wrappingLabelWithString: "AVFoundation doesn't support WebM, MKV, and other formats. Install libmpv to enable playback of these formats.")
        descLabel.textColor = .secondaryLabelColor
        descLabel.font = .systemFont(ofSize: 12)
        container.addArrangedSubview(descLabel)

        // Checkbox
        mpvCheckbox.target = self
        mpvCheckbox.action = #selector(mpvToggled(_:))
        container.addArrangedSubview(mpvCheckbox)

        // Button row
        let buttonRow = NSStackView()
        buttonRow.orientation = .horizontal
        buttonRow.spacing = 12

        installButton.bezelStyle = .rounded
        installButton.target = self
        installButton.action = #selector(installClicked(_:))

        uninstallButton.bezelStyle = .rounded
        uninstallButton.target = self
        uninstallButton.action = #selector(uninstallClicked(_:))

        progressIndicator.style = .spinning
        progressIndicator.controlSize = .small
        progressIndicator.isHidden = true

        buttonRow.addArrangedSubview(installButton)
        buttonRow.addArrangedSubview(uninstallButton)
        buttonRow.addArrangedSubview(progressIndicator)
        container.addArrangedSubview(buttonRow)

        // Status label
        statusLabel.font = .systemFont(ofSize: 11)
        statusLabel.textColor = .secondaryLabelColor
        container.addArrangedSubview(statusLabel)

        // Size info
        sizeLabel.font = .systemFont(ofSize: 11)
        sizeLabel.textColor = .tertiaryLabelColor
        container.addArrangedSubview(sizeLabel)
    }

    // MARK: - State

    private func updateState() {
        let manager = MPVManager.shared

        mpvCheckbox.state = manager.isEnabled ? .on : .off
        mpvCheckbox.isEnabled = manager.isInstalled

        installButton.isHidden = manager.isInstalled
        uninstallButton.isHidden = !manager.isInstalled

        if manager.isInstalled {
            statusLabel.stringValue = "libmpv is installed"
            statusLabel.textColor = .systemGreen

            // Get installed size
            if let size = try? FileManager.default.allocatedSizeOfDirectory(at: manager.installDirectory) {
                let formatter = ByteCountFormatter()
                formatter.countStyle = .file
                sizeLabel.stringValue = "Size: \(formatter.string(fromByteCount: Int64(size)))"
            }
        } else {
            statusLabel.stringValue = "libmpv is not installed"
            statusLabel.textColor = .secondaryLabelColor
            sizeLabel.stringValue = "Download size: ~35MB (mpv bundle)"
        }
    }

    // MARK: - Actions

    @objc private func mpvToggled(_ sender: NSButton) {
        MPVManager.shared.isEnabled = sender.state == .on

        if sender.state == .on && !MPVManager.shared.isLoaded {
            MPVManager.shared.loadLibrary()
        }
    }

    @objc private func installClicked(_ sender: NSButton) {
        installButton.isEnabled = false
        progressIndicator.isHidden = false
        progressIndicator.startAnimation(nil)

        MPVManager.shared.install { [weak self] progress, status in
            self?.statusLabel.stringValue = status
        } completion: { [weak self] result in
            self?.progressIndicator.stopAnimation(nil)
            self?.progressIndicator.isHidden = true
            self?.installButton.isEnabled = true

            switch result {
            case .success:
                MPVManager.shared.isEnabled = true
                MPVManager.shared.loadLibrary()
                self?.updateState()

            case .failure(let error):
                let alert = NSAlert()
                alert.messageText = "Installation Failed"
                alert.informativeText = error.localizedDescription
                alert.alertStyle = .critical
                if let window = self?.window {
                    alert.beginSheetModal(for: window)
                }
                self?.updateState()
            }
        }
    }

    @objc private func uninstallClicked(_ sender: NSButton) {
        let alert = NSAlert()
        alert.messageText = "Uninstall MPV?"
        alert.informativeText = "WebM, MKV, and other extended formats will no longer be playable."
        alert.addButton(withTitle: "Uninstall")
        alert.addButton(withTitle: "Cancel")

        guard let window = window else { return }

        alert.beginSheetModal(for: window) { [weak self] response in
            if response == .alertFirstButtonReturn {
                do {
                    try MPVManager.shared.uninstall()
                    self?.updateState()
                } catch {
                    let errorAlert = NSAlert(error: error)
                    errorAlert.beginSheetModal(for: window)
                }
            }
        }
    }

    // MARK: - Show

    func showWindow() {
        updateState()
        // Make preferences appear above floating windows
        window?.level = .floating + 1
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

// MARK: - FileManager Extension

extension FileManager {
    func allocatedSizeOfDirectory(at url: URL) throws -> UInt64 {
        var size: UInt64 = 0
        let resourceKeys: [URLResourceKey] = [.fileSizeKey, .isDirectoryKey]

        guard let enumerator = enumerator(at: url, includingPropertiesForKeys: resourceKeys) else {
            return 0
        }

        for case let fileURL as URL in enumerator {
            let resourceValues = try fileURL.resourceValues(forKeys: Set(resourceKeys))
            if resourceValues.isDirectory == false {
                size += UInt64(resourceValues.fileSize ?? 0)
            }
        }

        return size
    }
}
