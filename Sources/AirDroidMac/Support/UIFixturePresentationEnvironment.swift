import SwiftUI
import TetherPaneUIFixtureSupport

private struct UIFixturePresentationProfileKey: EnvironmentKey {
    static let defaultValue = UIFixturePresentationProfile.system
}

extension EnvironmentValues {
    var uiFixturePresentationProfile: UIFixturePresentationProfile {
        get { self[UIFixturePresentationProfileKey.self] }
        set { self[UIFixturePresentationProfileKey.self] = newValue }
    }
}
