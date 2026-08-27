import Testing
import Foundation
@testable import Pantry

@Suite("Quantities and units")
struct QuantityTests {

    @Test("Pieces read as a bare number next to the item's name")
    func formatsPiecesWithoutAUnit() {
        #expect(QuantityFormatter.string(quantity: 6, unit: .piece) == "6")
        #expect(QuantityFormatter.string(quantity: 500, unit: .gram) == "500 g")
    }

    @Test("Trailing zeroes are trimmed")
    func trimsTrailingZeroes() {
        #expect(QuantityFormatter.number(1.0) == "1")
        #expect(QuantityFormatter.number(1.50) == "1.5")
    }

    @Test("Countable units round to whole numbers and never go negative")
    func normalisesQuantities() {
        #expect(QuantityFormatter.normalise(2.4, unit: .piece) == 2)
        #expect(QuantityFormatter.normalise(2.6, unit: .piece) == 3)
        #expect(QuantityFormatter.normalise(-5, unit: .gram) == 0)
        #expect(QuantityFormatter.normalise(1.234, unit: .kilogram) == 1.23)
    }

    @Test("Step size suits the unit")
    func stepsSuitTheUnit() {
        #expect(MeasurementUnit.piece.stepIncrement == 1)
        #expect(MeasurementUnit.gram.stepIncrement == 50)
        #expect(MeasurementUnit.kilogram.stepIncrement == 0.25)
    }

    @Test("Mass and volume convert within their own dimension")
    func convertsWithinADimension() throws {
        #expect(UnitConverter.convert(1, from: .kilogram, to: .gram) == 1000)
        #expect(UnitConverter.convert(500, from: .millilitre, to: .litre) == 0.5)
        let ounces = try #require(UnitConverter.convert(1, from: .pound, to: .ounce))
        #expect(abs(ounces - 16) < 0.01)
    }

    @Test("Conversions that would be a guess return nothing")
    func refusesMeaninglessConversions() {
        #expect(UnitConverter.convert(200, from: .gram, to: .pack) == nil)
        #expect(UnitConverter.convert(1, from: .litre, to: .gram) == nil)
        #expect(!UnitConverter.areCompatible(.gram, .millilitre))
    }
}

@Suite("Expiry")
struct ExpiryTests {

    private let now = Date(timeIntervalSince1970: 1_756_000_000)

    private func date(daysFromNow days: Int) -> Date {
        Calendar.current.date(byAdding: .day, value: days, to: now) ?? now
    }

    @Test("Day counts are calendar days, not elapsed hours")
    func countsCalendarDays() {
        #expect(ExpirationCalculator.daysUntil(date(daysFromNow: 0), now: now) == 0)
        #expect(ExpirationCalculator.daysUntil(date(daysFromNow: 3), now: now) == 3)
        #expect(ExpirationCalculator.daysUntil(date(daysFromNow: -2), now: now) == -2)
        #expect(ExpirationCalculator.daysUntil(nil, now: now) == nil)
    }

    @Test("Freshness respects the user's chosen window")
    func classifiesFreshness() {
        #expect(ExpirationCalculator.freshness(for: date(daysFromNow: -1), now: now) == .past)
        #expect(ExpirationCalculator.freshness(for: date(daysFromNow: 0), now: now) == .today)
        #expect(ExpirationCalculator.freshness(for: date(daysFromNow: 2), now: now) == .useSoon)
        #expect(ExpirationCalculator.freshness(for: date(daysFromNow: 10), now: now) == .fresh)
        #expect(ExpirationCalculator.freshness(for: nil, now: now) == .unknown)
        #expect(ExpirationCalculator.freshness(for: date(daysFromNow: 5), useSoonWindowDays: 7, now: now) == .useSoon)
    }

    @Test("Only dates worth acting on are marked noteworthy")
    func flagsOnlyActionableStates() {
        #expect(FreshnessState.past.isNoteworthy)
        #expect(FreshnessState.today.isNoteworthy)
        #expect(FreshnessState.useSoon.isNoteworthy)
        #expect(!FreshnessState.fresh.isNoteworthy)
        #expect(!FreshnessState.unknown.isNoteworthy)
    }

    @Test("Suggested dates follow the category, and stay absent where there is no sensible default")
    func suggestsShelfLife() throws {
        let produce = try #require(ExpirationCalculator.suggestedExpiration(for: .produce, from: now))
        #expect(ExpirationCalculator.daysUntil(produce, now: now) == 7)
        #expect(ExpirationCalculator.suggestedExpiration(for: .other, from: now) == nil)
    }
}
