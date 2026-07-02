import Foundation

/// Central place for build-time feature toggles.
///
/// To disable a feature for the final App Store build, flip its flag to `false`
/// here — no other code needs to change.
enum FeatureFlags {

    /// Shows the "Save LED Simulation" export option in the Gallery, which writes
    /// the glowing LED-bar look (round pixels on black, no frame) to the Photo
    /// Library. Set to `false` for the final build to hide it.
    static let ledSimulationExport = false
}
