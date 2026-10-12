/// The user's mouse choices, persisted as one value.
struct MouseSettings: Codable, Equatable {
    /// Bundle identifiers of terminals, whose scrollback reads best a line at a time. Those installed seed the line-by-line apps.
    static let terminalApps = [
        "com.apple.Terminal",
        "com.mitchellh.ghostty",
        "com.googlecode.iterm2",
        "net.kovidgoyal.kitty",
        "dev.warp.Warp-Stable",
        "com.github.wez.wezterm",
        "org.alacritty",
        "co.zeit.hyper",
        "org.tabby",
        "com.raphamorim.rio",
    ]

    var isEnabled = false
    var wheelStep = WheelStep.default
    var direction = ScrollDirection.standard
    var isOptionPrecisionEnabled = false
    /// Bundle identifiers of apps where a notch scrolls one line, in the order the user added them.
    private(set) var lineByLineApps: [String]
    var isLookUpEnabled = true

    init(lineByLineApps: [String] = []) {
        self.lineByLineApps = lineByLineApps
    }

    mutating func addLineByLineApp(_ bundleID: String) {
        guard !lineByLineApps.contains(bundleID) else {
            return
        }
        lineByLineApps.append(bundleID)
    }

    mutating func removeLineByLineApp(_ bundleID: String) {
        lineByLineApps.removeAll { $0 == bundleID }
    }
}

enum WheelStep: UInt32, Codable, CaseIterable {
    case slow
    case `default`

    var lines: Int32 {
        switch self {
        case .slow: 2
        case .default: 3
        }
    }
}

enum ScrollDirection: UInt32, Codable, CaseIterable {
    case standard
    /// Content follows the fingers, as on a trackpad.
    case natural
}
