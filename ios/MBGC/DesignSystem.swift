import SwiftUI

enum DesignSystem {
    enum Spacing {
        static let s4: CGFloat = 4
        static let s6: CGFloat = 6
        static let s8: CGFloat = 8
        static let s10: CGFloat = 10
        static let s12: CGFloat = 12
        static let s14: CGFloat = 14
        static let s16: CGFloat = 16
        static let s20: CGFloat = 20
        static let s24: CGFloat = 24
        static let s32: CGFloat = 32
        static let s40: CGFloat = 40

        static let screenHorizontalMargin: CGFloat = 24
        static let sectionVerticalSpacing: CGFloat = 32
    }

    enum CornerRadius {
        static let card: CGFloat = 16
        static let button: CGFloat = 12
        static let pill: CGFloat = 24
    }

    enum Typography {
        static let screenTitle = Font.system(size: 40, weight: .bold)
        static let sectionTitle = Font.system(size: 24, weight: .semibold)
        static let cardTitle = Font.system(size: 20, weight: .semibold)
        static let body = Font.system(size: 17, weight: .regular)
        static let metadata = Font.system(size: 15, weight: .regular)
        static let stepLabel = Font.system(size: 16, weight: .medium)
    }
}
