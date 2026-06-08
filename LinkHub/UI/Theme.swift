import Foundation
import CoreGraphics

enum PanelLayout {
    static let panelWidth: CGFloat = 320
    static let outerPadding: CGFloat = 8
    static let panelMaxHeight: CGFloat = 520        // PRD 04 D2
    static let interSectionSpacing: CGFloat = 8     // VStack(spacing: 8); UX-DR9
    static let rowHeight: CGFloat = 44              // PRD 04 D13
    static let rowHorizontalPadding: CGFloat = 16   // PRD 04 D13
    static let rowVerticalPadding: CGFloat = 11     // PRD 04 D13
    static let sectionHeaderVerticalPadding: CGFloat = 8
    static let signalBarsSize: CGFloat = 16         // epic AC #3
    static let networkListMaxHeight: CGFloat = 220  // PRD 04 D3 — reserved for Epic 2 ScrollView; OK to add now since constant is read-only
}
