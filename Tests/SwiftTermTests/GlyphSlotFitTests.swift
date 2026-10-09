#if os(macOS)
import AppKit
import Testing
@testable import SwiftTerm

/// Tests for the single-cell fallback-glyph fitting added on top of the
/// wide-cell centering: Nerd Font icons arrive from fallback fonts with an
/// advance wider than the cell and must be centered/downscaled into their
/// slot instead of spilling into the neighbor cell.
final class GlyphSlotFitTests {
    private func makeView() throws -> TerminalView {
        let font = try #require(NSFont(name: "Menlo", size: 12))
        return TerminalView(frame: .zero, font: font)
    }

    @Test func configuredFacesAreNotFallbackFonts() throws {
        let view = try makeView()
        #expect(!view.isFallbackFont(view.fontSet.normal as CTFont))
        #expect(!view.isFallbackFont(view.fontSet.bold as CTFont))
        #expect(!view.isFallbackFont(view.fontSet.italic as CTFont))
        #expect(!view.isFallbackFont(view.fontSet.boldItalic as CTFont))
        let other = try #require(NSFont(name: "Monaco", size: 12))
        #expect(view.isFallbackFont(other as CTFont))
    }

    @Test func singleCellBaseFontGlyphIsUntouched() throws {
        let view = try makeView()
        var glyph = CGGlyph(0)
        var scalar = UniChar(65) // "A"
        CTFontGetGlyphsForCharacters(view.fontSet.normal, &scalar, &glyph, 1)
        let fit = view.glyphSlotFit(font: view.fontSet.normal as CTFont, glyph: glyph, columnWidth: 1)
        #expect(fit.isIdentity)
    }

    @Test func singleCellOversizeFallbackGlyphIsFittedIntoTheSlot() throws {
        let view = try makeView()
        // Stand in for a fallback-substituted Nerd Font icon: the same face at
        // twice the point size has an advance wider than one cell, which is
        // exactly the overflow condition the fit guards against.
        let oversized = try #require(NSFont(name: "Menlo", size: 24))
        var glyph = CGGlyph(0)
        var scalar = UniChar(65)
        CTFontGetGlyphsForCharacters(oversized, &scalar, &glyph, 1)
        var advance = CGSize.zero
        CTFontGetAdvancesForGlyphs(oversized as CTFont, .horizontal, &glyph, &advance, 1)
        let cellWidth = view.cellDimension.width
        try #require(advance.width > cellWidth)

        let fit = view.glyphSlotFit(font: oversized as CTFont, glyph: glyph, columnWidth: 1)

        #expect(!fit.isIdentity)
        // Scaled down so the ink fits the single cell, never enlarged.
        #expect(fit.scale < 1)
        #expect(fit.scale >= 0.1)
        // The scaled advance box is centered in the slot.
        #expect(abs(fit.dx - (cellWidth - advance.width * fit.scale) / 2) < 0.0001)
    }

    @Test func singleCellFallbackGlyphThatFitsIsUntouched() throws {
        let view = try makeView()
        // A fallback face whose advance fits the cell must not move: only
        // oversized glyphs are fitted.
        let small = try #require(NSFont(name: "Menlo", size: 6))
        var glyph = CGGlyph(0)
        var scalar = UniChar(65)
        CTFontGetGlyphsForCharacters(small, &scalar, &glyph, 1)
        var advance = CGSize.zero
        CTFontGetAdvancesForGlyphs(small as CTFont, .horizontal, &glyph, &advance, 1)
        try #require(advance.width <= view.cellDimension.width)

        let fit = view.glyphSlotFit(font: small as CTFont, glyph: glyph, columnWidth: 1)
        #expect(fit.isIdentity)
    }

    @Test func wideCellCenteringIsUnchanged() throws {
        let view = try makeView()
        var glyph = CGGlyph(0)
        var scalar = UniChar(87) // "W"
        CTFontGetGlyphsForCharacters(view.fontSet.normal, &scalar, &glyph, 1)
        var advance = CGSize.zero
        CTFontGetAdvancesForGlyphs(view.fontSet.normal as CTFont, .horizontal, &glyph, &advance, 1)

        let fit = view.glyphSlotFit(font: view.fontSet.normal as CTFont, glyph: glyph, columnWidth: 2)

        // Centered within the two-cell slot, not scaled.
        #expect(fit.scale == 1)
        #expect(abs(fit.dx - (2 * view.cellDimension.width - advance.width) / 2) < 0.0001)
        #expect(fit.dy == 0)
    }
}
#endif
