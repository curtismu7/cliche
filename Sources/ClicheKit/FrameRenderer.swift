import AppKit

/// Procedural presentation chrome: browser/mac title bars and generic
/// device bezels, drawn straight into the beautify render context.
public enum FrameRenderer {
    /// Extra space the chrome needs around the screenshot, in pixels.
    public static func chromeInsets(
        _ style: FrameStyle, minDimension: CGFloat
    ) -> NSEdgeInsets {
        switch style {
        case .none:
            return NSEdgeInsets()
        case .browserLight, .browserDark, .macWindow:
            return NSEdgeInsets(top: 0.055 * minDimension, left: 0, bottom: 0, right: 0)
        case .phone:
            let b = 0.045 * minDimension
            return NSEdgeInsets(top: b, left: b, bottom: b, right: b)
        case .tablet:
            let b = 0.06 * minDimension
            return NSEdgeInsets(top: b, left: b, bottom: b, right: b)
        }
    }
}
