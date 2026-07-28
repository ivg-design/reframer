import AppKit
import XCTest
@testable import Reframer

@MainActor
final class DocumentationViewTests: XCTestCase {
    private var testDirectoryURL: URL!
    private var rootURL: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        testDirectoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "ReframerDocumentationTests-\(UUID().uuidString)",
                isDirectory: true
            )
        rootURL = testDirectoryURL.appendingPathComponent(
            "Help",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: rootURL,
            withIntermediateDirectories: true
        )

        try writePage(
            """
            <!doctype html>
            <html>
            <head><meta charset="utf-8"><title>Reframer Help</title></head>
            <body>
              <h1>Reframer Help</h1>
              <p>Bundled documentation content.</p>
              <a href="details.html">Details</a>
            </body>
            </html>
            """,
            named: "index.html"
        )
        try writePage(
            """
            <!doctype html>
            <html>
            <body>
              <h1>Details</h1>
              <p>Second page.</p>
              <a href="alternate.html">Alternate</a>
            </body>
            </html>
            """,
            named: "details.html"
        )
        try writePage(
            """
            <!doctype html>
            <html><body><h1>Alternate</h1><p>Alternate page.</p></body></html>
            """,
            named: "alternate.html"
        )

        let outsideURL = testDirectoryURL.appendingPathComponent("outside.html")
        try Data("<h1>Outside</h1>".utf8).write(to: outsideURL)
        try FileManager.default.createSymbolicLink(
            at: rootURL.appendingPathComponent("linked-outside.html"),
            withDestinationURL: outsideURL
        )
    }

    override func tearDownWithError() throws {
        if let testDirectoryURL {
            try? FileManager.default.removeItem(at: testDirectoryURL)
        }
        rootURL = nil
        testDirectoryURL = nil
        try super.tearDownWithError()
    }

    func testLoaderRendersKnownBundledPageContent() throws {
        let page = try DocumentationPageLoader(rootURL: rootURL)
            .page(named: "index.html")

        XCTAssertEqual(page.title, "Reframer Help")
        XCTAssertTrue(
            page.attributedText.string.contains(
                "Bundled documentation content."
            )
        )
        XCTAssertTrue(page.attributedText.string.contains("Details"))
        XCTAssertEqual(page.url, expectedPageURL(named: "index.html"))
    }

    func testViewStartsAtHomeWithDeterministicNavigationState() {
        let view = DocumentationView(rootURL: rootURL)

        XCTAssertEqual(
            view.currentPageURL,
            expectedPageURL(named: "index.html")
        )
        XCTAssertEqual(view.currentPageTitle, "Reframer Help")
        XCTAssertTrue(
            view.currentPageText.contains("Bundled documentation content.")
        )
        XCTAssertEqual(view.navigationHistoryIndex, 0)
        XCTAssertEqual(view.navigationHistoryCount, 1)
        XCTAssertFalse(view.isBackNavigationEnabled)
        XCTAssertFalse(view.isForwardNavigationEnabled)
    }

    func testBundledLinkNavigationOpensSecondPage() {
        let view = DocumentationView(rootURL: rootURL)
        let textView = view.preferredInitialFirstResponder as! DocumentationTextView

        XCTAssertTrue(
            view.textView(
                textView,
                clickedOnLink: "details.html",
                at: 0
            )
        )
        XCTAssertEqual(
            view.currentPageURL,
            expectedPageURL(named: "details.html")
        )
        XCTAssertEqual(view.currentPageTitle, "Details")
        XCTAssertTrue(view.currentPageText.contains("Second page."))
        XCTAssertEqual(view.navigationHistoryIndex, 1)
        XCTAssertEqual(view.navigationHistoryCount, 2)
        XCTAssertTrue(view.isBackNavigationEnabled)
        XCTAssertFalse(view.isForwardNavigationEnabled)
    }

    func testBackForwardAndHomeNavigationRestoreRenderedPages() {
        let view = DocumentationView(rootURL: rootURL)
        XCTAssertTrue(
            view.navigate(to: rootURL.appendingPathComponent("details.html"))
        )

        view.goBack()
        XCTAssertEqual(view.currentPageTitle, "Reframer Help")
        XCTAssertEqual(view.navigationHistoryIndex, 0)
        XCTAssertEqual(view.navigationHistoryCount, 2)
        XCTAssertFalse(view.isBackNavigationEnabled)
        XCTAssertTrue(view.isForwardNavigationEnabled)

        view.goForward()
        XCTAssertEqual(view.currentPageTitle, "Details")
        XCTAssertTrue(view.currentPageText.contains("Second page."))
        XCTAssertEqual(view.navigationHistoryIndex, 1)
        XCTAssertTrue(view.isBackNavigationEnabled)
        XCTAssertFalse(view.isForwardNavigationEnabled)

        view.showHome()
        XCTAssertEqual(
            view.currentPageURL,
            expectedPageURL(named: "index.html")
        )
        XCTAssertEqual(view.currentPageTitle, "Reframer Help")
        XCTAssertEqual(view.navigationHistoryIndex, 2)
        XCTAssertEqual(view.navigationHistoryCount, 3)
        XCTAssertTrue(view.isBackNavigationEnabled)
        XCTAssertFalse(view.isForwardNavigationEnabled)
    }

    func testNewNavigationAfterBackTruncatesForwardHistory() {
        let view = DocumentationView(rootURL: rootURL)
        XCTAssertTrue(
            view.navigate(to: rootURL.appendingPathComponent("details.html"))
        )
        view.goBack()
        XCTAssertTrue(view.isForwardNavigationEnabled)

        XCTAssertTrue(
            view.navigate(to: rootURL.appendingPathComponent("alternate.html"))
        )

        XCTAssertEqual(view.currentPageTitle, "Alternate")
        XCTAssertTrue(view.currentPageText.contains("Alternate page."))
        XCTAssertEqual(view.navigationHistoryIndex, 1)
        XCTAssertEqual(view.navigationHistoryCount, 2)
        XCTAssertTrue(view.isBackNavigationEnabled)
        XCTAssertFalse(view.isForwardNavigationEnabled)

        view.goForward()
        XCTAssertEqual(
            view.currentPageURL,
            expectedPageURL(named: "alternate.html")
        )
    }

    func testExternalAndTraversalNavigationAreRejectedWithoutChangingPage() {
        let view = DocumentationView(rootURL: rootURL)
        let originalURL = view.currentPageURL
        let originalTitle = view.currentPageTitle
        let originalText = view.currentPageText

        let rejectedURLs = [
            URL(string: "https://example.com/help.html")!,
            rootURL.appendingPathComponent("../outside.html"),
            rootURL.appendingPathComponent("linked-outside.html"),
            rootURL.appendingPathComponent("notes.txt")
        ]

        for rejectedURL in rejectedURLs {
            XCTAssertFalse(
                view.navigate(to: rejectedURL),
                "Expected rejection for \(rejectedURL)"
            )
            XCTAssertEqual(view.currentPageURL, originalURL)
            XCTAssertEqual(view.currentPageTitle, originalTitle)
            XCTAssertEqual(view.currentPageText, originalText)
            XCTAssertEqual(view.navigationHistoryIndex, 0)
            XCTAssertEqual(view.navigationHistoryCount, 1)
            XCTAssertFalse(view.isBackNavigationEnabled)
            XCTAssertFalse(view.isForwardNavigationEnabled)
        }
    }

    func testLoaderRejectsTraversalNetworkSymlinksAndNonHTMLPages() {
        let loader = DocumentationPageLoader(rootURL: rootURL)

        XCTAssertNil(
            loader.validatedPageURL(
                rootURL.appendingPathComponent("../outside.html")
            )
        )
        XCTAssertNil(
            loader.validatedPageURL(
                URL(string: "https://example.com/help.html")!
            )
        )
        XCTAssertNil(
            loader.validatedPageURL(
                rootURL.appendingPathComponent("linked-outside.html")
            )
        )
        XCTAssertNil(
            loader.validatedPageURL(
                rootURL.appendingPathComponent("notes.txt")
            )
        )
        XCTAssertNotNil(
            loader.validatedPageURL(
                rootURL.appendingPathComponent("details.html")
            )
        )
    }

    func testNativeDocumentationViewExposesRenderedTextToAccessibility() {
        let view = DocumentationView(rootURL: rootURL)
        let textView = view.preferredInitialFirstResponder
            as? DocumentationTextView

        XCTAssertNotNil(textView)
        XCTAssertTrue(textView?.string.contains("Reframer Help") == true)
        XCTAssertTrue(
            (textView?.accessibilityValue() as? String)?
                .contains("Bundled documentation content.") == true
        )
    }

    func testMissingPageReturnsReadableError() {
        XCTAssertThrowsError(
            try DocumentationPageLoader(rootURL: rootURL)
                .page(named: "missing.html")
        ) { error in
            XCTAssertEqual(
                error.localizedDescription,
                DocumentationPageError.unreadablePage.localizedDescription
            )
        }
    }

    private func writePage(_ html: String, named name: String) throws {
        try Data(html.utf8).write(to: rootURL.appendingPathComponent(name))
    }

    private func expectedPageURL(named name: String) -> URL {
        rootURL.appendingPathComponent(name)
            .standardizedFileURL
            .resolvingSymlinksInPath()
    }
}
