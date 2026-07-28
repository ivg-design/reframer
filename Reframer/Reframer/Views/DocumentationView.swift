import AppKit

struct DocumentationPage {
    let url: URL
    let title: String
    let attributedText: NSAttributedString
}

enum DocumentationPageError: LocalizedError {
    case invalidPage
    case unreadablePage

    var errorDescription: String? {
        switch self {
        case .invalidPage:
            return "The requested help page is outside the Reframer Help book."
        case .unreadablePage:
            return "The requested help page could not be read."
        }
    }
}

/// Loads only bundled HTML pages rooted in the Help book. Rendering through
/// AppKit keeps the documentation available in the sandbox without granting
/// Reframer network access merely to launch WebKit helper processes.
struct DocumentationPageLoader {
    let rootURL: URL

    init(rootURL: URL) {
        self.rootURL = rootURL.standardizedFileURL.resolvingSymlinksInPath()
    }

    func page(named name: String) throws -> DocumentationPage {
        try page(at: rootURL.appendingPathComponent(name))
    }

    func page(at requestedURL: URL) throws -> DocumentationPage {
        guard let pageURL = validatedPageURL(requestedURL) else {
            throw DocumentationPageError.invalidPage
        }
        guard let data = try? Data(contentsOf: pageURL, options: .mappedIfSafe) else {
            throw DocumentationPageError.unreadablePage
        }

        let imported = try NSAttributedString(
            data: data,
            options: [
                .documentType: NSAttributedString.DocumentType.html,
                .characterEncoding: String.Encoding.utf8.rawValue,
                .baseURL: pageURL.deletingLastPathComponent()
            ],
            documentAttributes: nil
        )
        let normalized = Self.normalizedForAppKit(imported)
        let title = normalized.string
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first(where: { !$0.isEmpty })
            ?? "Reframer Documentation"

        return DocumentationPage(
            url: pageURL,
            title: title,
            attributedText: normalized
        )
    }

    func validatedPageURL(_ requestedURL: URL) -> URL? {
        guard requestedURL.isFileURL else { return nil }
        let pageURL = requestedURL
            .standardizedFileURL
            .resolvingSymlinksInPath()
        let rootPath = rootURL.path.hasSuffix("/")
            ? rootURL.path
            : rootURL.path + "/"
        guard pageURL.path.hasPrefix(rootPath),
              pageURL.pathExtension.lowercased() == "html" else {
            return nil
        }
        return pageURL
    }

    private static func normalizedForAppKit(
        _ imported: NSAttributedString
    ) -> NSAttributedString {
        let result = NSMutableAttributedString(attributedString: imported)
        let fullRange = NSRange(location: 0, length: result.length)
        guard fullRange.length > 0 else { return result }

        result.enumerateAttribute(
            .font,
            in: fullRange,
            options: []
        ) { value, range, _ in
            let sourceFont = value as? NSFont
            let pointSize = max(13, sourceFont?.pointSize ?? 14)
            let traits = sourceFont?.fontDescriptor.symbolicTraits ?? []
            let replacement: NSFont
            if traits.contains(.monoSpace) {
                replacement = .monospacedSystemFont(
                    ofSize: pointSize,
                    weight: traits.contains(.bold) ? .semibold : .regular
                )
            } else {
                replacement = .systemFont(
                    ofSize: pointSize,
                    weight: traits.contains(.bold) ? .semibold : .regular
                )
            }
            let finalFont = traits.contains(.italic)
                ? NSFontManager.shared.convert(
                    replacement,
                    toHaveTrait: .italicFontMask
                )
                : replacement
            result.addAttribute(.font, value: finalFont, range: range)
        }

        result.addAttribute(.foregroundColor, value: NSColor.labelColor, range: fullRange)
        result.removeAttribute(.backgroundColor, range: fullRange)
        result.enumerateAttribute(.link, in: fullRange, options: []) {
            link, range, _ in
            guard link != nil else { return }
            result.addAttribute(.foregroundColor, value: NSColor.linkColor, range: range)
            result.removeAttribute(.underlineStyle, range: range)
        }
        return result
    }
}

