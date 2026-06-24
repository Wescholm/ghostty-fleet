# AppKit Bridging (macOS)

Embed AppKit inside SwiftUI and vice-versa — essential for a Ghostty-style app where the terminal surface is an NSView and chrome is SwiftUI.

> Fetch tip: the human doc pages are a JS app (empty when fetched). For live detail, fetch the **DocC JSON** endpoint (`.../tutorials/data/documentation/swiftui/<symbol>.json`), not the HTML.

## Contents

- [NSViewRepresentable](#nsviewrepresentable)
- [NSViewControllerRepresentable](#nsviewcontrollerrepresentable)
- [NSViewRepresentableContext](#nsviewrepresentablecontext)
- [NSHostingController](#nshostingcontroller)
- [NSHostingView](#nshostingview)
- [NSHostingSizingOptions](#nshostingsizingoptions)

---

## NSViewRepresentable

[Apple docs](https://developer.apple.com/documentation/swiftui/nsviewrepresentable) · [DocC JSON](https://developer.apple.com/tutorials/data/documentation/swiftui/nsviewrepresentable.json)

_Protocol_

Availability: macOS 10.15

A wrapper that you use to integrate an AppKit view into your SwiftUI view hierarchy.

Declaration:
```swift
@MainActor @preconcurrency protocol NSViewRepresentable : View where Self.Body == Never
```


## Overview

Use an NSViewRepresentable instance to create and manage an NSView object in your SwiftUI interface. Adopt this protocol in one of your app’s custom instances, and use its methods to create, update, and tear down your view. The creation and update processes parallel the behavior of SwiftUI views, and you use them to configure your view with your app’s current state information. Use the teardown process to remove your view cleanly from your SwiftUI. For example, you might use the teardown process to notify other objects that the view is disappearing.

To add your view into your SwiftUI interface, create your NSViewRepresentable instance and add it to your SwiftUI interface. The system calls the methods of your representable instance at appropriate times to create and update the view. The following example shows the inclusion of a custom MyRepresentedCustomView struct in the view hierarchy.

```swift
struct ContentView: View {
   var body: some View {
      VStack {
         Text("Global Sales")
         MyRepresentedCustomView()
      }
   }
}
```

The system doesn’t automatically communicate changes occurring within your view controller to other parts of your SwiftUI interface. When you want your view controller to coordinate with other SwiftUI views, you must provide a Coordinator object to facilitate those interactions. For example, you use a coordinator to forward target-action and delegate messages from your view controller to any SwiftUI views.

> **Warning:** SwiftUI fully controls the layout of the AppKit view using the view’s frame and bounds properties. Don’t directly set these layout-related properties on the view managed by an NSViewRepresentable instance from your own code because that conflicts with SwiftUI and results in undefined behavior.

Topics:
**Creating and updating the view**: makeNSView(context:), updateNSView(_:context:), NSViewRepresentable.Context, NSViewType
**Specifying a size**: sizeThatFits(_:nsView:context:)
**Cleaning up the view**: dismantleNSView(_:coordinator:)
**Providing a custom coordinator object**: makeCoordinator(), Coordinator
**Performing layout**: NSViewRepresentable.LayoutOptions

---

## NSViewControllerRepresentable

[Apple docs](https://developer.apple.com/documentation/swiftui/nsviewcontrollerrepresentable) · [DocC JSON](https://developer.apple.com/tutorials/data/documentation/swiftui/nsviewcontrollerrepresentable.json)

_Protocol_

Availability: macOS 10.15

A wrapper that you use to integrate an AppKit view controller into your SwiftUI interface.

Declaration:
```swift
@MainActor @preconcurrency protocol NSViewControllerRepresentable : View where Self.Body == Never
```


## Overview

Use an NSViewControllerRepresentable instance to create and manage an NSViewController object in your SwiftUI interface. Adopt this protocol in one of your app’s custom instances, and use its methods to create, update, and tear down your view controller. The creation and update processes parallel the behavior of SwiftUI views, and you use them to configure your view controller with your app’s current state information. Use the teardown process to remove your view controller cleanly from your SwiftUI. For example, you might use the teardown process to notify other objects that the view controller is disappearing.

To add your view controller into your SwiftUI interface, create your NSViewControllerRepresentable instance and add it to your SwiftUI interface. The system calls the methods of your custom instance at appropriate times.

The system doesn’t automatically communicate changes occurring within your view controller to other parts of your SwiftUI interface. When you want your view controller to coordinate with other SwiftUI views, you must provide a Coordinator instance to facilitate those interactions. For example, you use a coordinator to forward target-action and delegate messages from your view controller to any SwiftUI views.

> **Warning:** SwiftUI fully controls the layout of the AppKit view controller’s view using the view’s frame and bounds properties. Don’t directly set these layout-related properties on the view managed by an NSViewControllerRepresentable instance from your own code because that conflicts with SwiftUI and results in undefined behavior.

Topics:
**Creating and updating the view controller**: makeNSViewController(context:), updateNSViewController(_:context:), NSViewControllerRepresentable.Context, NSViewControllerType
**Specifying a size**: sizeThatFits(_:nsViewController:context:)
**Cleaning up the view controller**: dismantleNSViewController(_:coordinator:)
**Providing a custom coordinator object**: makeCoordinator(), Coordinator
**Performing layout**: NSViewControllerRepresentable.LayoutOptions

---

## NSViewRepresentableContext

[Apple docs](https://developer.apple.com/documentation/swiftui/nsviewrepresentablecontext) · [DocC JSON](https://developer.apple.com/tutorials/data/documentation/swiftui/nsviewrepresentablecontext.json)

_Structure_

Availability: macOS 10.15

Contextual information about the state of the system that you use to create and update your AppKit view.

Declaration:
```swift
@MainActor @preconcurrency struct NSViewRepresentableContext<View> where View : NSViewRepresentable
```


## Overview

An NSViewRepresentableContext structure contains details about the current state of the system. When creating and updating your view, the system creates one of these structures and passes it to the appropriate method of your custom NSViewRepresentable instance. Use the information in this structure to configure your view. For example, use the provided environment values to configure the appearance of your view. Don’t create this structure yourself.

Topics:
**Coordinating view-related interactions**: coordinator, transaction
**Getting the current environment data**: environment
**Instance Methods**: animate(changes:completion:)

---

## NSHostingController

[Apple docs](https://developer.apple.com/documentation/swiftui/nshostingcontroller) · [DocC JSON](https://developer.apple.com/tutorials/data/documentation/swiftui/nshostingcontroller.json)

_Class_

Availability: macOS 10.15

An AppKit view controller that hosts SwiftUI view hierarchy.

Declaration:
```swift
@MainActor @preconcurrency class NSHostingController<Content> where Content : View
```


## Overview

Create an NSHostingController object when you want to integrate SwiftUI views into an AppKit view hierarchy. At creation time, specify the SwiftUI view you want to use as the root view for this view controller; you can change that view later using the rootView property. Use the hosting controller like you would any other view controller, by presenting it or embedding it as a child view controller in your interface.

Topics:
**Creating a hosting controller object**: init(rootView:), init(coder:rootView:), init(coder:)
**Getting the root view**: rootView, identifier
**Configuring the controller**: sizeThatFits(in:), preferredContentSize, sizingOptions, safeAreaRegions, sceneBridgingOptions

---

## NSHostingView

[Apple docs](https://developer.apple.com/documentation/swiftui/nshostingview) · [DocC JSON](https://developer.apple.com/tutorials/data/documentation/swiftui/nshostingview.json)

_Class_

Availability: macOS 10.15

An AppKit view that hosts a SwiftUI view hierarchy.

Declaration:
```swift
@MainActor @preconcurrency class NSHostingView<Content> where Content : View
```


## Overview

You use NSHostingView objects to integrate SwiftUI views into your AppKit view hierarchies. A hosting view is an NSView object that manages a single SwiftUI view, which may itself contain other SwiftUI views. Because it is an NSView object, you can integrate it into your existing AppKit view hierarchies to implement portions of your UI. For example, you can use a hosting view to implement a custom control.

A hosting view acts as a bridge between your SwiftUI views and your AppKit interface. During layout, the hosting view reports the content size preferences of your SwiftUI views back to the AppKit layout system so that it can size the view appropriately. The hosting view also coordinates event delivery.

Topics:
**Creating a hosting view**: init(rootView:), init(coder:), prepareForReuse()
**Getting the root view**: rootView
**Configuring the view layout behavior**: requiresConstraintBasedLayout, userInterfaceLayoutDirection, isFlipped, layerContentsRedrawPolicy, updateConstraints(), layout(), safeAreaRegions
**Managing keyboard interaction**: keyDown(with:), keyUp(with:), performKeyEquivalent(with:), insertText(_:), didChangeValue(forKey:), makeTouchBar()
**Responding to mouse events**: mouseDown(with:), mouseUp(with:), otherMouseDown(with:), otherMouseUp(with:), rightMouseDown(with:), rightMouseUp(with:), mouseEntered(with:), mouseExited(with:), mouseDragged(with:), mouseMoved(with:), otherMouseDragged(with:), rightMouseDragged(with:), cursorUpdate(with:)
**Responding to touch events**: touchesBegan(with:), touchesCancelled(with:), touchesEnded(with:), touchesMoved(with:)
**Responding to gestures**: magnify(with:), rotate(with:), scrollWheel(with:)
**Handling drag and drop**: validRequestor(forSendType:returnType:)
**Providing a context menu**: menu(for:)
**Responding to actions**: responds(to:), forwardingTarget(for:), doCommand(by:)
**Configuring the responder behavior**: acceptsFirstResponder, needsPanelToBecomeKey
**Managing the view hierarchy**: viewWillMove(toWindow:), viewDidMoveToWindow(), viewDidChangeBackingProperties(), viewDidChangeEffectiveAppearance()
**Modifying the frame rectangle**: intrinsicContentSize, setFrameSize(_:), firstBaselineOffsetFromTop, lastBaselineOffsetFromBottom, sizingOptions, firstTextLineCenter
**Testing for hits**: hitTest(_:)
**Managing accessibility behaviors**: accessibilityFocusedUIElement, accessibilityChildren(), accessibilityChildrenInNavigationOrder(), accessibilityHitTest(_:), accessibilityRole(), accessibilitySubrole(), isAccessibilityElement()
**Bridging with SwiftUI**: sceneBridgingOptions
**Initializers**: init(coder:rootView:)
**Instance Properties**: clipsToBounds
**Instance Methods**: acceptsFirstMouse(for:), beginDocument(), didAddSubview(_:), endDocument(), observeValue(forKeyPath:of:change:context:), shouldDelayWindowOrdering(for:), viewDidEndLiveResize(), viewWillStartLiveResize(), willRemoveSubview(_:)

---

## NSHostingSizingOptions

[Apple docs](https://developer.apple.com/documentation/swiftui/nshostingsizingoptions) · [DocC JSON](https://developer.apple.com/tutorials/data/documentation/swiftui/nshostingsizingoptions.json)

_Structure_

Availability: macOS 13.0

Options for how hosting views and controllers reflect their content’s size into Auto Layout constraints.

Declaration:
```swift
struct NSHostingSizingOptions
```

Topics:
**Geting sizing options**: intrinsicContentSize, maxSize, minSize, preferredContentSize, standardBounds
**Creating a sizing option**: init(rawValue:), rawValue

---
