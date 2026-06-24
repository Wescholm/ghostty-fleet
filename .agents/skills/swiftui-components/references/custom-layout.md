# Custom Layout

Implement the Layout protocol, size negotiation, alignment guides, and geometry-driven sizing for custom container components.

> Fetch tip: the human doc pages are a JS app (empty when fetched). For live detail, fetch the **DocC JSON** endpoint (`.../tutorials/data/documentation/swiftui/<symbol>.json`), not the HTML.

## Contents

- [Layout](#layout)
- [LayoutSubview](#layoutsubview)
- [LayoutSubviews](#layoutsubviews)
- [ProposedViewSize](#proposedviewsize)
- [LayoutValueKey](#layoutvaluekey)
- [ViewDimensions](#viewdimensions)
- [GeometryReader](#geometryreader)
- [GeometryProxy](#geometryproxy)
- [Alignment](#alignment)
- [HorizontalAlignment](#horizontalalignment)
- [VerticalAlignment](#verticalalignment)
- [AlignmentID](#alignmentid)
- [Anchor](#anchor)

---

## Layout

[Apple docs](https://developer.apple.com/documentation/swiftui/layout) · [DocC JSON](https://developer.apple.com/tutorials/data/documentation/swiftui/layout.json)

_Protocol_

Availability: macOS 13.0

A type that defines the geometry of a collection of views.

Declaration:
```swift
@preconcurrency protocol Layout : Sendable, Animatable
```


## Overview

You traditionally arrange views in your app’s user interface using built-in layout containers like HStack and Grid. If you need more complex layout behavior, you can define a custom layout container by creating a type that conforms to the Layout protocol and implementing its required methods:

- sizeThatFits(proposal:subviews:cache:) reports the size of the composite layout view.

- placeSubviews(in:proposal:subviews:cache:) assigns positions to the container’s subviews.

You can define a basic layout type with only these two methods:

```swift
struct BasicVStack: Layout {
    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) -> CGSize {
        // Calculate and return the size of the layout container.
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        // Tell each subview where to appear.
    }
}
```

Use your layout the same way you use a built-in layout container, by providing a ContentBuilder with the list of subviews to arrange:

```swift
BasicVStack {
    Text("A Subview")
    Text("Another Subview")
}
```


### Support additional behaviors

You can optionally implement other protocol methods and properties to provide more layout container features:

- Define explicit horizontal and vertical layout guides for the container by implementing explicitAlignment(of:in:proposal:subviews:cache:) for each dimension.

- Establish the preferred spacing around the container by implementing spacing(subviews:cache:).

- Indicate the axis of orientation for a container that has characteristics of a stack by implementing the layoutProperties static property.

- Create and manage a cache to store computed values across different layout protocol calls by implementing makeCache(subviews:).

The protocol provides default implementations for these symbols if you don’t implement them. See each method or property for details.


### Add input parameters

You can define parameters as inputs to the layout, like you might for a View:

```swift
struct BasicVStack: Layout {
    var alignment: HorizontalAlignment

    // ...
}
```

Set the parameters at the point where you instantiate the layout:

```swift
BasicVStack(alignment: .leading) {
    // ...
}
```

If the layout provides default values for its parameters, you can omit the parameters at the call site, but you might need to keep the parentheses after the name of the layout, depending on how you specify the defaults. For example, suppose you set a default alignment for the basic stack in the parameter declaration:

```swift
struct BasicVStack: Layout {
    var alignment: HorizontalAlignment = .center

    // ...
}
```

To instantiate this layout using the default center alignment, you don’t have to specify the alignment value, but you do need to add empty parentheses:

```swift
BasicVStack() {
    // ...
}
```

The Swift compiler requires the parentheses in this case because of how the layout protocol implements this call site syntax. Specifically, the layout’s callAsFunction(_:) method looks for an initializer with exactly zero input arguments when you omit the parentheses from the call site. You can enable the simpler call site for a layout that doesn’t have an implicit initializer of this type by explicitly defining one:

```swift
init() {
    self.alignment = .center
}
```

For information about Swift initializers, see Initialization in The Swift Programming Language.


### Interact with subviews through their proxies

To perform layout, you need information about all of its subviews, which are the views that your container arranges. While your layout can’t interact directly with its subviews, it can access a set of subview proxies through the Layout.Subviews collection that each protocol method receives as an input parameter. That type is an alias for the LayoutSubviews collection type, which in turn contains LayoutSubview instances that are the subview proxies.

You can get information about each subview from its proxy, like its dimensions and spacing preferences. This enables you to measure subviews before you commit to placing them. You also assign a position to each subview by calling its proxy’s place(at:anchor:proposal:) method. Call the method on each subview from within your implementation of the layout’s placeSubviews(in:proposal:subviews:cache:) method.


### Access layout values

Views have layout values that you set with view modifiers. Layout containers can choose to condition their behavior accordingly. For example, a built-in HStack allocates space to its subviews based in part on the priorities that you set with the layoutPriority(_:) view modifier. Your layout container accesses this value for a subview by reading the proxy’s priority property.

You can also create custom layout values by creating a layout key. Set a value on a view with the layoutValue(key:value:) view modifier. Read the corresponding value from the subview’s proxy using the key as an index on the subview. For more information about creating, setting, and accessing custom layout values, see LayoutValueKey.

Topics:
**Sizing the container and placing subviews**: sizeThatFits(proposal:subviews:cache:), placeSubviews(in:proposal:subviews:cache:), Layout.Subviews
**Reporting layout container characteristics**: explicitAlignment(of:in:proposal:subviews:cache:), spacing(subviews:cache:), layoutProperties
**Managing a cache**: makeCache(subviews:), updateCache(_:subviews:), Cache
**Supporting types**: callAsFunction(_:)
**Instance Methods**: depthAlignment(_:), depthAlignment(_:content:)

---

## LayoutSubview

[Apple docs](https://developer.apple.com/documentation/swiftui/layoutsubview) · [DocC JSON](https://developer.apple.com/tutorials/data/documentation/swiftui/layoutsubview.json)

_Structure_

Availability: macOS 13.0

A proxy that represents one subview of a layout.

Declaration:
```swift
struct LayoutSubview
```


## Overview

This type acts as a proxy for a view that your custom layout container places in the user interface. Layout protocol methods receive a LayoutSubviews collection that contains exactly one proxy for each of the subviews arranged by your container.

Use a proxy to get information about the associated subview, like its dimensions, layout priority, or custom layout values. You also use the proxy to tell its corresponding subview where to appear by calling the proxy’s place(at:anchor:proposal:) method. Do this once for each subview from your implementation of the layout’s placeSubviews(in:proposal:subviews:cache:) method.

You can read custom layout values associated with a subview by using the property’s key as an index on the subview. For more information about defining, setting, and reading custom values, see LayoutValueKey.

Topics:
**Placing the subview**: place(at:anchor:proposal:)
**Getting subview characteristics**: dimensions(in:), sizeThatFits(_:), spacing, priority
**Getting custom values**: subscript(_:)
**Instance Properties**: containerValues

---

## LayoutSubviews

[Apple docs](https://developer.apple.com/documentation/swiftui/layoutsubviews) · [DocC JSON](https://developer.apple.com/tutorials/data/documentation/swiftui/layoutsubviews.json)

_Structure_

Availability: macOS 13.0

A collection of proxy values that represent the subviews of a layout view.

Declaration:
```swift
struct LayoutSubviews
```


## Overview

You receive a LayoutSubviews input to your implementations of Layout protocol methods, like placeSubviews(in:proposal:subviews:cache:) and sizeThatFits(proposal:subviews:cache:). The subviews parameter (which the protocol aliases to the Layout.Subviews type) is a collection that contains proxies for the layout’s subviews (of type LayoutSubview). The proxies appear in the collection in the same order that they appear in the ContentBuilder input to the layout container. Use the proxies to perform layout operations.

Access the proxies in the collection as you would the contents of any Swift random-access collection. For example, you can enumerate all of the subviews and their indices to inspect or operate on them:

```swift
for (index, subview) in subviews.enumerated() {
    // ...
}
```

Topics:
**Getting the layout direction**: layoutDirection
**Accessing subviews**: subscript(_:), startIndex, endIndex, LayoutSubviews.Element, LayoutSubviews.Index, LayoutSubviews.SubSequence

---

## ProposedViewSize

[Apple docs](https://developer.apple.com/documentation/swiftui/proposedviewsize) · [DocC JSON](https://developer.apple.com/tutorials/data/documentation/swiftui/proposedviewsize.json)

_Structure_

Availability: macOS 13.0

A proposal for the size of a view.

Declaration:
```swift
@frozen struct ProposedViewSize
```


## Overview

During layout in SwiftUI, views choose their own size, but they do that in response to a size proposal from their parent view. When you create a custom layout using the Layout protocol, your layout container participates in this process using ProposedViewSize instances. The layout protocol’s methods take a proposed size input that you can take into account when arranging views and calculating the size of the composite container. Similarly, your layout proposes a size to each of its own subviews when it measures and places them.

Layout containers typically measure their subviews by proposing several sizes and looking at the responses. The container can use this information to decide how to allocate space among its subviews. A layout might try the following special proposals:

- The zero proposal; the view responds with its minimum size.

- The infinity proposal; the view responds with its maximum size.

- The unspecified proposal; the view responds with its ideal size.

A layout might also try special cases for one dimension at a time. For example, an HStack might measure the flexibility of its subviews’ widths, while using a fixed value for the height.

Topics:
**Getting standard proposals**: zero, infinity, unspecified
**Creating a custom size proposal**: init(_:), init(width:height:)
**Getting the proposal’s dimensions**: height, width
**Modifying a proposal**: replacingUnspecifiedDimensions(by:)

---

## LayoutValueKey

[Apple docs](https://developer.apple.com/documentation/swiftui/layoutvaluekey) · [DocC JSON](https://developer.apple.com/tutorials/data/documentation/swiftui/layoutvaluekey.json)

_Protocol_

Availability: macOS 13.0

A key for accessing a layout value of a layout container’s subviews.

Declaration:
```swift
protocol LayoutValueKey
```


## Overview

If you create a custom layout by defining a type that conforms to the Layout protocol, you can also create custom layout values that you set on individual views, and that your container view can access to guide its layout behavior. Your custom values resemble the built-in layout values that you set with view modifiers like layoutPriority(_:) and zIndex(_:), but have a purpose that you define.

To create a custom layout value, define a type that conforms to the LayoutValueKey protocol and implement the one required property that returns the default value of the property. For example, you can create a property that defines an amount of flexibility for a view, defined as an optional floating point number with a default value of nil:

```swift
private struct Flexibility: LayoutValueKey {
    static let defaultValue: CGFloat? = nil
}
```

The Swift compiler infers this particular key’s associated type as an optional CGFloat from this definition.


### Set a value on a view

Set the value on a view by adding the layoutValue(key:value:) view modifier to the view. To make your custom value easier to work with, you can do this in a convenience modifier in an extension of the View protocol:

```swift
extension View {
    func layoutFlexibility(_ value: CGFloat?) -> some View {
        layoutValue(key: Flexibility.self, value: value)
    }
}
```

Use your modifier to set the value on any views that need a nondefault value:

```swift
BasicVStack {
    Text("One View")
    Text("Another View")
        .layoutFlexibility(3)
}
```

Any view that you don’t explicitly set a value for uses the default value, as with the first Text view, above.


### Retrieve a value during layout

Access a custom layout value using the key as an index on subview’s proxy (an instance of LayoutSubview) and use the value to make decisions about sizing, placement, or other layout operations. For example, you might read the flexibility value in your layout view’s sizeThatFits(_:) method, and adjust your size calculations accordingly:

```swift
extension BasicVStack {
    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout Void
    ) -> CGSize {

        // Map the flexibility property of each subview into an array.
        let flexibilities = subviews.map { subview in
            subview[Flexibility.self]
        }

        // Calculate and return the size of the layout container.
        // ...
    }
}
```

Topics:
**Providing a default value**: defaultValue, Value

---

## ViewDimensions

[Apple docs](https://developer.apple.com/documentation/swiftui/viewdimensions) · [DocC JSON](https://developer.apple.com/tutorials/data/documentation/swiftui/viewdimensions.json)

_Structure_

Availability: macOS 10.15

A view’s size and alignment guides in its own coordinate space.

Declaration:
```swift
struct ViewDimensions
```


## Overview

This structure contains the size and alignment guides of a view. You receive an instance of this structure to use in a variety of layout calculations, like when you:

- Define a default value for a custom alignment guide; see defaultValue(in:).

- Modify an alignment guide on a view; see alignmentGuide(_:computeValue:).

- Ask for the dimensions of a subview of a custom view layout; see dimensions(in:).


### Custom alignment guides

You receive an instance of this structure as the context parameter to the defaultValue(in:) method that you implement to produce the default offset for an alignment guide, or as the first argument to the closure you provide to the alignmentGuide(_:computeValue:) view modifier to override the default calculation for an alignment guide. In both cases you can use the instance, if helpful, to calculate the offset for the guide. For example, you could compute a default offset for a custom VerticalAlignment as a fraction of the view’s height:

```swift
private struct FirstThirdAlignment: AlignmentID {
    static func defaultValue(in context: ViewDimensions) -> CGFloat {
        context.height / 3
    }
}

extension VerticalAlignment {
    static let firstThird = VerticalAlignment(FirstThirdAlignment.self)
}
```

As another example, you could use the view dimensions instance to look up the offset of an existing guide and modify it:

```swift
struct ViewDimensionsOffset: View {
    var body: some View {
        VStack(alignment: .leading) {
            Text("Default")
            Text("Indented")
                .alignmentGuide(.leading) { context in
                    context[.leading] - 10
                }
        }
    }
}
```

The example above indents the second text view because the subtraction moves the second text view’s leading guide in the negative x direction, which is to the left in the view’s coordinate space. As a result, SwiftUI moves the second text view to the right, relative to the first text view, to keep their leading guides aligned:


### Layout direction

The discussion above describes a left-to-right language environment, but you don’t change your guide calculation to operate in a right-to-left environment. SwiftUI moves the view’s origin from the left to the right side of the view and inverts the positive x direction. As a result, the existing calculation produces the same effect, but in the opposite direction.

You can see this if you use the environment(_:_:) modifier to set the layoutDirection property for the view that you defined above:

```swift
ViewDimensionsOffset()
    .environment(\.layoutDirection, .rightToLeft)
```

With no change in your guide, this produces the desired effect — it indents the second text view’s right side, relative to the first text view’s right side. The leading edge is now on the right, and the direction of the offset is reversed:

Topics:
**Getting dimensions**: height, width
**Accessing guide values**: subscript(_:), subscript(explicit:)

---

## GeometryReader

[Apple docs](https://developer.apple.com/documentation/swiftui/geometryreader) · [DocC JSON](https://developer.apple.com/tutorials/data/documentation/swiftui/geometryreader.json)

_Structure_

Availability: macOS 10.15

A container view that defines its content as a function of its own size and coordinate space.

Declaration:
```swift
@frozen nonisolated struct GeometryReader<Content> where Content : View
```


## Overview

This view returns a flexible preferred size to its parent layout.

Topics:
**Creating a geometry reader**: init(content:), content

---

## GeometryProxy

[Apple docs](https://developer.apple.com/documentation/swiftui/geometryproxy) · [DocC JSON](https://developer.apple.com/tutorials/data/documentation/swiftui/geometryproxy.json)

_Structure_

Availability: macOS 10.15

A proxy for access to the size and coordinate space (for anchor resolution) of the container view.

Declaration:
```swift
struct GeometryProxy
```

Topics:
**Accessing geometry characteristics**: bounds(of:), frame(in:), size, safeAreaInsets, subscript(_:), transform(in:)
**Instance Properties**: containerCornerInsets

---

## Alignment

[Apple docs](https://developer.apple.com/documentation/swiftui/alignment) · [DocC JSON](https://developer.apple.com/tutorials/data/documentation/swiftui/alignment.json)

_Structure_

Availability: macOS 10.15

An alignment in both axes.

Declaration:
```swift
@frozen struct Alignment
```


## Overview

An Alignment contains a HorizontalAlignment guide and a VerticalAlignment guide. Specify an alignment to direct the behavior of certain layout containers and modifiers, like when you place views in a ZStack, or layer a view in front of or behind another view using overlay(alignment:content:) or background(alignment:content:), respectively. During layout, SwiftUI brings the specified guides of the affected views together, aligning the views.

SwiftUI provides a set of built-in alignments that represent common combinations of the built-in horizontal and vertical alignment guides. The blue boxes in the following diagram demonstrate the alignment named by each box’s label, relative to the background view:

The following code generates the diagram above, where each blue box appears in an overlay that’s configured with a different alignment:

```swift
struct AlignmentGallery: View {
    var body: some View {
        BackgroundView()
            .overlay(alignment: .topLeading) { box(".topLeading") }
            .overlay(alignment: .top) { box(".top") }
            .overlay(alignment: .topTrailing) { box(".topTrailing") }
            .overlay(alignment: .leading) { box(".leading") }
            .overlay(alignment: .center) { box(".center") }
            .overlay(alignment: .trailing) { box(".trailing") }
            .overlay(alignment: .bottomLeading) { box(".bottomLeading") }
            .overlay(alignment: .bottom) { box(".bottom") }
            .overlay(alignment: .bottomTrailing) { box(".bottomTrailing") }
            .overlay(alignment: .leadingLastTextBaseline) { box(".leadingLastTextBaseline") }
            .overlay(alignment: .trailingFirstTextBaseline) { box(".trailingFirstTextBaseline") }
    }

    private func box(_ name: String) -> some View {
        Text(name)
            .font(.system(.caption, design: .monospaced))
            .padding(2)
            .foregroundColor(.white)
            .background(.blue.opacity(0.8), in: Rectangle())
    }
}

private struct BackgroundView: View {
    var body: some View {
        Grid(horizontalSpacing: 0, verticalSpacing: 0) {
            GridRow {
                Text("Some text in an upper quadrant")
                Color.gray.opacity(0.3)
            }
            GridRow {
                Color.gray.opacity(0.3)
                Text("More text in a lower quadrant")
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .foregroundColor(.secondary)
        .border(.gray)
    }
}
```

To avoid crowding, the alignment diagram shows only two of the available text baseline alignments. The others align as their names imply. Notice that the first text baseline alignment aligns with the top-most line of text in the background view, while the last text baseline aligns with the bottom-most line. For more information about text baseline alignment, see VerticalAlignment.

In a left-to-right language like English, the leading and trailing alignments appear on the left and right edges, respectively. SwiftUI reverses these in right-to-left language environments. For more information, see HorizontalAlignment.


### Custom alignment

You can create custom alignments — which you typically do to make use of custom horizontal or vertical guides — by using the init(horizontal:vertical:) initializer. For example, you can combine a custom vertical guide called firstThird with the built-in horizontal center guide, and use it to configure a ZStack:

```swift
ZStack(alignment: Alignment(horizontal: .center, vertical: .firstThird)) {
    // ...
}
```

For more information about creating custom guides, including the code that creates the custom firstThird alignment in the example above, see AlignmentID.

Topics:
**Getting top guides**: topLeading, top, topTrailing
**Getting middle guides**: leading, center, trailing
**Getting bottom guides**: bottomLeading, bottom, bottomTrailing
**Getting text baseline guides**: leadingFirstTextBaseline, centerFirstTextBaseline, trailingFirstTextBaseline, leadingLastTextBaseline, centerLastTextBaseline, trailingLastTextBaseline
**Creating a custom alignment**: init(horizontal:vertical:), horizontal, vertical

---

## HorizontalAlignment

[Apple docs](https://developer.apple.com/documentation/swiftui/horizontalalignment) · [DocC JSON](https://developer.apple.com/tutorials/data/documentation/swiftui/horizontalalignment.json)

_Structure_

Availability: macOS 10.15

An alignment position along the horizontal axis.

Declaration:
```swift
@frozen struct HorizontalAlignment
```


## Overview

Use horizontal alignment guides to tell SwiftUI how to position views relative to one another horizontally, like when you place views vertically in an VStack. The following example demonstrates common built-in horizontal alignments:

You can generate the example above by creating a series of columns implemented as vertical stacks, where you configure each stack with a different alignment guide:

```swift
private struct HorizontalAlignmentGallery: View {
    var body: some View {
        HStack(spacing: 30) {
            column(alignment: .leading, text: "Leading")
            column(alignment: .center, text: "Center")
            column(alignment: .trailing, text: "Trailing")
        }
        .frame(height: 150)
    }

    private func column(alignment: HorizontalAlignment, text: String) -> some View {
        VStack(alignment: alignment, spacing: 0) {
            Color.red.frame(width: 1)
            Text(text).font(.title).border(.gray)
            Color.red.frame(width: 1)
        }
    }
}
```

During layout, SwiftUI aligns the views inside each stack by bringing together the specified guides of the affected views. SwiftUI calculates the position of a guide for a particular view based on the characteristics of the view. For example, the center guide appears at half the width of the view. You can override the guide calculation for a particular view using the alignmentGuide(_:computeValue:) view modifier.


### Layout direction

When a user configures their device to use a left-to-right language like English, the system places the leading alignment on the left and the trailing alignment on the right, as the example from the previous section demonstrates. However, in a right-to-left language, the system reverses these. You can see this by using the environment(_:_:) view modifier to explicitly override the layoutDirection environment value for the view defined above:

```swift
HorizontalAlignmentGallery()
    .environment(\.layoutDirection, .rightToLeft)
```

This automatic layout adjustment makes it easier to localize your app, but it’s still important to test your app for the different locales that you ship into. For more information about the localization process, see Localization.


### Custom alignment guides

You can create a custom horizontal alignment by creating a type that conforms to the AlignmentID protocol, and then using that type to initialize a new static property on HorizontalAlignment:

```swift
private struct OneQuarterAlignment: AlignmentID {
    static func defaultValue(in context: ViewDimensions) -> CGFloat {
        context.width / 4
    }
}

extension HorizontalAlignment {
    static let oneQuarter = HorizontalAlignment(OneQuarterAlignment.self)
}
```

You implement the defaultValue(in:) method to calculate a default value for the custom alignment guide. The method receives a ViewDimensions instance that you can use to calculate an appropriate value based on characteristics of the view. The example above places the guide at one quarter of the width of the view, as measured from the view’s origin.

You can then use the custom alignment guide like any built-in guide. For example, you can use it as the alignment parameter to a VStack, or you can change it for a specific view using the alignmentGuide(_:computeValue:) view modifier. Custom alignment guides also automatically reverse in a right-to-left environment, just like built-in guides.


### Composite alignment

Combine a VerticalAlignment with a HorizontalAlignment to create a composite Alignment that indicates both vertical and horizontal positioning in one value. For example, you could combine your custom oneQuarter horizontal alignment from the previous section with a built-in center vertical alignment to use in a ZStack:

```swift
struct LayeredVerticalStripes: View {
    var body: some View {
        ZStack(alignment: Alignment(horizontal: .oneQuarter, vertical: .center)) {
            verticalStripes(color: .blue)
                .frame(width: 300, height: 150)
            verticalStripes(color: .green)
                .frame(width: 180, height: 80)
        }
    }

    private func verticalStripes(color: Color) -> some View {
        HStack(spacing: 1) {
            ForEach(0..<4) { _ in color }
        }
    }
}
```

The example above uses widths and heights that generate two mismatched sets of four vertical stripes. The ZStack centers the two sets vertically and aligns them horizontally one quarter of the way from the leading edge of each set. In a left-to-right locale, this aligns the right edges of the left-most stripes of each set:

Topics:
**Getting guides**: leading, center, trailing, listRowSeparatorLeading, listRowSeparatorTrailing
**Creating a custom alignment**: init(_:), combineExplicit(_:)

---

## VerticalAlignment

[Apple docs](https://developer.apple.com/documentation/swiftui/verticalalignment) · [DocC JSON](https://developer.apple.com/tutorials/data/documentation/swiftui/verticalalignment.json)

_Structure_

Availability: macOS 10.15

An alignment position along the vertical axis.

Declaration:
```swift
@frozen struct VerticalAlignment
```


## Overview

Use vertical alignment guides to position views relative to one another vertically, like when you place views side-by-side in an HStack or when you create a row of views in a Grid using GridRow. The following example demonstrates common built-in vertical alignments:

You can generate the example above by creating a series of rows implemented as horizontal stacks, where you configure each stack with a different alignment guide:

```swift
private struct VerticalAlignmentGallery: View {
    var body: some View {
        VStack(spacing: 30) {
            row(alignment: .top, text: "Top")
            row(alignment: .center, text: "Center")
            row(alignment: .bottom, text: "Bottom")
            row(alignment: .firstTextBaseline, text: "First Text Baseline")
            row(alignment: .lastTextBaseline, text: "Last Text Baseline")
        }
    }

    private func row(alignment: VerticalAlignment, text: String) -> some View {
        HStack(alignment: alignment, spacing: 0) {
            Color.red.frame(height: 1)
            Text(text).font(.title).border(.gray)
            Color.red.frame(height: 1)
        }
    }
}
```

During layout, SwiftUI aligns the views inside each stack by bringing together the specified guides of the affected views. SwiftUI calculates the position of a guide for a particular view based on the characteristics of the view. For example, the center guide appears at half the height of the view. You can override the guide calculation for a particular view using the alignmentGuide(_:computeValue:) view modifier.


### Text baseline alignment

Use the firstTextBaseline or lastTextBaseline guide to match the bottom of either the top- or bottom-most line of text that a view contains, respectively. Text baseline alignment excludes the parts of characters that descend below the baseline, like the tail on lower case g and j:

```swift
row(alignment: .firstTextBaseline, text: "fghijkl")
```

If you use a text baseline alignment on a view that contains no text, SwiftUI applies the equivalent of bottom alignment instead. For the row in the example above, SwiftUI matches the bottom of the horizontal lines with the baseline of the text:

Aligning a text view to its baseline rather than to the bottom of its frame produces the best layout effect in many cases, like when creating forms. For example, you can align the baseline of descriptive text in one GridRow cell with the baseline of a text field, or the label of a checkbox, in another cell in the same row.


### Custom alignment guides

You can create a custom vertical alignment guide by first creating a type that conforms to the AlignmentID protocol, and then using that type to initialize a new static property on VerticalAlignment:

```swift
private struct FirstThirdAlignment: AlignmentID {
    static func defaultValue(in context: ViewDimensions) -> CGFloat {
        context.height / 3
    }
}

extension VerticalAlignment {
    static let firstThird = VerticalAlignment(FirstThirdAlignment.self)
}
```

You implement the defaultValue(in:) method to calculate a default value for the custom alignment guide. The method receives a ViewDimensions instance that you can use to calculate a value based on characteristics of the view. The example above places the guide at one-third of the height of the view as measured from the view’s origin.

You can then use the custom alignment guide like any built-in guide. For example, you can use it as the alignment parameter to an HStack, or to alter the guide calculation for a specific view using the alignmentGuide(_:computeValue:) view modifier.


### Composite alignment

Combine a VerticalAlignment with a HorizontalAlignment to create a composite Alignment that indicates both vertical and horizontal positioning in one value. For example, you could combine your custom firstThird vertical alignment from the previous section with a built-in center horizontal alignment to use in a ZStack:

```swift
struct LayeredHorizontalStripes: View {
    var body: some View {
        ZStack(alignment: Alignment(horizontal: .center, vertical: .firstThird)) {
            horizontalStripes(color: .blue)
                .frame(width: 180, height: 90)
            horizontalStripes(color: .green)
                .frame(width: 70, height: 60)
        }
    }

    private func horizontalStripes(color: Color) -> some View {
        VStack(spacing: 1) {
            ForEach(0..<3) { _ in color }
        }
    }
}
```

The example above uses widths and heights that generate two mismatched sets of three vertical stripes. The ZStack centers the two sets horizontally and aligns them vertically one-third from the top of each set. This aligns the bottom edges of the top stripe from each set:

Topics:
**Getting guides**: top, center, bottom, firstTextBaseline, lastTextBaseline
**Creating a custom alignment**: init(_:), combineExplicit(_:)

---

## AlignmentID

[Apple docs](https://developer.apple.com/documentation/swiftui/alignmentid) · [DocC JSON](https://developer.apple.com/tutorials/data/documentation/swiftui/alignmentid.json)

_Protocol_

Availability: macOS 10.15

A type that you use to create custom alignment guides.

Declaration:
```swift
protocol AlignmentID
```


## Overview

Every built-in alignment guide that VerticalAlignment or HorizontalAlignment defines as a static property, like top or leading, has a unique alignment identifier type that produces the default offset for that guide. To create a custom alignment guide, define your own alignment identifier as a type that conforms to the AlignmentID protocol, and implement the required defaultValue(in:) method:

```swift
private struct FirstThirdAlignment: AlignmentID {
    static func defaultValue(in context: ViewDimensions) -> CGFloat {
        context.height / 3
    }
}
```

When implementing the method, calculate the guide’s default offset from the view’s origin. If it’s helpful, you can use information from the ViewDimensions input in the calculation. This parameter provides context about the specific view that’s using the guide. The above example creates an identifier called FirstThirdAlignment and calculates a default value that’s one-third of the height of the aligned view.

Use the identifier’s type to create a static property in an extension of one of the alignment guide types, like VerticalAlignment:

```swift
extension VerticalAlignment {
    static let firstThird = VerticalAlignment(FirstThirdAlignment.self)
}
```

You can apply your custom guide like any of the built-in guides. For example, you can use an HStack to align its views at one-third of their height using the guide defined above:

```swift
struct StripesGroup: View {
    var body: some View {
        HStack(alignment: .firstThird, spacing: 1) {
            HorizontalStripes().frame(height: 60)
            HorizontalStripes().frame(height: 120)
            HorizontalStripes().frame(height: 90)
        }
    }
}

struct HorizontalStripes: View {
    var body: some View {
        VStack(spacing: 1) {
            ForEach(0..<3) { _ in Color.blue }
        }
    }
}
```

Because each set of stripes has three equal, vertically stacked rectangles, they align at the bottom edge of the top rectangle. This corresponds in each case to a third of the overall height, as measured from the origin at the top of each set of stripes:

You can also use the alignmentGuide(_:computeValue:) view modifier to alter the behavior of your custom guide for a view, as you might alter a built-in guide. For example, you can change one of the stacks of stripes from the previous example to align its firstThird guide at two thirds of the height instead:

```swift
struct StripesGroupModified: View {
    var body: some View {
        HStack(alignment: .firstThird, spacing: 1) {
            HorizontalStripes().frame(height: 60)
            HorizontalStripes().frame(height: 120)
            HorizontalStripes().frame(height: 90)
                .alignmentGuide(.firstThird) { context in
                    2 * context.height / 3
                }
        }
    }
}
```

The modified guide calculation causes the affected view to place the bottom edge of its middle rectangle on the firstThird guide, which aligns with the bottom edge of the top rectangle in the other two groups:

Topics:
**Getting the default value**: defaultValue(in:)

---

## Anchor

[Apple docs](https://developer.apple.com/documentation/swiftui/anchor) · [DocC JSON](https://developer.apple.com/tutorials/data/documentation/swiftui/anchor.json)

_Structure_

Availability: macOS 10.15

An opaque value derived from an anchor source and a particular view.

Declaration:
```swift
@frozen struct Anchor<Value>
```


## Overview

You can convert the anchor to a Value in the coordinate space of a target view by using a GeometryProxy to specify the target view.

Topics:
**Getting the anchor’s source**: Anchor.Source

---
