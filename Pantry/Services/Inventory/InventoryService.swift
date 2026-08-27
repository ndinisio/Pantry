import Foundation
import SwiftData

/// Every write to the inventory goes through here, so views stay free of business
/// logic and behaviour like "cooking decrements what you used" lives in one place.
@MainActor
struct InventoryService {
    let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    // MARK: - Items

    @discardableResult
    func add(_ item: PantryItem) -> PantryItem {
        context.insert(item)
        save()
        return item
    }

    /// Adds a batch, merging into existing items of the same name and unit rather than
    /// creating duplicates — "milk" bought twice should read as more milk, not two rows.
    @discardableResult
    func add(_ items: [PantryItem]) -> [PantryItem] {
        let existing = allItems()
        var result: [PantryItem] = []
        for item in items {
            if let match = existing.first(where: { $0.matchKey == item.matchKey && $0.unit == item.unit }) {
                match.quantity += item.quantity
                if match.expirationDate == nil { match.expirationDate = item.expirationDate }
                match.touch()
                result.append(match)
            } else {
                context.insert(item)
                result.append(item)
            }
        }
        save()
        return result
    }

    func delete(_ item: PantryItem) {
        context.delete(item)
        save()
    }

    func delete(_ items: [PantryItem]) {
        for item in items { context.delete(item) }
        save()
    }

    func adjustQuantity(of item: PantryItem, by delta: Double) {
        item.quantity = QuantityFormatter.normalise(item.quantity + delta, unit: item.unit)
        item.touch()
        save()
    }

    func setQuantity(of item: PantryItem, to value: Double) {
        item.quantity = QuantityFormatter.normalise(value, unit: item.unit)
        item.touch()
        save()
    }

    func togglePinned(_ item: PantryItem) {
        item.isPinned.toggle()
        item.touch()
        save()
    }

    func toggleOpened(_ item: PantryItem) {
        item.isOpened.toggle()
        item.openedDate = item.isOpened ? .now : nil
        item.touch()
        save()
    }

    // MARK: - Queries

    func allItems() -> [PantryItem] {
        let descriptor = FetchDescriptor<PantryItem>(sortBy: [SortDescriptor(\.name)])
        return (try? context.fetch(descriptor)) ?? []
    }

    /// Items at or past their date, soonest first. `nil` dates are excluded.
    func itemsNeedingAttention(windowDays: Int = 3, now: Date = .now) -> [PantryItem] {
        allItems()
            .filter { item in
                guard item.quantity > 0 else { return false }
                return ExpirationCalculator
                    .freshness(for: item.expirationDate, useSoonWindowDays: windowDays, now: now)
                    .isNoteworthy
            }
            .sorted { lhs, rhs in
                let l = lhs.expirationDate ?? .distantFuture
                let r = rhs.expirationDate ?? .distantFuture
                return l < r
            }
    }

    func recentlyAdded(limit: Int = 5) -> [PantryItem] {
        var descriptor = FetchDescriptor<PantryItem>(sortBy: [SortDescriptor(\.dateAdded, order: .reverse)])
        descriptor.fetchLimit = limit
        return (try? context.fetch(descriptor)) ?? []
    }

    func item(withID id: UUID) -> PantryItem? {
        let descriptor = FetchDescriptor<PantryItem>(predicate: #Predicate { $0.id == id })
        return try? context.fetch(descriptor).first
    }

    func counts(now: Date = .now, windowDays: Int = 3) -> InventorySummary {
        let items = allItems()
        var byLocation: [StorageLocation: Int] = [:]
        var byCategory: [FoodCategory: Int] = [:]
        var expiringSoon = 0
        var past = 0

        for item in items {
            if let location = item.location { byLocation[location, default: 0] += 1 }
            byCategory[item.category, default: 0] += 1
            switch ExpirationCalculator.freshness(for: item.expirationDate, useSoonWindowDays: windowDays, now: now) {
            case .past: past += 1
            case .today, .useSoon: expiringSoon += 1
            default: break
            }
        }

        return InventorySummary(
            totalItems: items.count,
            expiringSoon: expiringSoon,
            pastDate: past,
            byLocation: byLocation,
            byCategory: byCategory
        )
    }

    // MARK: - Cooking

    /// Deducts what a recipe used, scaled to the servings actually cooked.
    ///
    /// Deliberately forgiving: unmatched ingredients are skipped, and an item is
    /// emptied rather than going negative. Cooking should never fail because the
    /// numbers in the pantry were approximate.
    @discardableResult
    func consumeIngredients(for recipe: Recipe, servings: Int) -> [String] {
        let index = InventoryIndex(items: allItems(), useSoonWindowDays: 3)
        let factor = recipe.servings > 0 ? Double(servings) / Double(recipe.servings) : 1
        var consumed: [String] = []

        for ingredient in recipe.ingredients where !ingredient.isOptional {
            guard let item = index.item(for: ingredient.name) else { continue }
            let amount = ingredient.quantity * factor
            guard amount > 0 else { continue }

            if item.unit == ingredient.unit {
                item.quantity = QuantityFormatter.normalise(max(0, item.quantity - amount), unit: item.unit)
            } else if let converted = UnitConverter.convert(amount, from: ingredient.unit, to: item.unit) {
                item.quantity = QuantityFormatter.normalise(max(0, item.quantity - converted), unit: item.unit)
            } else if item.unit.isCountable && ingredient.unit.isCountable {
                item.quantity = QuantityFormatter.normalise(max(0, item.quantity - amount), unit: item.unit)
            } else {
                // Units that cannot be reconciled (a "pack" of rice against 200 g) are
                // left alone rather than guessed at.
                continue
            }
            item.touch()
            consumed.append(item.name)
        }

        save()
        return consumed
    }

    /// Records a cook, updates the recipe's history and returns the session.
    @discardableResult
    func markCooked(_ recipe: Recipe, servings: Int, consumeInventory: Bool = true) -> CookingSession {
        let session = CookingSession(recipe: recipe, servingsCooked: servings)
        session.finishedAt = .now
        if consumeInventory {
            session.consumedItemNames = consumeIngredients(for: recipe, servings: servings)
        }
        recipe.timesCooked += 1
        recipe.lastCookedDate = .now
        context.insert(session)
        save()
        return session
    }

    // MARK: - Persistence

    func save() {
        guard context.hasChanges else { return }
        do {
            try context.save()
        } catch {
            PantryLog.inventory.error("Could not save inventory changes: \(error.localizedDescription, privacy: .public)")
        }
    }
}

/// Counts used by the Home screen, the Pantry header and the widget.
struct InventorySummary: Equatable, Sendable {
    var totalItems: Int = 0
    var expiringSoon: Int = 0
    var pastDate: Int = 0
    var byLocation: [StorageLocation: Int] = [:]
    var byCategory: [FoodCategory: Int] = [:]

    var isEmpty: Bool { totalItems == 0 }
}
