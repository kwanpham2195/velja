import Foundation
import Testing
@testable import VeljaCore

private let encodedLink = "https%3A%2F%2Fexample.com%2F%3Fa%3D1%26b%3D2"
private let decodedLink = URL(string: "https://example.com/?a=1&b=2")!

struct VeljaOpenCommandTests {
    @Test(arguments: [
        ("linkfork:open?url=\(encodedLink)", VeljaOpenCommand(url: decodedLink)),
        ("linkfork://open?url=\(encodedLink)&prompt", VeljaOpenCommand(url: decodedLink, forcesBrowserPicker: true)),
        ("linkfork:///open?url=\(encodedLink)&prompt=FALSE", VeljaOpenCommand(url: decodedLink)),
        ("linkfork://open/?url=\(encodedLink)&prompt=No", VeljaOpenCommand(url: decodedLink)),
        ("LINKFORK:open?url=\(encodedLink)&prompt=0", VeljaOpenCommand(url: decodedLink)),
        (
            "linkfork:open?url=\(encodedLink)&prompt=1&app=com.google.Chrome&profile=Profile%201",
            VeljaOpenCommand(
                url: decodedLink,
                forcesBrowserPicker: true,
                browserTarget: BrowserTarget(bundleIdentifier: "com.google.Chrome", profileDirectory: "Profile 1")
            )
        ),
    ])
    func acceptsOpenCommands(_ commandText: String, _ expected: VeljaOpenCommand) {
        #expect(VeljaOpenCommand.parseVeljaOpenCommand(URL(string: commandText)!) == expected)
    }

    @Test(arguments: [
        "linkfork:open",
        "linkfork:open?url=file%3A%2F%2F%2Fetc%2Fhosts",
        "linkfork:open?url=javascript%3Aalert(1)",
        "linkfork:settings?url=\(encodedLink)",
        "linkfork://open/extra?url=\(encodedLink)",
        "linkfork:open/extra?url=\(encodedLink)",
        "https://example.com/open?url=\(encodedLink)",
    ])
    func rejectsOtherCommands(_ commandText: String) {
        #expect(VeljaOpenCommand.parseVeljaOpenCommand(URL(string: commandText)!) == nil)
    }
}

struct LinkTextParserTests {
    @Test func findsOnlyWebLinksInFreeText() {
        #expect(LinkTextParser.webLinks(inText: "Contact bob@acme.com, see README.md and Node.js (https://example.com/a).")
            == [URL(string: "https://example.com/a")!])
        #expect(LinkTextParser.webLinks(inText: "Docs: example.com/page, then http://a.com/x and http://a.com/x again.")
            == [URL(string: "https://example.com/page")!, URL(string: "http://a.com/x")!])
    }

    @Test(arguments: [
        ("  https://example.com/a?b=1 \n", "https://example.com/a?b=1"),
        ("example.com/page", "https://example.com/page"),
        ("bob@acme.com", nil),
        ("mailto:bob@acme.com", nil),
        ("file:///etc/hosts", nil),
        ("javascript:alert(1)", nil),
        ("hello world", nil),
        ("localhost", nil),
    ] as [(String, String?)])
    func readsClipboardLink(_ text: String, _ expected: String?) {
        #expect(LinkTextParser.webLink(fromText: text)?.absoluteString == expected)
    }
}

struct TrackingParameterCleanerTests {
    @Test(arguments: [
        ("https://example.com/search?q=a%20b+c&UTM_Medium=email&page=2&fbclid=xyz#results", "https://example.com/search?q=a%20b+c&page=2#results"),
        ("https://a.com/p?utm_source=x&", "https://a.com/p"),
        ("https://x.com/user/status/1?s=20&t=abc", "https://x.com/user/status/1"),
        // Nothing to remove: returned byte for byte, including empty items and site-specific names on other sites.
        ("https://example.com/a?b=1&&flag&ref=main", "https://example.com/a?b=1&&flag&ref=main"),
        ("https://example.com/?s=term&si=1", "https://example.com/?s=term&si=1"),
        // Unsubscribe and preference pages need these subscriber identifiers.
        ("https://example.com/unsubscribe?mkt_tok=abc&ck_subscriber_id=1&ml_subscriber=2", "https://example.com/unsubscribe?mkt_tok=abc&ck_subscriber_id=1&ml_subscriber=2"),
        ("file:///tmp/page.html?utm_source=x", "file:///tmp/page.html?utm_source=x"),
    ])
    func removesTrackingParameters(_ link: String, _ expected: String) {
        #expect(TrackingParameterCleaner.removeTrackingParameters(from: URL(string: link)!).absoluteString == expected)
    }
}

struct NativeAppLinkRewriteTests {
    @Test func zoomMeetingKeepsHostAndJoinParameters() {
        let meeting = URL(string: "https://us02web.zoom.us/j/85551234567?uname=Jo%20Do&from=addon&pwd=Ab.Cd1&tk=t%2B1")!
        #expect(NativeAppLinkHandler.zoom.nativeAppURL(for: meeting)?.absoluteString
            == "zoommtg://us02web.zoom.us/join?action=join&confno=85551234567&pwd=Ab.Cd1&tk=t%2B1&uname=Jo%20Do")
        #expect(NativeAppLinkHandler.zoom.nativeAppURL(for: URL(string: "https://zoom.us/j/123/?pwd=")!)?.absoluteString
            == "zoommtg://zoom.us/join?action=join&confno=123")
        for otherLink in ["https://zoom.us/signin", "https://zoom.us/j/abc", "https://zoom.us/j/123/extra", "https://zoom.us.evil.com/j/123"] {
            #expect(NativeAppLinkHandler.zoom.nativeAppURL(for: URL(string: otherLink)!) == nil)
        }
    }
}

struct ShortURLRedirectTests {
    @Test func followsShortenerHopsOverHTTPSAndStopsBeforeTheDestination() async {
        let stopper = ShortURLRedirectStopper()
        let task = URLSession.shared.dataTask(with: URL(string: "https://bit.ly/abc")!)
        let redirectResponse = HTTPURLResponse(url: URL(string: "https://bit.ly/abc")!, statusCode: 301, httpVersion: nil, headerFields: nil)!
        func redirect(to link: String) async -> URLRequest? {
            await withCheckedContinuation { continuation in
                stopper.urlSession(.shared, task: task, willPerformHTTPRedirection: redirectResponse, newRequest: URLRequest(url: URL(string: link)!)) {
                    continuation.resume(returning: $0)
                }
            }
        }

        #expect(await redirect(to: "http://t.co/x")?.url == URL(string: "https://t.co/x"))
        #expect(stopper.destinationURL == nil)
        #expect(await redirect(to: "https://github.com/apple?ref=1") == nil)
        #expect(stopper.destinationURL == URL(string: "https://github.com/apple?ref=1"))
    }
}
