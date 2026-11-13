#if os(iOS)
import Foundation
import Testing
import SweepDesignSystem

struct LocalizationTests {
    @Test func packageResourceResolvesOutsideItsModule() {
        var title = L10n.appTitle
        title.locale = Locale(identifier: "en")
        #expect(String(localized: title) == "Qdrant PhotoSweep")
    }
}
#endif
