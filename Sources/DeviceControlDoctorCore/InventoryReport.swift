import Foundation

/// The plain-text report Copy Report puts on the clipboard. It names apps,
/// identifiers and paths, so the pane says so before copying; nothing sends
/// it anywhere.
public enum InventoryReport {
    public static func text(_ inventory: PermissionInventory, system: String, timeZone: TimeZone = .current) -> String {
        var lines: [String] = []
        lines.append("App Permission Checkup: privacy permissions")
        lines.append("Read \(timestamp(inventory.readAt, timeZone: timeZone)) on \(system)")
        lines.append("")
        lines.append("Sources")
        for source in inventory.sources { lines.append("  " + source.summary) }
        lines.append("")
        let counts = InventoryFilter.allCases.filter { $0 != .all }.map { "\($0.title) \(inventory.count($0))" }
        lines.append("Entries \(inventory.entries.count): " + counts.joined(separator: ", "))
        lines.append("A recorded decision is not proof of effective access. Organization policy can still allow or deny it.")

        for (service, _) in inventory.serviceCounts {
            let entries = inventory.entries.filter { $0.service == service }
            lines.append("")
            lines.append("\(service.title) (\(service.identifier)), \(entries.count)")
            for entry in entries { lines.append("  " + line(for: entry, timeZone: timeZone)) }
        }
        return lines.joined(separator: "\n") + "\n"
    }

    static func line(for entry: InventoryEntry, timeZone: TimeZone) -> String {
        var parts = [entry.record.decision.title, entry.client.name]
        if entry.client.name != entry.record.client { parts.append(entry.record.client) }
        if let target = entry.record.target { parts.append("controls \(entry.target?.name ?? target)") }
        parts.append(entry.record.database.title.lowercased())
        if let changed = entry.record.lastModified { parts.append("changed \(timestamp(changed, timeZone: timeZone))") }
        if let reason = entry.record.reasonTitle { parts.append("reason \(reason)") }
        var line = parts.joined(separator: " · ")
        if !entry.flagTitles.isEmpty { line += " [\(entry.flagTitles.joined(separator: ", "))]" }
        return line
    }

    static func timestamp(_ date: Date, timeZone: TimeZone) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter.string(from: date)
    }
}
