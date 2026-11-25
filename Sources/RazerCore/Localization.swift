import Foundation
import Observation

public enum AppLanguage: String, CaseIterable, Identifiable, Sendable {
    case english = "en"
    case chinese = "zh-Hans"

    public var id: String { rawValue }
    /// Each language is named in itself, so either can be found from the other.
    public var displayName: String { self == .english ? "English" : "简体中文" }
}

/// The interface language. New installs start in English. The choice is stored in the app's
/// defaults and takes effect at once: views read it through Observation when they call `L`.
@Observable
public final class Localization: @unchecked Sendable {
    public static let shared = Localization()
    public static let defaultsKey = "appLanguage"

    public var language: AppLanguage {
        didSet {
            UserDefaults.standard.set(language.rawValue, forKey: Self.defaultsKey)
            // Menu items AppKit supplies itself (Hide, Services…) follow this after a relaunch.
            UserDefaults.standard.set([language.rawValue], forKey: "AppleLanguages")
        }
    }

    init() {
        language = AppLanguage(rawValue: UserDefaults.standard.string(forKey: Self.defaultsKey) ?? "") ?? .english
    }
}

/// Picks the Chinese or English text for the current interface language.
public func L(_ chinese: String, _ english: String) -> String {
    Localization.shared.language == .chinese ? chinese : english
}