final class DocumentationTextView: NSTextView, ReframerNavigableContentResponder {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }
}

/// Native, sandbox-safe browser for the bundled Reframer Help book.
final class DocumentationView: NSView, NSTextViewDelegate {
    private let loader: DocumentationPageLoader
    private let homePageName: String
    private let titleLabel = NSTextField(labelWithString: "Reframer Documentation")
    private let backButton = NSButton()
    private let forwardButton = NSButton()
    private let homeButton = NSButton()
    private let scrollView = NSScrollView()
    private let textView = DocumentationTextView()
    private var history: [URL] = []
    private var historyIndex = -1
    private var displayedPageURL: URL?

    var preferredInitialFirstResponder: NSResponder {
        textView
    }

    /// Narrow, read-only navigation state used by the app's contract tests.
    var currentPageURL: URL? {
        displayedPageURL
    }

    var currentPageTitle: String {
        titleLabel.stringValue
    }

    var currentPageText: String {
        textView.string
    }

    var navigationHistoryIndex: Int {
        historyIndex
    }

    var navigationHistoryCount: Int {
        history.count
    }

    var isBackNavigationEnabled: Bool {
        backButton.isEnabled
    }

    var isForwardNavigationEnabled: Bool {
        forwardButton.isEnabled
    }

    init(rootURL: URL, homePageName: String = "index.html") {
        loader = DocumentationPageLoader(rootURL: rootURL)
        self.homePageName = homePageName
        super.init(frame: .zero)
        setup()
        showHome()
    }

    required init?(coder: NSCoder) {
        nil
    }

    func showHome() {
        do {
            let page = try loader.page(named: homePageName)
            display(page, recordingHistory: true)
        } catch {
            display(error: error)
        }
    }

    /// Opens a bundled Help page while preserving the current page when the
    /// request is outside the Help root. This is also the single navigation
    /// entry point used by clicked links.
    @discardableResult
    func navigate(to requestedURL: URL) -> Bool {
        guard let pageURL = loader.validatedPageURL(requestedURL) else {
            return false
        }
        return load(pageURL, recordingHistory: true)
    }

    func goBack() {
        guard historyIndex > 0 else { return }
        historyIndex -= 1
        load(history[historyIndex], recordingHistory: false)
    }

    func goForward() {
        guard historyIndex >= 0, historyIndex + 1 < history.count else {
            return
        }
        historyIndex += 1
        load(history[historyIndex], recordingHistory: false)
    }

