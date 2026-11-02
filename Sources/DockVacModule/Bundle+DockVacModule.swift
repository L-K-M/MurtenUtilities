import Foundation

extension Bundle {
  /// DockVac's resources. In the app they sit in Contents/Resources, where
  /// scripts/build-app.sh copies SwiftPM's resource bundles because code signing forbids
  /// them at the bundle root that the generated `Bundle.module` searches.
  static let dockVacModule: Bundle = {
    let name = "MurtenUtilities_DockVacModule.bundle"
    if let url = Bundle.main.resourceURL?.appendingPathComponent(name),
      let bundle = Bundle(url: url)
    {
      return bundle
    }
    return .module  // swift run and tests
  }()
}
