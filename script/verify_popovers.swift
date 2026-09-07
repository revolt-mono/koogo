import AppKit
import ApplicationServices

// Run with Koogo's menu panel open. Only the two presentation triggers are clicked;
// reset confirmation and system actions are never activated. This checks input delivery
// and settled presentation state, not the visual trajectory of the native animation.
func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("\(message)\n".utf8))
    exit(1)
}

func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
    var value: CFTypeRef?
    AXUIElementCopyAttributeValue(element, name as CFString, &value)
    return value
}

func button(in element: AXUIElement, named name: String, depth: Int = 0) -> AXUIElement? {
    guard depth < 30 else { return nil }
    if attribute(element, kAXRoleAttribute) as? String == kAXButtonRole,
        attribute(element, kAXTitleAttribute) as? String == name
            || attribute(element, kAXDescriptionAttribute) as? String == name
    {
        return element
    }
    for child in attribute(element, kAXChildrenAttribute) as? [AXUIElement] ?? [] {
        if let found = button(in: child, named: name, depth: depth + 1) { return found }
    }
    return nil
}

func waitUntil(_ description: String, _ condition: () -> Bool) {
    let deadline = Date().addingTimeInterval(3)
    while !condition() {
        guard Date() < deadline else { fail(description) }
        Thread.sleep(forTimeInterval: 0.01)
    }
}

guard AXIsProcessTrusted() else { fail("Accessibility permission is required") }
let applications = NSRunningApplication.runningApplications(withBundleIdentifier: "com.revolt.koogo")
guard applications.count == 1, let app = applications.first else { fail("Run the signed Koogo app first") }
let root = AXUIElementCreateApplication(app.processIdentifier)
let source = CGEventSource(stateID: .hidSystemState)
var eventNumber: Int64 = 1

func windowCount() -> Int {
    let windows = CGWindowListCopyWindowInfo(.optionOnScreenOnly, 0) as? [[String: Any]] ?? []
    return windows.filter {
        ($0[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value == app.processIdentifier
            && (($0[kCGWindowBounds as String] as? [String: NSNumber])?["Height"]?.doubleValue ?? 0) > 40
    }.count
}

for name in ["Quota reset details", "Quick Actions"] {
    guard let trigger = button(in: root, named: name),
        let position = attribute(trigger, kAXPositionAttribute), CFGetTypeID(position) == AXValueGetTypeID(),
        let size = attribute(trigger, kAXSizeAttribute), CFGetTypeID(size) == AXValueGetTypeID()
    else { fail("Open the menu panel and wait for \(name)") }
    var origin = CGPoint.zero
    var dimensions = CGSize.zero
    // The CF type IDs were checked above; Swift cannot express that refinement.
    // swiftlint:disable force_cast
    guard AXValueGetValue(position as! AXValue, .cgPoint, &origin),
        AXValueGetValue(size as! AXValue, .cgSize, &dimensions)
    else { fail("Invalid trigger frame for \(name)") }
    // swiftlint:enable force_cast
    let point = CGPoint(x: origin.x + dimensions.width / 2, y: origin.y + dimensions.height / 2)
    guard
        let move = CGEvent(
            mouseEventSource: source,
            mouseType: .mouseMoved,
            mouseCursorPosition: point,
            mouseButton: .left
        )
    else { fail("Could not create mouse event") }
    move.post(tap: .cghidEventTap)

    func click(count: Int) {
        eventNumber += 1
        for type in [CGEventType.leftMouseDown, .leftMouseUp] {
            guard
                let event = CGEvent(
                    mouseEventSource: source,
                    mouseType: type,
                    mouseCursorPosition: point,
                    mouseButton: .left
                )
            else { fail("Could not create click event") }
            event.setIntegerValueField(.mouseEventClickState, value: Int64(count))
            event.setIntegerValueField(.mouseEventNumber, value: eventNumber)
            event.post(tap: .cghidEventTap)
            Thread.sleep(forTimeInterval: 0.01)
        }
    }

    func isPresented() -> Bool {
        guard let current = button(in: root, named: name),
            let value = attribute(current, kAXValueAttribute) as? String,
            value == "Expanded" || value == "Collapsed"
        else { fail("Presentation state unavailable for \(name)") }
        return value == "Expanded"
    }

    func assertPresentation(_ expected: Bool) {
        waitUntil("\(name) stopped responding without pointer movement (expected expanded: \(expected))") {
            isPresented() == expected && windowCount() == (expected ? 2 : 1)
        }
    }

    if isPresented() { click(count: 1) }
    assertPresentation(false)
    var expected = false
    // AXPress and clickCount=1 alone miss the native multi-click regression.
    // Do not move the pointer anywhere within these sequences.
    for count in 1...6 {
        click(count: count)
        expected.toggle()
        assertPresentation(expected)
    }
    for length in [3, 4, 7, 8] {
        for count in 1...length {
            click(count: count)
            expected.toggle()
            Thread.sleep(forTimeInterval: 0.035)
        }
        assertPresentation(expected)
        click(count: length + 1)
        expected.toggle()
        assertPresentation(expected)
    }
    if expected { click(count: 1) }
    assertPresentation(false)
    print("\(name): multi-click and burst input passed")
}
