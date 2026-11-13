#if os(iOS)
import SwiftUI

public enum QIcons {
    // MARK: - Navigation & Actions

    public static let settings = "gear"
    public static let search = "magnifyingglass"
    public static let searchSpark = "sparkle.magnifyingglass"
    public static let delete = "trash"

    // MARK: - Status

    public static let successFill = "checkmark.circle.fill"
    public static let success = "checkmark.circle"
    public static let warningFill = "exclamationmark.triangle.fill"
    public static let warning = "exclamationmark.triangle"
    public static let errorFill = "xmark.circle.fill"
    public static let cancelFill = "xmark.circle.fill"

    // MARK: - Photos

    public static let photoStack = "photo.stack"
    public static let photoStackFill = "photo.stack.fill"
    public static let photoAngled = "photo.on.rectangle.angled"
    public static let photoError = "photo.badge.exclamationmark"

    // MARK: - Features

    public static let sparkles = "sparkles"
    public static let trashCircle = "trash.circle"
    public static let trashFill = "trash.fill"
    public static let fullscreen = "arrow.up.left.and.arrow.down.right"
    public static let xmark = "xmark"
    public static let clock = "clock.fill"
    public static let stackFill = "square.stack.3d.up.fill"
    public static let squareGrid = "square.grid.2x2"
    public static let rectangleStack = "rectangle.stack"
    public static let refresh = "arrow.clockwise"
}

#endif
