import Foundation

/// The OAuth consent page and its error page (strings.md "OAuth consent page"). No script at all; the only inline
/// style is allowed by a per-response nonce, the form may only post back here (and follow the redirect to the
/// client), and the page can't be framed.
enum ConsentPage {
    static func consent(clientName: String, requestID: String, csrf: String, formTarget: String?) -> HTTPResponse {
        let name = escape(clientName)
        let body = """
        <main>
        <h1>Connect \(name)</h1>
        <p>\(name) wants to use Super Paste on this Mac.</p>
        <p>This will allow access to:</p>
        <ul><li>View and manage your clipboard items</li><li>View and manage your pinboards</li></ul>
        <p class="note">You can revoke this connection later in Super Paste Settings.</p>
        <form method="post" action="/authorize">
        <input type="hidden" name="request_id" value="\(escape(requestID))">
        <input type="hidden" name="csrf" value="\(escape(csrf))">
        <div class="buttons">
        <button type="submit" name="decision" value="deny">Cancel</button>
        <button type="submit" name="decision" value="approve" autofocus>Connect</button>
        </div>
        </form>
        </main>
        """
        return page(title: "Connect \(name)", body: body, status: 200, formTarget: formTarget)
    }

    static func error(_ message: String, status: Int = 400) -> HTTPResponse {
        page(title: "Super Paste", body: "<main><h1>Can't connect</h1><p>\(escape(message))</p></main>", status: status,
             formTarget: nil)
    }

    private static func page(title: String, body: String, status: Int, formTarget: String?) -> HTTPResponse {
        let nonce = MCPSecrets.generate(prefix: "")
        let html = """
        <!doctype html>
        <html lang="en"><head><meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <title>\(title)</title>
        <style nonce="\(nonce)">\(style)</style>
        </head><body>
        \(body)
        </body></html>
        """
        let formAction = ["'self'", formTarget].compactMap { $0 }.joined(separator: " ")
        let csp = "default-src 'none'; style-src 'nonce-\(nonce)'; form-action \(formAction); frame-ancestors 'none'; "
            + "base-uri 'none'"
        return HTTPResponse(status: status, headers: [("Content-Type", "text/html; charset=utf-8"),
                                                      ("Content-Security-Policy", csp)],
                            body: Data(html.utf8))
    }

    /// Plain system styling that follows light and dark mode (provisional: the design spec has no consent page).
    private static let style = """
    :root{color-scheme:light dark;font:15px/1.45 -apple-system,BlinkMacSystemFont,sans-serif}
    body{margin:0;display:flex;min-height:100vh;align-items:center;justify-content:center}
    main{max-width:26rem;padding:2rem}
    h1{font-size:1.4rem;margin:0 0 .75rem}
    ul{padding-left:1.2rem}
    .note{opacity:.7;font-size:.9rem}
    .buttons{display:flex;gap:.75rem;justify-content:flex-end;margin-top:1.5rem}
    button{font:inherit;padding:.4rem 1.1rem;border-radius:.4rem}
    """

    /// HTML-escapes text for element content and quoted attribute values.
    static func escape(_ text: String) -> String {
        var out = ""
        for c in text {
            switch c {
            case "&": out += "&amp;"
            case "<": out += "&lt;"
            case ">": out += "&gt;"
            case "\"": out += "&quot;"
            case "'": out += "&#39;"
            default: out.append(c)
            }
        }
        return out
    }
}
