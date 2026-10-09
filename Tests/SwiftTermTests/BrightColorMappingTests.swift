//
//  BrightColorMappingTests.swift
//
//  Bright ANSI foreground mapping (Pine issue #1650).
//
//  `useBrightColors` historically coupled two independent behaviors:
//  bold text promoting to the bright palette slots (0-7 -> 8-15), and —
//  when disabled — every palette index above 7 collapsing onto `index - 8`.
//  The collapse made the bright slots 8-15 unreachable for foreground text
//  (`\e[38;5;8m` … `\e[38;5;15m`, SGR 90-97), shifted the whole 16-255
//  extended range down by 8, and forced bright foregrounds to a bold font.
//
//  `collapseBrightColorsToBase` decouples the two: with it set to false the
//  palette indexes address their own slots while `useBrightColors = false`
//  keeps bold text on the base colors.
//
import Foundation
import Testing

@testable import SwiftTerm

#if os(macOS)
import AppKit

final class BrightColorMappingTests {

    /// Installs a palette whose slots are trivially distinguishable:
    /// slot `i` is the gray `(i * 16, i * 16, i * 16)`.
    @MainActor private func makeView() -> TerminalView {
        let view = TerminalView(frame: CGRect(x: 0, y: 0, width: 320, height: 160))
        view.installColors((0..<16).map { i in
            let v = UInt16(i * 16) * 257
            return Color(red: v, green: v, blue: v)
        })
        return view
    }

    private func assertSlot(_ actual: NSColor, _ slot: Int, _ comment: Comment? = nil) {
        let expected = CGFloat(slot * 16) / 255.0
        let srgb = actual.usingColorSpace(.sRGB) ?? actual
        #expect(abs(srgb.redComponent - expected) < 0.001, comment ?? "expected palette slot \(slot)")
        #expect(abs(srgb.greenComponent - expected) < 0.001)
        #expect(abs(srgb.blueComponent - expected) < 0.001)
    }

    @MainActor @Test func defaultsPreserveHistoricalBehavior() {
        let view = makeView()
        #expect(view.useBrightColors == true)
        #expect(view.collapseBrightColorsToBase == true, "the collapse defaults on for backward compatibility")
    }

    @MainActor @Test func useBrightColorsPromotesBoldAndKeepsBrightSlots() {
        let view = makeView()
        // bold on a base slot promotes to the bright variant
        assertSlot(view.mapColor(color: .ansi256(code: 1), isFg: true, isBold: true), 9)
        // explicit bright indexes already address their own slots here
        assertSlot(view.mapColor(color: .ansi256(code: 9), isFg: true, isBold: false), 9)
        assertSlot(view.mapColor(color: .ansi256(code: 8), isFg: true, isBold: false), 8)
    }

    @MainActor @Test func legacyCollapseFoldsEverythingAboveSeven() {
        let view = makeView()
        view.useBrightColors = false
        // bright slots fold onto the base palette
        for code: UInt8 in 8...15 {
            assertSlot(
                view.mapColor(color: .ansi256(code: code), isFg: true, isBold: false, useBrightColors: false),
                Int(code) - 8,
                "legacy mode must collapse \(code) -> \(code - 8)"
            )
        }
        // and the extended range shifts down by 8 as well
        let collapsed = view.mapColor(color: .ansi256(code: 200), isFg: true, isBold: false, useBrightColors: false)
        let expected = NSColor.make(color: view.terminal.ansiColors[192])
        #expect(collapsed == expected, "legacy mode shifts the extended 16-255 range down by 8")
    }

    @MainActor @Test func distinctBrightSlotsResolveTheirOwnPaletteEntries() {
        let view = makeView()
        view.useBrightColors = false
        view.collapseBrightColorsToBase = false
        // both the 256-color form and the SGR 90-97 form land on ansi256
        // codes 8-15, and each must read its own palette slot
        for code: UInt8 in 8...15 {
            assertSlot(
                view.mapColor(color: .ansi256(code: code), isFg: true, isBold: false, useBrightColors: false),
                Int(code),
                "slot \(code) must not collapse to \(code - 8)"
            )
        }
    }

    @MainActor @Test func boldDoesNotPromoteOrCollapseInDistinctSlotMode() {
        let view = makeView()
        view.useBrightColors = false
        view.collapseBrightColorsToBase = false
        // bold text keeps its base color (#733: no bold -> bright promotion)
        assertSlot(view.mapColor(color: .ansi256(code: 1), isFg: true, isBold: true, useBrightColors: false), 1)
        // a bold bright index keeps its bright color
        assertSlot(view.mapColor(color: .ansi256(code: 9), isFg: true, isBold: true, useBrightColors: false), 9)
    }

    @MainActor @Test func extendedRangeIsUntouchedInDistinctSlotMode() {
        let view = makeView()
        view.useBrightColors = false
        view.collapseBrightColorsToBase = false
        let resolved = view.mapColor(color: .ansi256(code: 200), isFg: true, isBold: false, useBrightColors: false)
        #expect(resolved == NSColor.make(color: view.terminal.ansiColors[200]),
                "extended indexes must address their own slots, not shift down by 8")
    }

    @MainActor @Test func backgroundAlwaysResolvesBrightSlots() {
        let view = makeView()
        view.useBrightColors = false
        // backgrounds are mapped with bright colors enabled, so they never
        // collapse — this must hold in every configuration
        assertSlot(view.mapColor(color: .ansi256(code: 11), isFg: false, isBold: false), 11)
        view.collapseBrightColorsToBase = false
        assertSlot(view.mapColor(color: .ansi256(code: 11), isFg: false, isBold: false), 11)
    }

    @MainActor @Test func brightForegroundForcesBoldFontOnlyWhenCollapsed() {
        let view = makeView()
        let bright = Attribute(fg: .ansi256(code: 9), bg: .defaultColor, style: .none)

        // legacy: the bold font compensates for the collapsed color
        view.useBrightColors = false
        view.collapseBrightColorsToBase = true
        var attrs = view.getAttributes(bright, withUrl: false)
        #expect(attrs?[.font] as? NSFont == view.fontSet.bold,
                "collapsed bright foreground must fall back to the bold font")

        // distinct slots: the bright color speaks for itself, no bold forcing
        view.collapseBrightColorsToBase = false
        attrs = view.getAttributes(bright, withUrl: false)
        #expect(attrs?[.font] as? NSFont == view.fontSet.normal,
                "a bright slot of its own must not force the bold font")
        assertSlot(attrs?[.foregroundColor] as? NSColor ?? .clear, 9)
    }
}
#endif
