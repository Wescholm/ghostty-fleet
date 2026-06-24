# Styling Protocols

The SwiftUI 'style protocol' pattern (makeBody + Configuration) used to make controls themeable — the same shape you follow for custom styles.

> Fetch tip: the human doc pages are a JS app (empty when fetched). For live detail, fetch the **DocC JSON** endpoint (`.../tutorials/data/documentation/swiftui/<symbol>.json`), not the HTML.

## Contents

- [ButtonStyle](#buttonstyle)
- [PrimitiveButtonStyle](#primitivebuttonstyle)
- [ToggleStyle](#togglestyle)
- [LabelStyle](#labelstyle)
- [PickerStyle](#pickerstyle)
- [MenuStyle](#menustyle)
- [GroupBoxStyle](#groupboxstyle)
- [ProgressViewStyle](#progressviewstyle)
- [GaugeStyle](#gaugestyle)
- [TextFieldStyle](#textfieldstyle)
- [ControlSize](#controlsize)

---

## ButtonStyle

[Apple docs](https://developer.apple.com/documentation/swiftui/buttonstyle) · [DocC JSON](https://developer.apple.com/tutorials/data/documentation/swiftui/buttonstyle.json)

_Protocol_

Availability: macOS 10.15

A type that applies standard interaction behavior and a custom appearance to all buttons within a view hierarchy.

Declaration:
```swift
@MainActor @preconcurrency protocol ButtonStyle
```


## Overview

To configure the current button style for a view hierarchy, use the buttonStyle(_:) modifier. Specify a style that conforms to ButtonStyle when creating a button that uses the standard button interaction behavior defined for each platform. To create a button with custom interaction behavior, use PrimitiveButtonStyle instead.

Topics:
**Custom button styles**: makeBody(configuration:), ButtonStyle.Configuration, Body

---

## PrimitiveButtonStyle

[Apple docs](https://developer.apple.com/documentation/swiftui/primitivebuttonstyle) · [DocC JSON](https://developer.apple.com/tutorials/data/documentation/swiftui/primitivebuttonstyle.json)

_Protocol_

Availability: macOS 10.15

A type that applies custom interaction behavior and a custom appearance to all buttons within a view hierarchy.

Declaration:
```swift
@MainActor @preconcurrency protocol PrimitiveButtonStyle
```


## Overview

To configure the current button style for a view hierarchy, use the buttonStyle(_:) modifier. Specify a style that conforms to PrimitiveButtonStyle to create a button with custom interaction behavior. To create a button with the standard button interaction behavior defined for each platform, use ButtonStyle instead.

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
**Getting built-in button styles**: automatic, accessoryBar, accessoryBarAction, bordered, borderedProminent, borderless, card, glass, glassProminent, glass(_:), link, plain
**Creating custom button styles**: makeBody(configuration:), PrimitiveButtonStyle.Configuration, Body
**Supporting types**: DefaultButtonStyle, AccessoryBarButtonStyle, AccessoryBarActionButtonStyle, BorderedButtonStyle, BorderedProminentButtonStyle, BorderlessButtonStyle, CardButtonStyle, LinkButtonStyle, PlainButtonStyle

---

## ToggleStyle

[Apple docs](https://developer.apple.com/documentation/swiftui/togglestyle) · [DocC JSON](https://developer.apple.com/tutorials/data/documentation/swiftui/togglestyle.json)

_Protocol_

Availability: macOS 10.15

The appearance and behavior of a toggle.

Declaration:
```swift
@MainActor @preconcurrency protocol ToggleStyle
```


## Overview

To configure the style for a single Toggle or for all toggle instances in a view hierarchy, use the toggleStyle(_:) modifier. You can specify one of the built-in toggle styles, like switch or button:

```swift
Toggle(isOn: $isFlagged) {
    Label("Flag", systemImage: "flag.fill")
}
.toggleStyle(.button)
```

Alternatively, you can create and apply a custom style.


### Custom styles

To create a custom style, declare a type that conforms to the ToggleStyle protocol and implement the required makeBody(configuration:) method. For example, you can define a checklist toggle style:

```swift
struct ChecklistToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        // Return a view that has checklist appearance and behavior.
    }
}
```

Inside the method, use the configuration parameter, which is an instance of the ToggleStyleConfiguration structure, to get the label and a binding to the toggle state. To see examples of how to use these items to construct a view that has the appearance and behavior of a toggle, see makeBody(configuration:).

To provide easy access to the new style, declare a corresponding static variable in an extension to ToggleStyle:

```swift
extension ToggleStyle where Self == ChecklistToggleStyle {
    static var checklist: ChecklistToggleStyle { .init() }
}
```

You can then use your custom style:

```swift
Toggle(activity.name, isOn: $activity.isComplete)
    .toggleStyle(.checklist)
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
**Getting built-in toggle styles**: automatic, button, checkbox, switch
**Creating custom toggle styles**: makeBody(configuration:), ToggleStyleConfiguration, ToggleStyle.Configuration, Body
**Supporting types**: DefaultToggleStyle, ButtonToggleStyle, CheckboxToggleStyle, SwitchToggleStyle

---

## LabelStyle

[Apple docs](https://developer.apple.com/documentation/swiftui/labelstyle) · [DocC JSON](https://developer.apple.com/tutorials/data/documentation/swiftui/labelstyle.json)

_Protocol_

Availability: macOS 11.0

A type that applies a custom appearance to all labels within a view.

Declaration:
```swift
@MainActor @preconcurrency protocol LabelStyle
```


## Overview

To configure the current label style for a view hierarchy, use the labelStyle(_:) modifier.

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
**Getting built-in label styles**: automatic, iconOnly, titleAndIcon, titleOnly
**Creating custom label styles**: makeBody(configuration:), LabelStyle.Configuration, Body
**Supporting types**: DefaultLabelStyle, IconOnlyLabelStyle, TitleAndIconLabelStyle, TitleOnlyLabelStyle

---

## PickerStyle

[Apple docs](https://developer.apple.com/documentation/swiftui/pickerstyle) · [DocC JSON](https://developer.apple.com/tutorials/data/documentation/swiftui/pickerstyle.json)

_Protocol_

Availability: macOS 10.15

A type that specifies the appearance and interaction of all pickers within a view hierarchy.

Declaration:
```swift
protocol PickerStyle
```

Topics:
**Getting built-in picker styles**: automatic, inline, menu, navigationLink, palette, radioGroup, segmented, tabs, wheel
**Supporting types**: DefaultPickerStyle, InlinePickerStyle, MenuPickerStyle, NavigationLinkPickerStyle, PalettePickerStyle, RadioGroupPickerStyle, SegmentedPickerStyle, TabsPickerStyle, WheelPickerStyle
**Deprecated styles**: PopUpButtonPickerStyle

---

## MenuStyle

[Apple docs](https://developer.apple.com/documentation/swiftui/menustyle) · [DocC JSON](https://developer.apple.com/tutorials/data/documentation/swiftui/menustyle.json)

_Protocol_

Availability: macOS 11.0

A type that applies standard interaction behavior and a custom appearance to all menus within a view hierarchy.

Declaration:
```swift
@MainActor @preconcurrency protocol MenuStyle
```


## Overview

To configure the current menu style for a view hierarchy, use the menuStyle(_:) modifier.

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
**Getting built-in menu styles**: automatic, button, borderedButton, borderlessButton
**Creating custom menu styles**: makeBody(configuration:), MenuStyle.Configuration, Body
**Supporting types**: DefaultMenuStyle, ButtonMenuStyle, BorderlessButtonMenuStyle, BorderedButtonMenuStyle

---

## GroupBoxStyle

[Apple docs](https://developer.apple.com/documentation/swiftui/groupboxstyle) · [DocC JSON](https://developer.apple.com/tutorials/data/documentation/swiftui/groupboxstyle.json)

_Protocol_

Availability: macOS 11.0

A type that specifies the appearance and interaction of all group boxes within a view hierarchy.

Declaration:
```swift
@MainActor @preconcurrency protocol GroupBoxStyle
```


## Overview

To configure the current GroupBoxStyle for a view hierarchy, use the groupBoxStyle(_:) modifier.

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
**Getting built-in group box styles**: automatic
**Creating custom group box styles**: makeBody(configuration:), GroupBoxStyle.Configuration, Body
**Supporting types**: DefaultGroupBoxStyle

---

## ProgressViewStyle

[Apple docs](https://developer.apple.com/documentation/swiftui/progressviewstyle) · [DocC JSON](https://developer.apple.com/tutorials/data/documentation/swiftui/progressviewstyle.json)

_Protocol_

Availability: macOS 11.0

A type that applies standard interaction behavior to all progress views within a view hierarchy.

Declaration:
```swift
@MainActor @preconcurrency protocol ProgressViewStyle
```


## Overview

To configure the current progress view style for a view hierarchy, use the progressViewStyle(_:) modifier.

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
**Getting built-in progress view styles**: automatic, circular, linear
**Creating custom progress view styles**: makeBody(configuration:), ProgressViewStyle.Configuration, Body
**Supporting types**: DefaultProgressViewStyle, CircularProgressViewStyle, LinearProgressViewStyle

---

## GaugeStyle

[Apple docs](https://developer.apple.com/documentation/swiftui/gaugestyle) · [DocC JSON](https://developer.apple.com/tutorials/data/documentation/swiftui/gaugestyle.json)

_Protocol_

Availability: macOS 13.0

Defines the implementation of all gauge instances within a view hierarchy.

Declaration:
```swift
@MainActor @preconcurrency protocol GaugeStyle
```


## Overview

To configure the style for all the Gauge instances in a view hierarchy, use the gaugeStyle(_:) modifier. For example, you can configure a gauge to use the circular style:

```swift
Gauge(value: batteryLevel, in: 0...100) {
    Text("Battery Level")
}
.gaugeStyle(.circular)
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
**Getting the automatic style**: automatic
**Getting circular gauge styles**: circular, accessoryCircular, accessoryCircularCapacity
**Getting linear gauge styles**: linear, linearCapacity, accessoryLinear, accessoryLinearCapacity
**Creating custom gauge styles**: makeBody(configuration:), GaugeStyle.Configuration, Body
**Supporting types**: DefaultGaugeStyle, CircularGaugeStyle, AccessoryCircularGaugeStyle, AccessoryCircularCapacityGaugeStyle, LinearGaugeStyle, LinearCapacityGaugeStyle, AccessoryLinearGaugeStyle, AccessoryLinearCapacityGaugeStyle

---

## TextFieldStyle

[Apple docs](https://developer.apple.com/documentation/swiftui/textfieldstyle) · [DocC JSON](https://developer.apple.com/tutorials/data/documentation/swiftui/textfieldstyle.json)

_Protocol_

Availability: macOS 10.15

A specification for the appearance and interaction of a text field.

Declaration:
```swift
protocol TextFieldStyle
```

Topics:
**Getting built-in text field styles**: automatic, plain, roundedBorder, squareBorder
**Supporting types**: DefaultTextFieldStyle, PlainTextFieldStyle, RoundedBorderTextFieldStyle, SquareBorderTextFieldStyle

---

## ControlSize

[Apple docs](https://developer.apple.com/documentation/swiftui/controlsize) · [DocC JSON](https://developer.apple.com/tutorials/data/documentation/swiftui/controlsize.json)

_Enumeration_

Availability: macOS 10.15

The size classes, like regular or small, that you can apply to controls within a view.

Declaration:
```swift
enum ControlSize
```

Topics:
**Getting control sizes**: ControlSize.mini, ControlSize.small, ControlSize.regular, ControlSize.large, ControlSize.extraLarge
**Initializers**: init(_:)

---
