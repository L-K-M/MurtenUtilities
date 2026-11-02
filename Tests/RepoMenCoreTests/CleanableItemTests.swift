import XCTest
@testable import RepoMenCore

final class CleanableItemTests: XCTestCase {
    private let tagged = CleanableItem(
        label: "tagged cache", kind: .taggedCache, path: "/Users/test/.ccache",
        anchorPaths: ["/Users/test/.ccache/CACHEDIR.TAG"], isKnownCache: false)

    private var catalog: CleanableItem {
        CleanableItem(label: "ccache", kind: .compilerCache, path: tagged.path,
                      anchorPaths: [], isKnownCache: true, warning: "Compiler is running")
    }

    func testMergingDiscoveriesKeepsFirstSeenOrderAndCatalogMetadata() {
        let project = CleanableItem(label: "app/target", kind: .rustTarget,
                                    path: "/Users/test/dev/app/target",
                                    anchorPaths: ["/Users/test/dev/app/Cargo.toml"], isKnownCache: false)
        let cacheOnly = CleanableItem(label: "pip", kind: .pipCache,
                                     path: "/Users/test/Library/Caches/pip",
                                     anchorPaths: [], isKnownCache: true)
        var laterTagged = tagged
        laterTagged.sizeBytes = 100
        var laterCatalog = catalog
        laterCatalog.warning = "Later duplicate"

        let merged = CleanableItem.mergingDiscoveries(
            [tagged, project, laterTagged, catalog, cacheOnly, laterCatalog])

        XCTAssertEqual(merged, [catalog, project, cacheOnly],
                       "one row per path, retaining the first catalog record and its reclaim metadata")
    }

    func testMergingDiscoveriesNeverReplacesCatalogWithScannedRecord() {
        XCTAssertEqual(CleanableItem.mergingDiscoveries([catalog, tagged]), [catalog])
    }
}
