//
//  LinkColorTests.swift
//
//  Hyperlink underline color override (Pine issue #1661).
//
//  `TerminalView.linkColor` recolors the underline drawn for hyperlinks
//  (OSC 8 payloads and implicit link matches). When unset (`nil`, the
//  default), link cells keep the historical behavior of underlining in the
//  cell's foreground color. Only the decoration is recolored — the link
//  text keeps its cell foreground so program-owned SGR colors stay intact.
//
#if os(macOS)
import AppKit
import Foundation
import Testing

@testable import SwiftTerm

@Suite("TerminalView link color")
struct LinkColorTests {

    @MainActor private func makeView() -> TerminalView {
        TerminalView(frame: CGRect(x: 0, y: 0, width: 320, height: 160))
    }

    private func assertSameColor(_ actual: NSColor?, _ expected: NSColor, _ comment: Comment) {
        let a = actual?.usingColorSpace(.sRGB)
        let e = expected.usingColorSpace(.sRGB) ?? expected
        #expect(a != nil, comment)
        #expect(abs((a?.redComponent ?? -1) - e.redComponent) < 0.001, comment)
        #expect(abs((a?.greenComponent ?? -1) - e.greenComponent) < 0.001, comment)
        #expect(abs((a?.blueComponent ?? -1) - e.blueComponent) < 0.001, comment)
    }

    @MainActor @Test func linkColorDefaultsToNil() {
        #expect(makeView().linkColor == nil)
    }

    @MainActor @Test func linkUnderlineUsesCellForegroundByDefault() {
        let view = makeView()
        let fg = NSColor(srgbRed: 0.8, green: 0.7, blue: 0.6, alpha: 1)
        view.nativeForegroundColor = fg

        let attrs = view.getAttributes(.empty, withUrl: true)

        assertSameColor(attrs?[.foregroundColor] as? NSColor, fg, "link text keeps the cell foreground")
        assertSameColor(attrs?[.underlineColor] as? NSColor, fg,
                        "without a linkColor the underline keeps the historical foreground color")
    }

    @MainActor @Test func linkUnderlineUsesLinkColorWhenSet() {
        let view = makeView()
        let fg = NSColor(srgbRed: 0.8, green: 0.7, blue: 0.6, alpha: 1)
        let link = NSColor(srgbRed: 0.1, green: 0.4, blue: 0.9, alpha: 1)
        view.nativeForegroundColor = fg
        view.linkColor = link

        let attrs = view.getAttributes(.empty, withUrl: true)

        assertSameColor(attrs?[.foregroundColor] as? NSColor, fg,
                        "linkColor recolors only the underline, not the text")
        assertSameColor(attrs?[.underlineColor] as? NSColor, link,
                        "link underline must use linkColor")
    }

    @MainActor @Test func assigningLinkColorFlushesCachedLinkAttributes() {
        let view = makeView()
        // Populate the urlAttributes cache under the default (foreground) color.
        _ = view.getAttributes(.empty, withUrl: true)

        let link = NSColor(srgbRed: 0.1, green: 0.4, blue: 0.9, alpha: 1)
        view.linkColor = link
        let attrs = view.getAttributes(.empty, withUrl: true)

        assertSameColor(attrs?[.underlineColor] as? NSColor, link,
                        "a cached link attribute must not survive a linkColor change")
    }

    @MainActor @Test func clearingLinkColorRestoresForegroundUnderline() {
        let view = makeView()
        let fg = NSColor(srgbRed: 0.8, green: 0.7, blue: 0.6, alpha: 1)
        view.nativeForegroundColor = fg
        view.linkColor = NSColor(srgbRed: 0.1, green: 0.4, blue: 0.9, alpha: 1)

        view.linkColor = nil
        let attrs = view.getAttributes(.empty, withUrl: true)

        assertSameColor(attrs?[.underlineColor] as? NSColor, fg,
                        "resetting linkColor to nil restores foreground underlines")
    }
}
#endif
