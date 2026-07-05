/// The all-in-one capture strip: every mode, its UI attributes, and the
/// routing rule. `switchesInPlace` modes are drag-selections on the frozen
/// frame; the others dismiss the overlay and run their own flow.
public enum AllInOneMode: CaseIterable, Equatable {
    case region, window, fullScreen, ocr

    public var label: String {
        switch self {
        case .region: return "Region"
        case .window: return "Window"
        case .fullScreen: return "Full Screen"
        case .ocr: return "Copy Text"
        }
    }

    public var symbol: String {
        switch self {
        case .region: return "rectangle.dashed"
        case .window: return "macwindow"
        case .fullScreen: return "rectangle.inset.filled"
        case .ocr: return "text.viewfinder"
        }
    }

    /// Number-key shortcut inside the overlay, in strip order.
    public var keyEquivalent: String {
        String(AllInOneMode.allCases.firstIndex(of: self)! + 1)
    }

    /// True for modes that select on the frozen frame; false for modes that
    /// tear the overlay down and delegate to their existing flow.
    public var switchesInPlace: Bool {
        switch self {
        case .region, .ocr: return true
        case .window, .fullScreen: return false
        }
    }

    public static func mode(forKey key: String) -> AllInOneMode? {
        allCases.first { $0.keyEquivalent == key }
    }
}
