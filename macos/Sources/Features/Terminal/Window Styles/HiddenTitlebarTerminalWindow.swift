import AppKit

class HiddenTitlebarTerminalWindow: TerminalWindow {
    // No titlebar, we don't support accessories.
    override var supportsUpdateAccessory: Bool { false }

    override func awakeFromNib() {
        super.awakeFromNib()

        // Setup our initial style
        reapplyHiddenStyle()

        // Notifications
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(fullscreenDidExit(_:)),
            name: .fullscreenDidExit,
            object: nil)

        // macOS re-lays the traffic lights to their default (corner-hugging) spot on various relayouts —
        // window resize, and notably a tab/session switch (which would otherwise flash the buttons back to
        // the default for a moment). Re-inset on resize and on the window's update cycle; the reposition is
        // a no-op once they're in place, so the didUpdate firing is cheap.
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(relayoutTrafficLights(_:)),
            name: NSWindow.didResizeNotification,
            object: self)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(relayoutTrafficLights(_:)),
            name: NSWindow.didUpdateNotification,
            object: self)
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    private static let hiddenStyleMask: NSWindow.StyleMask = [
        // We need `titled` in the mask to get the normal window frame
        .titled,

        // Full size content view so we can extend
        // content in to the hidden titlebar's area
        .fullSizeContentView,

        .resizable,
        .closable,
        .miniaturizable,
    ]

    /// Apply the hidden titlebar style.
    private func reapplyHiddenStyle() {
        // If our window is fullscreen then we don't reapply the hidden style because
        // it can result in messing up non-native fullscreen. See:
        // https://github.com/ghostty-org/ghostty/issues/8415
        if terminalController?.fullscreenStyle?.isFullscreen ?? false {
            return
        }

        // Apply our style mask while preserving the .fullScreen option
        if styleMask.contains(.fullScreen) {
            styleMask = Self.hiddenStyleMask.union([.fullScreen])
        } else {
            styleMask = Self.hiddenStyleMask
        }

        // Hide the title
        titleVisibility = .hidden
        titlebarAppearsTransparent = true

        // Fork change: keep the traffic lights (close/miniaturize/zoom) visible, floating over the
        // content, instead of upstream's hide-them-entirely for this style. The sidebar insets its
        // top to clear them (TerminalController.sidebarTopInset → SidebarView.topInset). The
        // titleVisibility/.transparent settings above keep the rest of the titlebar invisible, so
        // only the buttons show.
        standardWindowButton(.closeButton)?.isHidden = false
        standardWindowButton(.miniaturizeButton)?.isHidden = false
        standardWindowButton(.zoomButton)?.isHidden = false
        titlebarSeparatorStyle = .none

        // Disallow tabbing if the titlebar is hidden, since that will (should) also hide the tab bar.
        tabbingMode = .disallowed

        // Keep the titlebar container visible -- it hosts the traffic lights. (Upstream hid it here
        // to nuke any title bleed-through; we rely on titleVisibility + titlebarAppearsTransparent
        // for that instead, so the buttons survive.)
        if let themeFrame = contentView?.superview,
           let titleBarContainer = themeFrame.firstDescendant(withClassName: "NSTitlebarContainerView") {
            titleBarContainer.isHidden = false
        }

        // Inset the floating traffic lights so they don't crowd the rounded corner / sidebar. macOS may
        // finish laying them out after this returns, so re-apply on the next runloop tick too.
        repositionTrafficLights()
        DispatchQueue.main.async { [weak self] in self?.repositionTrafficLights() }
    }

    /// Floating-traffic-light inset from the window's top-left corner. Tuned so the rendered button frame
    /// lands at an 18×18pt inset — matching macOS system apps (measured from Messages: close button at an
    /// 18,18 offset from its window corner) — rather than the default corner-hugging position the full-size
    /// content view produces. (These target values render ~1pt smaller in practice, hence 19.)
    private static let trafficLightInset = CGPoint(x: 19, y: 19)

    /// Re-positions the close/miniaturize/zoom buttons as a group, preserving their spacing, with a
    /// comfortable top-left inset. Used because the hidden titlebar's full-size content view otherwise
    /// places them hard against the window corner.
    private func repositionTrafficLights() {
        let buttons = [
            standardWindowButton(.closeButton),
            standardWindowButton(.miniaturizeButton),
            standardWindowButton(.zoomButton),
        ].compactMap { $0 }
        guard let container = buttons.first?.superview, let first = buttons.first else { return }

        let minX = buttons.map(\.frame.minX).min() ?? 0
        let dx = Self.trafficLightInset.x - minX
        let targetY = container.bounds.height - Self.trafficLightInset.y - first.frame.height

        // Skip if already positioned. This is the loop guard *and* what makes it cheap to call from the
        // frequent didUpdate notification: once the buttons are at the inset, re-runs are no-ops, and we
        // only do work the moment macOS resets them to the default corner (e.g. on a tab/session switch).
        if abs(dx) < 0.5 && abs(first.frame.minY - targetY) < 0.5 { return }

        for button in buttons {
            let y = container.bounds.height - Self.trafficLightInset.y - button.frame.height
            button.setFrameOrigin(NSPoint(x: button.frame.minX + dx, y: y))
        }
    }

    // MARK: NSWindow

    override var title: String {
        didSet {
            // Updating the title text as above automatically reveals the
            // native title view in macOS 15.0 and above. Since we're using
            // a custom view instead, we need to re-hide it.
            reapplyHiddenStyle()
        }
    }

    // We override this so that with the hidden titlebar style the titlebar
    // area is not draggable.
    override var contentLayoutRect: CGRect {
        var rect = super.contentLayoutRect
        rect.origin.y = 0
        rect.size.height = self.frame.height
        return rect
    }

    // MARK: Notifications

    @objc private func fullscreenDidExit(_ notification: Notification) {
        // Make sure they're talking about our window
        guard let fullscreen = notification.object as? FullscreenBase else { return }
        guard fullscreen.window == self else { return }

        // On exit we need to reapply the style because macOS breaks it usually.
        // This is safe to call repeatedly so if its not broken its still safe.
        reapplyHiddenStyle()
    }

    @objc private func relayoutTrafficLights(_ notification: Notification) {
        repositionTrafficLights()
    }
}
