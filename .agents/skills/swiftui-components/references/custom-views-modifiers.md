# Custom Views & View Modifiers

Build reusable views and modifiers: the View protocol, @ViewBuilder result builders, custom ViewModifier types, and view-composition primitives.

> Fetch tip: the human doc pages are a JS app (empty when fetched). For live detail, fetch the **DocC JSON** endpoint (`.../tutorials/data/documentation/swiftui/<symbol>.json`), not the HTML.

## Contents

- [View](#view)
- [ViewBuilder](#viewbuilder)
- [ViewModifier](#viewmodifier)
- [ModifiedContent](#modifiedcontent)
- [Group](#group)
- [AnyView](#anyview)
- [EmptyView](#emptyview)
- [TupleView](#tupleview)
- [EquatableView](#equatableview)
- [ViewThatFits](#viewthatfits)

---

## View

[Apple docs](https://developer.apple.com/documentation/swiftui/view) · [DocC JSON](https://developer.apple.com/tutorials/data/documentation/swiftui/view.json)

_Protocol_

Availability: macOS 10.15

A type that represents part of your app’s user interface and provides modifiers that you use to configure views.

Declaration:
```swift
@MainActor @preconcurrency protocol View
```


## Overview

You create custom views by declaring types that conform to the View protocol. Implement the required body computed property to provide the content for your custom view.

```swift
struct MyView: View {
    var body: some View {
        Text("Hello, World!")
    }
}
```

Assemble the view’s body by combining one or more of the built-in views provided by SwiftUI, like the Text instance in the example above, plus other custom views that you define, into a hierarchy of views. For more information about creating custom views, see Declaring a custom view.

The View protocol provides a set of modifiers — protocol methods with default implementations — that you use to configure views in the layout of your app. Modifiers work by wrapping the view instance on which you call them in another view with the specified characteristics, as described in Configuring views. For example, adding the opacity(_:) modifier to a text view returns a new view with some amount of transparency:

```swift
Text("Hello, World!")
    .opacity(0.5) // Display partially transparent text.
```

The complete list of default modifiers provides a large set of controls for managing views. For example, you can fine tune Layout modifiers, add Accessibility modifiers information, and respond to Input and event modifiers. You can also collect groups of default modifiers into new, custom view modifiers for easy reuse.

A type conforming to this protocol inherits @preconcurrency @MainActor isolation from the protocol if the conformance is declared in its original declaration. Isolation to the main actor is the default, but it’s not required. Declare the conformance in an extension to opt-out the isolation.

Topics:
**Implementing a custom view**: body, Body, modifier(_:), Previews in Xcode
**Configuring view elements**: Accessibility modifiers, Appearance modifiers, Text and symbol modifiers, Auxiliary view modifiers, Chart view modifiers
**Drawing views**: Style modifiers, Layout modifiers, Graphics and rendering modifiers
**Providing interactivity**: Input and event modifiers, Search modifiers, Presentation modifiers, State modifiers
**Modifying technology-specific views**: Technology-specific modifiers
**Deprecated modifiers**: Deprecated modifiers

---

## ViewBuilder

[Apple docs](https://developer.apple.com/documentation/swiftui/viewbuilder) · [DocC JSON](https://developer.apple.com/tutorials/data/documentation/swiftui/viewbuilder.json)

_Structure_

Availability: macOS 10.15

A custom parameter attribute that constructs views from closures.

Declaration:
```swift
@resultBuilder struct ViewBuilder
```


## Overview

When you build your project in Xcode 26 and earlier, use ViewBuilder as a parameter attribute for view-producing closure parameters, allowing those closures to provide multiple child views. For example, the following contextMenu function accepts a closure that produces one or more views via the view builder.

```swift
func contextMenu<MenuItems: View>(
    @ViewBuilder menuItems: () -> MenuItems
) -> some View
```

Clients of this function can use multiple-statement closures to provide several child views, as the following example shows:

```swift
myView.contextMenu {
    Text("Cut")
    Text("Copy")
    Text("Paste")
    if isSymbol {
        Text("Jump to Definition")
    }
}
```

When you build in Xcode 27 and later for any version of SwiftUI, the system constructs type-agnostic content from ViewBuilder closures, and doesn’t restrict the types you use in closures to conform to View. Mark closures with the type alias ContentBuilder instead to indicate where your code expects this behavior. For more information, see ContentBuilder.

Topics:
**Building content**: buildBlock(), buildBlock(_:)
**Conditionally building content**: buildEither(first:), buildEither(second:), buildIf(_:), buildLimitedAvailability(_:)

---

## ViewModifier

[Apple docs](https://developer.apple.com/documentation/swiftui/viewmodifier) · [DocC JSON](https://developer.apple.com/tutorials/data/documentation/swiftui/viewmodifier.json)

_Protocol_

Availability: macOS 10.15

A modifier that you apply to a view or another view modifier, producing a different version of the original value.

Declaration:
```swift
@MainActor @preconcurrency protocol ViewModifier
```


## Overview

Adopt the ViewModifier protocol when you want to create a reusable modifier that you can apply to any view. The example below combines several modifiers to create a new modifier that you can use to create blue caption text surrounded by a rounded rectangle:

```swift
struct BorderedCaption: ViewModifier {
    func body(content: Content) -> some View {
        content
            .font(.caption2)
            .padding(10)
            .overlay(
                RoundedRectangle(cornerRadius: 15)
                    .stroke(lineWidth: 1)
            )
            .foregroundColor(Color.blue)
    }
}
```

You can apply modifier(_:) directly to a view, but a more common and idiomatic approach uses modifier(_:) to define an extension to View itself that incorporates the view modifier:

```swift
extension View {
    func borderedCaption() -> some View {
        modifier(BorderedCaption())
    }
}
```

You can then apply the bordered caption to any view, similar to this:

```swift
Image(systemName: "bus")
    .resizable()
    .frame(width:50, height:50)
Text("Downtown Bus")
    .borderedCaption()
```

A type conforming to this protocol inherits @preconcurrency @MainActor isolation from the protocol if the conformance is included in the type’s base declaration:

```swift
struct MyCustomType: Transition {
    // `@preconcurrency @MainActor` isolation by default
}
```

Isolation to the main actor is the default, but it’s not required. Declare the conformance in an extension to opt out of main actor isolation:

```swift
extension MyCustomType: Transition {
    // `nonisolated` by default
}
```

Topics:
**Creating a view modifier**: body(content:), Body, ViewModifier.Content
**Adding animations to a view**: animation(_:), concat(_:)
**Handling view taps and gestures**: transaction(_:)

---

## ModifiedContent

[Apple docs](https://developer.apple.com/documentation/swiftui/modifiedcontent) · [DocC JSON](https://developer.apple.com/tutorials/data/documentation/swiftui/modifiedcontent.json)

_Structure_

Availability: macOS 10.15

A value with a modifier applied to it.

Declaration:
```swift
@frozen struct ModifiedContent<Content, Modifier>
```

Topics:
**Creating a modified content view**: init(content:modifier:), content, modifier
**Instance Methods**: accessibility(activationPoint:), accessibility(addTraits:), accessibility(hidden:), accessibility(hint:), accessibility(identifier:), accessibility(inputLabels:), accessibility(label:), accessibility(removeTraits:), accessibility(selectionIdentifier:), accessibility(sortPriority:), accessibility(value:), accessibilityAction(_:_:), accessibilityAction(_:intent:), accessibilityAction(named:_:), accessibilityAction(named:intent:), accessibilityActivationPoint(_:), accessibilityActivationPoint(_:isEnabled:), accessibilityAddTraits(_:), accessibilityAdjustableAction(_:), accessibilityCustomContent(_:_:importance:), accessibilityDirectTouch(_:options:), accessibilityDragPoint(_:description:), accessibilityDragPoint(_:description:isEnabled:), accessibilityDropPoint(_:description:), accessibilityDropPoint(_:description:isEnabled:), accessibilityHeading(_:), accessibilityHidden(_:), accessibilityHidden(_:isEnabled:), accessibilityHint(_:), accessibilityHint(_:isEnabled:), accessibilityIdentifier(_:), accessibilityIdentifier(_:isEnabled:), accessibilityInputLabels(_:), accessibilityInputLabels(_:isEnabled:), accessibilityLabel(_:), accessibilityLabel(_:isEnabled:), accessibilityRemoveTraits(_:), accessibilityRespondsToUserInteraction(_:), accessibilityRespondsToUserInteraction(_:isEnabled:), accessibilityScrollAction(_:), accessibilityScrollStatus(_:isEnabled:), accessibilitySortPriority(_:), accessibilityTextContentType(_:), accessibilityValue(_:), accessibilityValue(_:isEnabled:), accessibilityZoomAction(_:)

---

## Group

[Apple docs](https://developer.apple.com/documentation/swiftui/group) · [DocC JSON](https://developer.apple.com/tutorials/data/documentation/swiftui/group.json)

_Structure_

Availability: macOS 10.15

A type that collects multiple instances of a content type — like views, scenes, or commands — into a single unit.

Declaration:
```swift
@frozen struct Group<Content>
```


## Overview

Use a group to collect multiple views into a single instance, without affecting the layout of those views, like an HStack, VStack, or Section would. After creating a group, any modifier you apply to the group affects all of that group’s members. For example, the following code applies the headline font to three views in a group.

```swift
Group {
    Text("SwiftUI")
    Text("Combine")
    Text("Swift System")
}
.font(.headline)
```

Because you create a group of views with a ContentBuilder, you can use the group’s initializer to produce different kinds of views from a conditional, and then optionally apply modifiers to them. The following example uses a Group to add a navigation bar title, regardless of the type of view the conditional produces:

```swift
Group {
    if isLoggedIn {
        WelcomeView()
    } else {
        LoginView()
    }
}
.navigationBarTitle("Start")
```

The modifier applies to all members of the group — and not to the group itself. For example, if you apply onAppear(perform:) to the above group, it applies to all of the views produced by the if isLoggedIn conditional, and it executes every time isLoggedIn changes.

Because a group of views itself is a view, you can compose a group within other content builders, including nesting within other groups. This allows you to add large numbers of views to different content builder containers. The following example uses a Group to collect 10 Text instances, meaning that the vertical stack’s content builder returns only two views — the group, plus an additional Text:

```swift
var body: some View {
    VStack {
        Group {
            Text("1")
            Text("2")
            Text("3")
            Text("4")
            Text("5")
            Text("6")
            Text("7")
            Text("8")
            Text("9")
            Text("10")
        }
        Text("11")
    }
}
```

You can initialize groups with several types other than View, such as Scene and ToolbarContent. The closure you provide to the group initializer uses the corresponding builder type (SceneBuilder, ToolbarContentBuilder, and so on), and the capabilities of these builders vary between types. For example, you can use groups to return large numbers of scenes or toolbar content instances, but not to return different scenes or toolbar content based on conditionals.

Topics:
**Creating a group**: init(content:), init(sections:transform:), init(subviews:transform:)

---

## AnyView

[Apple docs](https://developer.apple.com/documentation/swiftui/anyview) · [DocC JSON](https://developer.apple.com/tutorials/data/documentation/swiftui/anyview.json)

_Structure_

Availability: macOS 10.15

A type-erased view.

Declaration:
```swift
@frozen nonisolated struct AnyView
```


## Overview

An AnyView allows changing the type of view used in a given view hierarchy. Whenever the type of view used with an AnyView changes, the old hierarchy is destroyed and a new hierarchy is created for the new type.

Topics:
**Creating a view**: init(_:), init(erasing:)

---

## EmptyView

[Apple docs](https://developer.apple.com/documentation/swiftui/emptyview) · [DocC JSON](https://developer.apple.com/tutorials/data/documentation/swiftui/emptyview.json)

_Structure_

Availability: macOS 10.15

A view that doesn’t contain any content.

Declaration:
```swift
@frozen nonisolated struct EmptyView
```


## Overview

You will rarely, if ever, need to create an EmptyView directly. Instead, EmptyView represents the absence of a view.

SwiftUI uses EmptyView in situations where a SwiftUI view type defines one or more child views with generic parameters, and allows the child views to be absent. When absent, the child view’s type in the generic type parameter is EmptyView.

The following example creates an indeterminate ProgressView without a label. The ProgressView type declares two generic parameters, Label and CurrentValueLabel, for the types used by its subviews. When both subviews are absent, like they are here, the resulting type is ProgressView<EmptyView, EmptyView>, as indicated by the example’s output:

```swift
let progressView = ProgressView()
print("\(type(of:progressView))")
// Prints: ProgressView<EmptyView, EmptyView>
```

Topics:
**Creating an empty view**: init()

---

## TupleView

[Apple docs](https://developer.apple.com/documentation/swiftui/tupleview) · [DocC JSON](https://developer.apple.com/tutorials/data/documentation/swiftui/tupleview.json)

_Structure_

Availability: macOS 10.15

A View created from a swift tuple of View values.

Declaration:
```swift
@frozen nonisolated struct TupleView<T>
```

Topics:
**Creating a tuple view**: init(_:), value

---

## EquatableView

[Apple docs](https://developer.apple.com/documentation/swiftui/equatableview) · [DocC JSON](https://developer.apple.com/tutorials/data/documentation/swiftui/equatableview.json)

_Structure_

Availability: macOS 10.15

A view type that compares itself against its previous value and prevents its child updating if its new value is the same as its old value.

Declaration:
```swift
@frozen nonisolated struct EquatableView<Content> where Content : Equatable, Content : View
```

Topics:
**Creating an equatable view**: init(content:), content

---

## ViewThatFits

[Apple docs](https://developer.apple.com/documentation/swiftui/viewthatfits) · [DocC JSON](https://developer.apple.com/tutorials/data/documentation/swiftui/viewthatfits.json)

_Structure_

Availability: macOS 13.0

A view that adapts to the available space by providing the first child view that fits.

Declaration:
```swift
@frozen nonisolated struct ViewThatFits<Content> where Content : View
```


## Overview

ViewThatFits evaluates its child views in the order you provide them to the initializer. It selects the first child whose ideal size on the constrained axes fits within the proposed size. This means that you provide views in order of preference. Usually this order is largest to smallest, but since a view might fit along one constrained axis but not the other, this isn’t always the case. By default, ViewThatFits constrains in both the horizontal and vertical axes.

The following example shows an UploadProgressView that uses ViewThatFits to display the upload progress in one of three ways. In order, it attempts to display:

- An HStack that contains a Text view and a ProgressView.

- Only the ProgressView.

- Only the Text view.

The progress views are fixed to a 100-point width.

```swift
struct UploadProgressView: View {
    var uploadProgress: Double

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack {
                Text("\(uploadProgress.formatted(.percent))")
                ProgressView(value: uploadProgress)
                    .frame(width: 100)
            }
            ProgressView(value: uploadProgress)
                .frame(width: 100)
            Text("\(uploadProgress.formatted(.percent))")
        }
    }
}
```

This use of ViewThatFits evaluates sizes only on the horizontal axis. The following code fits the UploadProgressView to several fixed widths:

```swift
VStack {
    UploadProgressView(uploadProgress: 0.75)
        .frame(maxWidth: 200)
    UploadProgressView(uploadProgress: 0.75)
        .frame(maxWidth: 100)
    UploadProgressView(uploadProgress: 0.75)
        .frame(maxWidth: 50)
}
```

Topics:
**Creating a view that fits**: init(in:content:)

---
