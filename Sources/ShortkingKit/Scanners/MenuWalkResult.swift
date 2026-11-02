enum MenuWalkResult<Entry> {
    case complete([Entry])
    case incomplete

    var cacheableEntries: [Entry]? {
        switch self {
        case .complete(let entries): return entries
        case .incomplete: return nil
        }
    }
}
