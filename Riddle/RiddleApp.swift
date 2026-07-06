import SwiftUI

@main
struct RiddleApp: App {
    var body: some Scene {
        WindowGroup {
            DiaryView()
        }
    }
}

enum Secrets {
    static var apiKey: String { Bundle.main.object(forInfoDictionaryKey: "MOONSHOT_API_KEY") as? String ?? "" }
    static var baseURL: String { Bundle.main.object(forInfoDictionaryKey: "MOONSHOT_BASE_URL") as? String ?? "" }
    static var model: String { Bundle.main.object(forInfoDictionaryKey: "MOONSHOT_MODEL") as? String ?? "" }
}
