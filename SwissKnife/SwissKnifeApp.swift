import SwiftUI

@main
struct SwissKnifeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem!
    var popover: NSPopover!

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem.button {
            if let iconPath = Bundle.main.path(forResource: "swiss_knife_icon", ofType: "png"),
               let original = NSImage(contentsOfFile: iconPath) {
                let size: CGFloat = 22
                let angle: CGFloat = -15
                let rad = angle * .pi / 180
                let newSize = NSSize(width: size, height: size)
                let rotated = NSImage(size: newSize)
                rotated.lockFocus()
                let transform = NSAffineTransform()
                transform.translateX(by: size / 2, yBy: size / 2)
                transform.rotate(byDegrees: angle)
                transform.translateX(by: -size / 2, yBy: -size / 2)
                transform.concat()
                original.draw(in: NSRect(origin: .zero, size: newSize))
                rotated.unlockFocus()
                rotated.isTemplate = true
                button.image = rotated
            } else {
                button.image = NSImage(systemSymbolName: "wrench.and.screwdriver", accessibilityDescription: "SwissKnife")
            }
            button.action = #selector(togglePopover)
            button.target = self
        }

        popover = NSPopover()
        popover.contentSize = Tool.homeSize
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(rootView: MainView(popover: popover))
    }

    @objc func togglePopover() {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }
}
