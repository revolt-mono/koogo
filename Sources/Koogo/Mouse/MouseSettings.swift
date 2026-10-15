struct MouseSettings: Codable, Equatable {
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
    /// content follows the fingers, as on a trackpad.
    case natural
}
