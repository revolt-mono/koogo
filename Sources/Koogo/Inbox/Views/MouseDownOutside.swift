import AppKit
import SwiftUI

extension View {
  func onMouseDownOutside(perform action: @escaping @MainActor (NSView) -> Void) -> some View {
    onLocalEvent([.leftMouseDown, .rightMouseDown]) { event, view in
      if !event.isInside(view) {
        action(view)
      }
      return event
    }
  }
}
