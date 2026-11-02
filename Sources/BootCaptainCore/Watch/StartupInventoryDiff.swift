import Foundation

/// The product a new startup item is attributed to, for "X installed 2 new
/// startup items". `key` groups items and stays stable across checks; `name`
/// is what the user reads.
public struct StartupProduct: Sendable, Hashable {
    public var key: String
    public var name: String

    public init(key: String, name: String) {
        self.key = key
        self.name = name
    }
}

/// New startup items attributed to one product.
public struct NewStartupItems: Sendable, Equatable {
    public var product: StartupProduct
    /// Sorted by label.
    public var items: [WatchedStartupItem]

    public init(product: StartupProduct, items: [WatchedStartupItem]) {
        self.product = product
        self.items = items
    }
}

/// Compares the current startup inventory with the reviewed one and groups
/// what is new by product. Pure: the watcher supplies both sides.
public enum StartupInventoryDiff {
    /// Items whose identity is not in the reviewed inventory, one per id.
    public static func unreviewed(_ current: [WatchedStartupItem],
                                  reviewed: ReviewedInventory) -> [WatchedStartupItem] {
        var seen = Set<String>()
        return current.filter { item in
            guard !reviewed.contains(item.id) else { return false }
            return seen.insert(item.id).inserted
        }
    }

    /// New items grouped by product, ordered by product key.
    /// `installedApps` maps bundle identifiers to app names, so an item that
    /// only names its app through `AssociatedBundleIdentifiers` still reads
    /// as that app.
    public static func newItemsByProduct(
        current: [WatchedStartupItem],
        reviewed: ReviewedInventory,
        installedApps: [String: String] = [:],
        catalog: Catalog = .seed
    ) -> [NewStartupItems] {
        let new = unreviewed(current, reviewed: reviewed)
        var groups: [StartupProduct: [WatchedStartupItem]] = [:]
        var products: [String: StartupProduct] = [:]
        for item in new {
            let candidate = StartupProductAttribution.product(for: item, installedApps: installedApps,
                                                              catalog: catalog)
            // The first name seen for a key wins, so one product never
            // splits into two groups over a naming difference.
            let product = products[candidate.key] ?? candidate
            products[candidate.key] = product
            groups[product, default: []].append(item)
        }
        return groups
            .map { NewStartupItems(product: $0.key, items: $0.value.sorted { $0.label < $1.label }) }
            .sorted { $0.product.key < $1.product.key }
    }
}

/// Names the product behind a startup item from what a prompt-free read can
/// see, strongest evidence first: the owning app bundle, the app named in
/// `AssociatedBundleIdentifiers`, the curated catalog, then the label's
/// reverse-DNS vendor. Display and grouping only; never authorizes anything.
public enum StartupProductAttribution {
    public static func product(for item: WatchedStartupItem,
                               installedApps: [String: String] = [:],
                               catalog: Catalog = .seed) -> StartupProduct {
        if let app = item.owningApp {
            return StartupProduct(key: app.bundleIdentifier.map { "app:\($0)" } ?? "app-name:\(app.name)",
                                  name: app.name)
        }

        if let bundleID = item.associatedBundleIdentifiers.first(where: { installedApps[$0] != nil }),
           let name = installedApps[bundleID] {
            return StartupProduct(key: "app:\(bundleID)", name: name)
        }

        let entry = catalog.match(teamID: nil, label: item.label)
        if let bundleID = item.associatedBundleIdentifiers.first {
            let name = entry?.product ?? vendor(fromReverseDNS: bundleID) ?? bundleID
            return StartupProduct(key: "app:\(bundleID)", name: name)
        }

        if let entry {
            return StartupProduct(key: "catalog:\(entry.vendor)/\(entry.product)", name: entry.product)
        }

        if let vendor = vendor(fromReverseDNS: item.label) {
            return StartupProduct(key: "vendor:\(vendor.lowercased())", name: vendor)
        }

        return StartupProduct(key: "item:\(item.id)", name: DisplayPolish.prettifyLabel(item.label))
    }

    /// "com.docker.vmnetd" → "Docker", also behind a Team ID prefix
    /// ("2BUA8C4S2C.com.1password.helper" → "1password"). Nil when the label
    /// is not reverse-DNS, and for Apple's own prefix.
    static func vendor(fromReverseDNS label: String) -> String? {
        var parts = label.split(separator: ".").map(String.init)
        if let first = parts.first, first.count == 10,
           first.allSatisfy({ $0.isUppercase || $0.isNumber }) {
            parts.removeFirst()
        }
        guard parts.count >= 2 else { return nil }
        let vendor = parts[1]
        guard !(parts[0] == "com" && vendor == "apple") else { return nil }
        return vendor.prefix(1).uppercased() + vendor.dropFirst()
    }
}
