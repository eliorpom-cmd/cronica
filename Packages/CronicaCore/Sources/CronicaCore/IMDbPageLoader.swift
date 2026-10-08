//
//  IMDbPageLoader.swift
//  CronicaCore
//

#if canImport(WebKit)
import WebKit

/// Loads a public imdb.com page in an offscreen WebKit view and returns the JSON the page embeds
/// for its own rendering (Next.js `__NEXT_DATA__`).
enum IMDbPageLoader {
    /// Dedicated store so IMDb cookies stay apart from other web views in the app.
    private static let dataStoreID = UUID(uuidString: "6D1B2C4E-9A3F-4E0B-8C55-2F6A1D7E3B90")!
    private static let script = "document.getElementById('__NEXT_DATA__')?.textContent ?? null"

    @MainActor
    static func embeddedData(from url: URL, timeout: Duration = .seconds(20)) async throws -> Data {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = WKWebsiteDataStore(forIdentifier: dataStoreID)
        let webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 390, height: 844), configuration: configuration)
        webView.load(URLRequest(url: url))
        defer { webView.stopLoading() }

        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        // IMDb can answer with a short browser check that reloads the page, so poll until the data shows up.
        while clock.now < deadline {
            try await Task.sleep(for: .milliseconds(250))
            if let text = try? await webView.evaluateJavaScript(script) as? String,
               let data = text.data(using: .utf8) {
                return data
            }
        }
        throw NetworkError.unreachable
    }
}
#endif
