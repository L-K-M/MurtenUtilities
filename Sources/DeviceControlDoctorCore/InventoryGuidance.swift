import Foundation

/// What to do about an entry the module will not or cannot reset, in
/// words: where System Settings shows it and how to remove it there.
public enum InventoryGuidance {
    public static func steps(for entry: InventoryEntry) -> String {
        if entry.flags.contains(.system) {
            return "This entry is part of macOS. Leave it as it is."
        }
        if entry.flags.contains(.managed) {
            return "Your organization manages this permission through device management. Ask your administrator to change it."
        }
        let name = "“\(entry.client.name)”"
        guard let page = entry.service.settingsPageTitle else {
            return "System Settings has no list for \(entry.service.title). The entry goes away when tccutil can reset the app, or when the whole service is reset."
        }
        let location = "System Settings › Privacy & Security › \(page)"
        if entry.service.settingsCanRemove {
            return "Open \(location), select \(name), and click the remove (−) button."
        }
        return "Open \(location) and turn off \(name). That list has no remove button, so the entry stays until tccutil can reset the app."
    }
}