    private func setup() {
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityIdentifier("documentation-content")
        setAccessibilityLabel("Reframer documentation")

        let toolbar = NSVisualEffectView()
        toolbar.translatesAutoresizingMaskIntoConstraints = false
        toolbar.material = .headerView
        toolbar.blendingMode = .withinWindow
        toolbar.state = .active
        addSubview(toolbar)

        configureToolbarButton(
            backButton,
            symbol: "chevron.left",
            label: "Back",
            identifier: "documentation-back",
            action: #selector(handleBackButton)
        )
        configureToolbarButton(
            forwardButton,
            symbol: "chevron.right",
            label: "Forward",
            identifier: "documentation-forward",
            action: #selector(handleForwardButton)
        )
        configureToolbarButton(
            homeButton,
            symbol: "house",
            label: "Reframer Help",
            identifier: "documentation-home",
            action: #selector(handleHomeButton)
        )

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        titleLabel.setAccessibilityIdentifier("documentation-title")

        let toolbarStack = NSStackView(
            views: [backButton, forwardButton, homeButton, titleLabel]
        )
        toolbarStack.translatesAutoresizingMaskIntoConstraints = false
        toolbarStack.orientation = .horizontal
        toolbarStack.alignment = .centerY
        toolbarStack.spacing = 8
        toolbar.addSubview(toolbarStack)

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = true
        scrollView.backgroundColor = .textBackgroundColor
        addSubview(scrollView)

        textView.isEditable = false
        textView.isSelectable = true
        textView.isRichText = true
        textView.importsGraphics = false
        textView.usesFindBar = true
        textView.drawsBackground = true
        textView.backgroundColor = .textBackgroundColor
        textView.textContainerInset = NSSize(width: 28, height: 24)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(
            width: 0,
            height: CGFloat.greatestFiniteMagnitude
        )
        textView.textContainer?.lineFragmentPadding = 0
        textView.delegate = self
        textView.linkTextAttributes = [
            .foregroundColor: NSColor.linkColor,
            .cursor: NSCursor.pointingHand
        ]
        textView.setAccessibilityIdentifier("documentation-page")
        textView.setAccessibilityLabel("Reframer documentation page")
        scrollView.documentView = textView

        NSLayoutConstraint.activate([
            toolbar.topAnchor.constraint(equalTo: topAnchor),
            toolbar.leadingAnchor.constraint(equalTo: leadingAnchor),
            toolbar.trailingAnchor.constraint(equalTo: trailingAnchor),
            toolbar.heightAnchor.constraint(equalToConstant: 44),

            toolbarStack.leadingAnchor.constraint(equalTo: toolbar.leadingAnchor, constant: 10),
            toolbarStack.trailingAnchor.constraint(
                lessThanOrEqualTo: toolbar.trailingAnchor,
                constant: -12
            ),
            toolbarStack.centerYAnchor.constraint(equalTo: toolbar.centerYAnchor),

            scrollView.topAnchor.constraint(equalTo: toolbar.bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    private func configureToolbarButton(
        _ button: NSButton,
        symbol: String,
        label: String,
        identifier: String,
        action: Selector
    ) {
        button.translatesAutoresizingMaskIntoConstraints = false
        button.bezelStyle = .accessoryBarAction
        button.image = NSImage(
            systemSymbolName: symbol,
            accessibilityDescription: label
        )
        button.imagePosition = .imageOnly
        button.target = self
        button.action = action
        button.toolTip = label
        button.setAccessibilityIdentifier(identifier)
        button.setAccessibilityLabel(label)
        NSLayoutConstraint.activate([
            button.widthAnchor.constraint(equalToConstant: 28),
            button.heightAnchor.constraint(equalToConstant: 28)
        ])
    }

    private func display(
        _ page: DocumentationPage,
        recordingHistory: Bool
    ) {
        if recordingHistory {
            if historyIndex + 1 < history.count {
                history.removeSubrange((historyIndex + 1)..<history.count)
            }
            if history.last != page.url {
                history.append(page.url)
            }
            historyIndex = max(0, history.count - 1)
        }

        textView.textStorage?.setAttributedString(page.attributedText)
        textView.scrollToBeginningOfDocument(nil)
        textView.setAccessibilityValue(page.attributedText.string)
        titleLabel.stringValue = page.title
        displayedPageURL = page.url
        updateNavigationButtons()
    }

    private func display(error: Error) {
        let message = """
        Documentation couldn’t be loaded

        \(error.localizedDescription)
        """
        textView.string = message
        textView.font = .systemFont(ofSize: 14)
        textView.textColor = .labelColor
        textView.setAccessibilityValue(message)
        titleLabel.stringValue = "Documentation unavailable"
        displayedPageURL = nil
        updateNavigationButtons()
    }

    @discardableResult
    private func load(_ url: URL, recordingHistory: Bool) -> Bool {
        do {
            display(try loader.page(at: url), recordingHistory: recordingHistory)
            return true
        } catch {
            display(error: error)
            return false
        }
    }

    private func updateNavigationButtons() {
        backButton.isEnabled = historyIndex > 0
        forwardButton.isEnabled = historyIndex >= 0 && historyIndex + 1 < history.count
    }

    @objc private func handleBackButton() {
        goBack()
    }

    @objc private func handleForwardButton() {
        goForward()
    }

    @objc private func handleHomeButton() {
        showHome()
    }

    func textView(
        _ textView: NSTextView,
        clickedOnLink link: Any,
        at charIndex: Int
    ) -> Bool {
        let url: URL?
        if let linkURL = link as? URL {
            url = linkURL
        } else if let linkString = link as? String {
            url = URL(string: linkString, relativeTo: history[safe: historyIndex])
        } else {
            url = nil
        }
        guard let url, navigate(to: url) else {
            NSSound.beep()
            return true
        }
        return true
    }
}

private extension Array {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
