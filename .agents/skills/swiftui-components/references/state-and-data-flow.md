# State & Data Flow

Property wrappers and channels for moving data through a component tree: state, bindings, observation, environment, and preferences.

> Fetch tip: the human doc pages are a JS app (empty when fetched). For live detail, fetch the **DocC JSON** endpoint (`.../tutorials/data/documentation/swiftui/<symbol>.json`), not the HTML.

## Contents

- [State](#state)
- [Binding](#binding)
- [Bindable](#bindable)
- [StateObject](#stateobject)
- [ObservedObject](#observedobject)
- [EnvironmentObject](#environmentobject)
- [Environment](#environment)
- [EnvironmentValues](#environmentvalues)
- [EnvironmentKey](#environmentkey)
- [PreferenceKey](#preferencekey)
- [FocusState](#focusstate)
- [AppStorage](#appstorage)
- [SceneStorage](#scenestorage)

---

## State

[Apple docs](https://developer.apple.com/documentation/swiftui/state) · [DocC JSON](https://developer.apple.com/tutorials/data/documentation/swiftui/state.json)

_Structure_

Availability: macOS 10.15

A property wrapper type that can read and write a value managed by SwiftUI.

Declaration:
```swift
@frozen @propertyWrapper struct State<Value>
```


## Overview

> **Important:** When you build with Xcode 27 or later, the system uses the State() macro instead.

Use state as the single source of truth for a given value type that you store in a view hierarchy. Create a state value in an App, Scene, or View by applying the @State attribute to a property declaration and providing an initial value. Declare state as private to prevent setting it in a memberwise initializer, which can conflict with the storage management that SwiftUI provides:

```swift
struct PlayButton: View {
    @State private var isPlaying: Bool = false // Create the state.

    var body: some View {
        Button(isPlaying ? "Pause" : "Play") { // Read the state.
            isPlaying.toggle() // Write the state.
        }
    }
}
```

SwiftUI manages the property’s storage. When the value changes, SwiftUI updates the parts of the view hierarchy that depend on the value. To access a state’s underlying value, you use its wrappedValue property. However, as a shortcut Swift enables you to access the wrapped value by referring directly to the state instance. The above example reads and writes the isPlaying state property’s wrapped value by referring to the property directly.

Declare state as private in the highest view in the view hierarchy that needs access to the value. Then share the state with any subviews that also need access, either directly for read-only access, or as a binding for read-write access. You can safely mutate state properties from any thread.


### Share state with subviews

If you pass a state property to a subview, SwiftUI updates the subview any time the value changes in the container view, but the subview can’t modify the value. To enable the subview to modify the state’s stored value, pass a Binding instead.

For example, you can remove the isPlaying state from the play button in the above example, and instead make the button take a binding:

```swift
struct PlayButton: View {
    @Binding var isPlaying: Bool // Play button now receives a binding.

    var body: some View {
        Button(isPlaying ? "Pause" : "Play") {
            isPlaying.toggle()
        }
    }
}
```

Then you can define a player view that declares the state and creates a binding to the state. Get the binding to the state value by accessing the state’s projectedValue, which you get by prefixing the property name with a dollar sign ($):

```swift
struct PlayerView: View {
    @State private var isPlaying: Bool = false // Create the state here now.

    var body: some View {
        VStack {
            PlayButton(isPlaying: $isPlaying) // Pass a binding.

            // ...
        }
    }
}
```

Initialize state by providing a default value in the state’s declaration, as in the above examples. Use state only for storage that’s local to a view and its subviews.


### Store observable objects

You can also store observable objects that you create with the Observable() macro in State; for example:

```swift
@Observable
class Library {
    var name = "My library of books"
    // ...
}

struct ContentView: View {
    @State private var library = Library()

    var body: some View {
        LibraryView(library: library)
    }
}
```

A State property always instantiates its default value when SwiftUI instantiates the view. For this reason, avoid side effects and performance-intensive work when initializing the default value. For example, if a view updates frequently, allocating a new default object each time the view initializes can become expensive. Instead, you can defer the creation of the object using the task(name:priority:file:line:_:) modifier, which is called only once when the view first appears:

```swift
struct ContentView: View {
    @State private var library: Library?

    var body: some View {
        LibraryView(library: library)
            .task {
                library = Library()
            }
    }
}
```

Delaying the creation of the observable state object ensures that unnecessary allocations of the object don’t happen each time SwiftUI initializes the view. Using the task(name:priority:file:line:_:) modifier is also an effective way to defer any other kind of work required to create the initial state of the view, such as network calls or file access.

> **Note:** It’s possible to store an object that conforms to the ObservableObject protocol in a State property. However the view will only update when the reference to the object changes, such as when setting the property with a reference to another object. The view will not update if any of the object’s published properties change. To track changes to both the reference and the object’s published properties, use StateObject instead of State when storing the object.


### Share observable state objects with subviews

To share an Observable object stored in State with a subview, pass the object reference to the subview. SwiftUI updates the subview anytime an observable property of the object changes, but only when the subview’s body reads the property. For example, in the following code BookView updates each time title changes but not when isAvailable changes:

```swift
@Observable
class Book {
    var title = "A sample book"
    var isAvailable = true
}

struct ContentView: View {
    @State private var book = Book()

    var body: some View {
        BookView(book: book)
    }
}

struct BookView: View {
    var book: Book

    var body: some View {
        Text(book.title)
    }
}
```

State properties provide bindings to their value. When storing an object, you can get a Binding to that object, specifically the reference to the object. This is useful when you need to change the reference stored in state in some other subview, such as setting the reference to nil:

```swift
struct ContentView: View {
    @State private var book: Book?

    var body: some View {
        DeleteBookView(book: $book)
            .task {
                book = Book()
            }
    }
}

struct DeleteBookView: View {
    @Binding var book: Book?

    var body: some View {
        Button("Delete book") {
            book = nil
        }
    }
}
```

However, passing a Binding to an object stored in State isn’t necessary when you need to change properties of that object. For example, you can set the properties of the object to new values in a subview by passing the object reference instead of a binding to the reference:

```swift
struct ContentView: View {
    @State private var book = Book()

    var body: some View {
        BookCheckoutView(book: book)
    }
}

struct BookCheckoutView: View {
    var book: Book

    var body: some View {
        Button(book.isAvailable ? "Check out book" : "Return book") {
            book.isAvailable.toggle()
        }
    }
}
```

If you need a binding to a specific property of the object, pass either the binding to the object and extract bindings to specific properties where needed, or pass the object reference and use the Bindable property wrapper to create bindings to specific properties. For example, in the following code BookEditorView wraps book with @Bindable. Then the view uses the $ syntax to pass to a TextField a binding to title:

```swift
struct ContentView: View {
    @State private var book = Book()

    var body: some View {
        BookView(book: book)
    }
}

struct BookView: View {
    let book: Book

    var body: some View {
        BookEditorView(book: book)
    }
}

struct BookEditorView: View {
    @Bindable var book: Book

    var body: some View {
        TextField("Title", text: $book.title)
    }
}
```

Topics:
**Creating a state**: init(wrappedValue:), init(initialValue:), init()
**Getting the value**: wrappedValue, projectedValue

---

## Binding

[Apple docs](https://developer.apple.com/documentation/swiftui/binding) · [DocC JSON](https://developer.apple.com/tutorials/data/documentation/swiftui/binding.json)

_Structure_

Availability: macOS 10.15

A property wrapper type that can read and write a value owned by a source of truth.

Declaration:
```swift
@frozen @propertyWrapper @dynamicMemberLookup struct Binding<Value>
```


## Overview

Use a binding to create a two-way connection between a property that stores data, and a view that displays and changes the data. A binding connects a property to a source of truth stored elsewhere, instead of storing data directly. For example, a button that toggles between play and pause can create a binding to a property of its parent view using the Binding property wrapper.

```swift
struct PlayButton: View {
    @Binding var isPlaying: Bool

    var body: some View {
        Button(isPlaying ? "Pause" : "Play") {
            isPlaying.toggle()
        }
    }
}
```

The parent view declares a property to hold the playing state, using the State property wrapper to indicate that this property is the value’s source of truth.

```swift
struct PlayerView: View {
    var episode: Episode
    @State private var isPlaying: Bool = false

    var body: some View {
        VStack {
            Text(episode.title)
                .foregroundStyle(isPlaying ? .primary : .secondary)
            PlayButton(isPlaying: $isPlaying) // Pass a binding.
        }
    }
}
```

When PlayerView initializes PlayButton, it passes a binding of its state property into the button’s binding property. Applying the $ prefix to a property wrapped value returns its projectedValue, which for a state property wrapper returns a binding to the value.

Whenever the user taps the PlayButton, the PlayerView updates its isPlaying state.

A binding conforms to Sendable only if its wrapped value type also conforms to Sendable. It is always safe to pass a sendable binding between different concurrency domains. However, reading from or writing to a binding’s wrapped value from a different concurrency domain may or may not be safe, depending on how the binding was created. SwiftUI will issue a warning at runtime if it detects a binding being used in a way that may compromise data safety.

> **Note:** To create bindings to properties of a type that conforms to the Observable protocol, use the Bindable property wrapper. For more information, see Migrating from the Observable Object protocol to the Observable macro.

Topics:
**Creating a binding**: init(_:), init(projectedValue:), init(get:set:), constant(_:)
**Getting the value**: wrappedValue, projectedValue, subscript(dynamicMember:)
**Managing changes**: id, animation(_:), transaction(_:), transaction
**Subscripts**: subscript(_:)
**Default Implementations**: Identifiable Implementations

---

## Bindable

[Apple docs](https://developer.apple.com/documentation/swiftui/bindable) · [DocC JSON](https://developer.apple.com/tutorials/data/documentation/swiftui/bindable.json)

_Structure_

Availability: macOS 14.0

A property wrapper type that supports creating bindings to the mutable properties of observable objects.

Declaration:
```swift
@dynamicMemberLookup @propertyWrapper struct Bindable<Value>
```


## Overview

Use this property wrapper to create bindings to mutable properties of a data model object that conforms to the Observable protocol. For example, the following code wraps the book input with @Bindable. Then it uses a TextField to change the title property of a book, and a Toggle to change the isAvailable property, using the $ syntax to pass a binding for each property to those controls.

```swift
@Observable
class Book: Identifiable {
    var title = "Sample Book Title"
    var isAvailable = true
}

struct BookEditView: View {
    @Bindable var book: Book
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Form {
            TextField("Title", text: $book.title)

            Toggle("Book is available", isOn: $book.isAvailable)

            Button("Close") {
                dismiss()
            }
        }
    }
}
```

You can use the Bindable property wrapper on properties and variables to an Observable object. This includes global variables, properties that exists outside of SwiftUI types, or even local variables. For example, you can create a @Bindable variable within a view’s body:

```swift
struct LibraryView: View {
    @State private var books = [Book(), Book(), Book()]

    var body: some View {
        List(books) { book in
            @Bindable var book = book
            TextField("Title", text: $book.title)
        }
    }
}
```

The @Bindable variable book provides a binding that connects TextField to the title property of a book so that a person can make changes directly to the model data.

Use this same approach when you need a binding to a property of an observable object stored in a view’s environment. For example, the following code uses the Environment property wrapper to retrieve an instance of the observable type Book. Then the code creates a @Bindable variable book and passes a binding for the title property to a TextField using the $ syntax.

```swift
struct TitleEditView: View {
    @Environment(Book.self) private var book

    var body: some View {
        @Bindable var book = book
        TextField("Title", text: $book.title)
    }
}
```

Topics:
**Creating a bindable value**: init(_:), init(wrappedValue:), init(projectedValue:)
**Getting the value**: wrappedValue, projectedValue, subscript(dynamicMember:)

---

## StateObject

[Apple docs](https://developer.apple.com/documentation/swiftui/stateobject) · [DocC JSON](https://developer.apple.com/tutorials/data/documentation/swiftui/stateobject.json)

_Structure_

Availability: macOS 11.0

A property wrapper type that instantiates an observable object.

Declaration:
```swift
@MainActor @frozen @propertyWrapper @preconcurrency struct StateObject<ObjectType> where ObjectType : ObservableObject
```


## Overview

Use a state object as the single source of truth for a reference type that you store in a view hierarchy. Create a state object in an App, Scene, or View by applying the @StateObject attribute to a property declaration and providing an initial value that conforms to the ObservableObject protocol. Declare state objects as private to prevent setting them from a memberwise initializer, which can conflict with the storage management that SwiftUI provides:

```swift
class DataModel: ObservableObject {
    @Published var name = "Some Name"
    @Published var isEnabled = false
}

struct MyView: View {
    @StateObject private var model = DataModel() // Create the state object.

    var body: some View {
        Text(model.name) // Updates when the data model changes.
        MySubView()
            .environmentObject(model)
    }
}
```

SwiftUI creates a new instance of the model object only once during the lifetime of the container that declares the state object. For example, SwiftUI doesn’t create a new instance if a view’s inputs change, but does create a new instance if the identity of a view changes. When published properties of the observable object change, SwiftUI updates any view that depends on those properties, like the Text view in the above example.

> **Note:** If you need to store a value type, like a structure, string, or integer, use the State property wrapper instead. Also use State if you need to store a reference type that conforms to the Observable() protocol. To learn more about Observation in SwiftUI, see Managing model data in your app.


### Share state objects with subviews

You can pass a state object into a subview through a property that has the ObservedObject attribute. Alternatively, add the object to the environment of a view hierarchy by applying the environmentObject(_:) modifier to a view, like MySubView in the above code. You can then read the object inside MySubView or any of its descendants using the EnvironmentObject attribute:

```swift
struct MySubView: View {
    @EnvironmentObject var model: DataModel

    var body: some View {
        Toggle("Enabled", isOn: $model.isEnabled)
    }
}
```

Get a Binding to the state object’s properties using the dollar sign ($) operator. Use a binding when you want to create a two-way connection. In the above code, the Toggle controls the model’s isEnabled value through a binding.


### Initialize state objects using external data

When a state object’s initial state depends on data that comes from outside its container, you can call the object’s initializer explicitly from within its container’s initializer. For example, suppose the data model from the previous example takes a name input during initialization and you want to use a value for that name that comes from outside the view. You can do this with a call to the state object’s initializer inside an explicit initializer that you create for the view:

```swift
struct MyInitializableView: View {
    @StateObject private var model: DataModel

    init(name: String) {
        // SwiftUI ensures that the following initialization uses the
        // closure only once during the lifetime of the view, so
        // later changes to the view's name input have no effect.
        _model = StateObject(wrappedValue: DataModel(name: name))
    }

    var body: some View {
        VStack {
            Text("Name: \(model.name)")
        }
    }
}
```

Use caution when doing this. SwiftUI only initializes a state object the first time you call its initializer in a given view. This ensures that the object provides stable storage even as the view’s inputs change. However, it might result in unexpected behavior or unwanted side effects if you explicitly initialize the state object.

In the above example, if the name input to MyInitializableView changes, SwiftUI reruns the view’s initializer with the new value. However, SwiftUI runs the autoclosure that you provide to the state object’s initializer only the first time you call the state object’s initializer, so the model’s stored name value doesn’t change.

Explicit state object initialization works well when the external data that the object depends on doesn’t change for a given instance of the object’s container. For example, you can create two views with different constant names:

```swift
var body: some View {
    VStack {
        MyInitializableView(name: "Ravi")
        MyInitializableView(name: "Maria")
    }
}
```

> **Important:** Even for a configurable state object, you still declare it as private. This ensures that you can’t accidentally set the parameter through a memberwise initializer of the view, because doing so can conflict with the framework’s storage management and produce unexpected results.


### Force reinitialization by changing view identity

If you want SwiftUI to reinitialize a state object when a view input changes, make sure that the view’s identity changes at the same time. One way to do this is to bind the view’s identity to the value that changes using the id(_:) modifier. For example, you can ensure that the identity of an instance of MyInitializableView changes when its name input changes:

```swift
MyInitializableView(name: name)
    .id(name) // Binds the identity of the view to the name property.
```

> **Note:** If your view appears inside a ForEach, it implicitly receives an id(_:) modifier that uses the identifier of the corresponding data element.

If you need the view to reinitialize state based on changes in more than one value, you can combine the values into a single identifier using a Hasher. For example, if you want to update the data model in MyInitializableView when the values of either name or isEnabled change, you can combine both variables into a single hash:

```swift
var hash: Int {
    var hasher = Hasher()
    hasher.combine(name)
    hasher.combine(isEnabled)
    return hasher.finalize()
}
```

Then apply the combined hash to the view as an identifier:

```swift
MyInitializableView(name: name, isEnabled: isEnabled)
    .id(hash)
```

Be mindful of the performance cost of reinitializing the state object every time the input changes. Also, changing view identity can have side effects. For example, SwiftUI doesn’t automatically animate changes inside the view if the view’s identity changes at the same time. Also, changing the identity resets all state held by the view, including values that you manage as State, FocusState, GestureState, and so on.

Topics:
**Creating a state object**: init(wrappedValue:)
**Getting the value**: wrappedValue, projectedValue

---

## ObservedObject

[Apple docs](https://developer.apple.com/documentation/swiftui/observedobject) · [DocC JSON](https://developer.apple.com/tutorials/data/documentation/swiftui/observedobject.json)

_Structure_

Availability: macOS 10.15

A property wrapper type that subscribes to an observable object and invalidates a view whenever the observable object changes.

Declaration:
```swift
@MainActor @propertyWrapper @preconcurrency @frozen struct ObservedObject<ObjectType> where ObjectType : ObservableObject
```


## Overview

Add the @ObservedObject attribute to a parameter of a SwiftUI View when the input is an ObservableObject and you want the view to update when the object’s published properties change. You typically do this to pass a StateObject into a subview.

The following example defines a data model as an observable object, instantiates the model in a view as a state object, and then passes the instance to a subview as an observed object:

```swift
class DataModel: ObservableObject {
    @Published var name = "Some Name"
    @Published var isEnabled = false
}

struct MyView: View {
    @StateObject private var model = DataModel()

    var body: some View {
        Text(model.name)
        MySubView(model: model)
    }
}

struct MySubView: View {
    @ObservedObject var model: DataModel

    var body: some View {
        Toggle("Enabled", isOn: $model.isEnabled)
    }
}
```

When any published property of the observable object changes, SwiftUI updates any view that depends on the object. Subviews can also make updates to the model properties, like the Toggle in the above example, that propagate to other observers throughout the view hierarchy.

Don’t specify a default or initial value for the observed object. Use the attribute only for a property that acts as an input for a view, as in the above example.

> **Note:** Don’t wrap objects conforming to the Observable protocol with @ObservedObject. SwiftUI automatically tracks dependencies to Observable objects used within body and updates dependent views when their data changes. Attempting to wrap an Observable object with @ObservedObject may cause a compiler error, because it requires that its wrapped object to conform to the ObservableObject protocol.

If the view needs a binding to a property of an Observable object in its body, wrap the object with the Bindable property wrapper instead; for example, @Bindable var model: DataModel. For more information, see Managing model data in your app.

Topics:
**Creating an observed object**: init(wrappedValue:), init(initialValue:)
**Getting the value**: wrappedValue, projectedValue, ObservedObject.Wrapper

---

## EnvironmentObject

[Apple docs](https://developer.apple.com/documentation/swiftui/environmentobject) · [DocC JSON](https://developer.apple.com/tutorials/data/documentation/swiftui/environmentobject.json)

_Structure_

Availability: macOS 10.15

A property wrapper type for an observable object that a parent or ancestor view supplies.

Declaration:
```swift
@MainActor @frozen @propertyWrapper @preconcurrency struct EnvironmentObject<ObjectType> where ObjectType : ObservableObject
```


## Overview

An environment object invalidates the current view whenever the observable object that conforms to ObservableObject changes. If you declare a property as an environment object, be sure to set a corresponding model object on an ancestor view by calling its environmentObject(_:) modifier.

> **Note:** If your observable object conforms to the Observable protocol, use Environment instead of EnvironmentObject and set the model object in an ancestor view by calling its environment(_:) or environment(_:_:) modifiers.

Topics:
**Creating an environment object**: init()
**Getting the value**: wrappedValue, projectedValue, EnvironmentObject.Wrapper

---

## Environment

[Apple docs](https://developer.apple.com/documentation/swiftui/environment) · [DocC JSON](https://developer.apple.com/tutorials/data/documentation/swiftui/environment.json)

_Structure_

Availability: macOS 10.15

A property wrapper that reads a value from a view’s environment.

Declaration:
```swift
@frozen @propertyWrapper struct Environment<Value>
```


## Overview

Use the Environment property wrapper to read a value stored in a view’s environment. Indicate the value to read using an EnvironmentValues key path in the property declaration. For example, you can create a property that reads the color scheme of the current view using the key path of the colorScheme property:

```swift
@Environment(\.colorScheme) var colorScheme: ColorScheme
```

You can condition a view’s content on the associated value, which you read from the declared property’s wrappedValue. As with any property wrapper, you access the wrapped value by directly referring to the property:

```swift
if colorScheme == .dark { // Checks the wrapped value.
    DarkContent()
} else {
    LightContent()
}
```

If the value changes, SwiftUI updates any parts of your view that depend on the value. For example, that might happen in the above example if the user changes the Appearance settings.

You can use this property wrapper to read — but not set — an environment value. SwiftUI updates some environment values automatically based on system settings and provides reasonable defaults for others. You can override some of these, as well as set custom environment values that you define, using the environment(_:_:) view modifier.

For the complete list of environment values SwiftUI provides, see the properties of the EnvironmentValues structure. For information about creating custom environment values, see the Entry() macro.


### Get an observable object

You can also use Environment to get an observable object from a view’s environment. The observable object must conform to the Observable protocol, and your app must set the object in the environment using the object itself or a key path.

To set the object in the environment using the object itself, use the environment(_:) modifier:

```swift
@Observable
class Library {
    var books: [Book] = [Book(), Book(), Book()]

    var availableBooksCount: Int {
        books.filter(\.isAvailable).count
    }
}

@main
struct BookReaderApp: App {
    @State private var library = Library()

    var body: some Scene {
        WindowGroup {
            LibraryView()
                .environment(library)
        }
    }
}
```

To get the observable object using its type, create a property and provide the Environment property wrapper the object’s type:

```swift
struct LibraryView: View {
    @Environment(Library.self) private var library

    var body: some View {
        // ...
    }
}
```

By default, reading an object from the environment returns a non-optional object when using the object type as the key. This default behavior assumes that a view in the current hierarchy previously stored a non-optional instance of the type using the environment(_:) modifier. If a view attempts to retrieve an object using its type and that object isn’t in the environment, SwiftUI throws an exception.

In cases where there is no guarantee that an object is in the environment, retrieve an optional version of the object as shown in the following code. If the object isn’t available the environment, SwiftUI returns nil instead of throwing an exception.

```swift
@Environment(Library.self) private var library: Library?
```


### Get an observable object using a key path

To set the object with a key path, use the environment(_:_:) modifier:

```swift
@Observable
class Library {
    var books: [Book] = [Book(), Book(), Book()]

    var availableBooksCount: Int {
        books.filter(\.isAvailable).count
    }
}

@main
struct BookReaderApp: App {
    @State private var library = Library()

    var body: some Scene {
        WindowGroup {
            LibraryView()
                .environment(\.library, library)
        }
    }
}
```

To get the object, create a property and specify the key path:

```swift
struct LibraryView: View {
    @Environment(\.library) private var library

    var body: some View {
        // ...
    }
}
```

Topics:
**Creating an environment instance**: init(_:)
**Getting the value**: wrappedValue

---

## EnvironmentValues

[Apple docs](https://developer.apple.com/documentation/swiftui/environmentvalues) · [DocC JSON](https://developer.apple.com/tutorials/data/documentation/swiftui/environmentvalues.json)

_Structure_

Availability: macOS 10.15

A collection of environment values propagated through a view hierarchy.

Declaration:
```swift
struct EnvironmentValues
```


## Overview

SwiftUI exposes a collection of values to your app’s views in an EnvironmentValues structure. To read a value from the structure, declare a property using the Environment property wrapper and specify the value’s key path. For example, you can read the current locale:

```swift
@Environment(\.locale) var locale: Locale
```

Use the property you declare to dynamically control a view’s layout. SwiftUI automatically sets or updates many environment values, like pixelLength, scenePhase, or locale, based on device characteristics, system state, or user settings. For others, like lineLimit, SwiftUI provides a reasonable default value.

You can set or override some values using the environment(_:_:) view modifier:

```swift
MyView()
    .environment(\.lineLimit, 2)
```

The value that you set affects the environment for the view that you modify — including its descendants in the view hierarchy — but only up to the point where you apply a different environment modifier.

SwiftUI provides dedicated view modifiers for setting some values, which typically makes your code easier to read. For example, rather than setting the lineLimit value directly, as in the previous example, you should instead use the lineLimit(_:) modifier:

```swift
MyView()
    .lineLimit(2)
```

In some cases, using a dedicated view modifier provides additional functionality. For example, you must use the preferredColorScheme(_:) modifier rather than setting colorScheme directly to ensure that the new value propagates up to the presenting container when presenting a view like a popover:

```swift
MyView()
    .popover(isPresented: $isPopped) {
        PopoverContent()
            .preferredColorScheme(.dark)
    }
```

Create a custom environment value by declaring a new property in an extension to the environment values structure and applying the Entry() macro to the variable declaration:

```swift
extension EnvironmentValues {
    @Entry var myCustomValue: String = "Default value"
}

extension View {
    func myCustomValue(_ myCustomValue: String) -> some View {
        environment(\.myCustomValue, myCustomValue)
    }
}
```

Clients of your value then access the value in the usual way, reading it with the Environment property wrapper, and setting it with the myCustomValue view modifier.

Topics:
**Creating and accessing values**: init(), subscript(_:), description
**Accessibility**: accessibilityAssistiveAccessEnabled, accessibilityDimFlashingLights, accessibilityDifferentiateWithoutColor, accessibilityEnabled, accessibilityInvertColors, accessibilityLargeContentViewerEnabled, accessibilityPlayAnimatedImages, accessibilityPrefersHeadAnchorAlternative, accessibilityPrefersCrossFadeTransitions, accessibilityQuickActionsEnabled, accessibilityReduceMotion, accessibilityReduceTransparency, accessibilityShowButtonShapes, accessibilitySwitchControlEnabled, accessibilityVoiceOverEnabled, legibilityWeight
**Actions**: dismiss, dismissSearch, dismissWindow, openImmersiveSpace, dismissImmersiveSpace, newDocument, openDocument, openURL, openWindow, pushWindow, purchase, refresh, rename, resetFocus, openSettings
**Authentication**: authorizationController, webAuthenticationSession
**Controls and input**: buttonRepeatBehavior, controlSize, defaultWheelPickerItemHeight, keyboardShortcut, menuIndicatorVisibility, menuOrder, searchSuggestionsPlacement, preferredPencilDoubleTapAction, preferredPencilSqueezeAction
**Display characteristics**: appearsActive, colorScheme, colorSchemeContrast, displayScale, horizontalSizeClass, imageScale, pixelLength, sidebarRowSize, verticalSizeClass, immersiveSpaceDisplacement, labelsVisibility, materialActiveAppearance, TabBarPlacement, toolbarLabelStyle
**Global objects**: calendar, documentConfiguration, locale, managedObjectContext, modelContext, timeZone, undoManager
**Scrolling**: isScrollEnabled, horizontalScrollIndicatorVisibility, verticalScrollIndicatorVisibility, scrollDismissesKeyboardMode, horizontalScrollBounceBehavior, verticalScrollBounceBehavior
**State**: editMode, isActivityFullscreen, isEnabled, isFocused, isFocusEffectEnabled, isHoverEffectEnabled, isLuminanceReduced, isPresented, isSceneCaptured, isSearching, isTabBarShowingSections, scenePhase, supportsMultipleWindows
**StoreKit configuration**: displayStoreKitMessage, requestReview
**Text styles**: allowsTightening, autocorrectionDisabled, dynamicTypeSize, font, layoutDirection, lineLimit, lineSpacing, minimumScaleFactor, multilineTextAlignment, textCase, truncationMode, textSelectionAffinity
**View attributes**: allowedDynamicRange, backgroundMaterial, backgroundProminence, backgroundStyle, badgeProminence, contentTransition, contentTransitionAddsDrawingGroup, defaultMinListHeaderHeight, defaultMinListRowHeight, headerProminence, physicalMetrics, realityKitScene, realityViewCameraControls, redactionReasons, springLoadingBehavior, symbolRenderingMode, symbolVariants, worldTrackingLimitations
**Widgets**: showsWidgetContainerBackground, showsWidgetLabel, widgetFamily, widgetRenderingMode, widgetContentMargins
**Deprecated environment values**: disableAutocorrection, sizeCategory, presentationMode, PresentationMode, complicationRenderingMode, controlActiveState
**Instance Properties**: accessibilityReduceHighlightingEffects, accessibilityShowBorders, activityFamily, askPermission, buttonSizing, credentialDataManager, credentialExportManager, credentialImportManager, deliveredVerificationCodesManager, devicePickerSupports, findContext, fontResolutionContext, imagePlaygroundAllowedGenerationStyles, imagePlaygroundOptions, imagePlaygroundPersonalizationPolicy, imagePlaygroundSelectedGenerationStyle, isActivityUpdateReduced, isDynamicIslandLimitedInWidth, isTabViewSidebarAvailable, isUserAuthenticationEnabled, labelIconToTitleSpacing, labelReservedIconWidth, levelOfDetail, lineHeight, navigationLinkIndicatorVisibility, remoteDeviceIdentifier, requestAgeRange, requestAppDeletion, showSignificantUpdateAcknowledgment, supportedActivityFamilies, supportsImagePlayground, supportsRemoteScenes, surfaceSnappingInfo, symbolColorRenderingMode, symbolVariableValueMode, tabBarPlacement, tabViewBottomAccessoryPlacement, windowClippingMargins, writingToolsBehavior

---

## EnvironmentKey

[Apple docs](https://developer.apple.com/documentation/swiftui/environmentkey) · [DocC JSON](https://developer.apple.com/tutorials/data/documentation/swiftui/environmentkey.json)

_Protocol_

Availability: macOS 10.15

A key for accessing values in the environment.

Declaration:
```swift
protocol EnvironmentKey
```


## Overview

You can create custom environment values by extending the EnvironmentValues structure with new properties. First declare a new environment key type and specify a value for the required defaultValue property:

```swift
private struct MyEnvironmentKey: EnvironmentKey {
    static let defaultValue: String = "Default value"
}
```

The Swift compiler automatically infers the associated Value type as the type you specify for the default value. Then use the key to define a new environment value property:

```swift
extension EnvironmentValues {
    var myCustomValue: String {
        get { self[MyEnvironmentKey.self] }
        set { self[MyEnvironmentKey.self] = newValue }
    }
}
```

Clients of your environment value never use the key directly. Instead, they use the key path of your custom environment value property. To set the environment value for a view and all its subviews, add the environment(_:_:) view modifier to that view:

```swift
MyView()
    .environment(\.myCustomValue, "Another string")
```

As a convenience, you can also define a dedicated view modifier to apply this environment value:

```swift
extension View {
    func myCustomValue(_ myCustomValue: String) -> some View {
        environment(\.myCustomValue, myCustomValue)
    }
}
```

This improves clarity at the call site:

```swift
MyView()
    .myCustomValue("Another string")
```

To read the value from inside MyView or one of its descendants, use the Environment property wrapper:

```swift
struct MyView: View {
    @Environment(\.myCustomValue) var customValue: String

    var body: some View {
        Text(customValue) // Displays "Another string".
    }
}
```

Topics:
**Getting the default value**: defaultValue, Value

---

## PreferenceKey

[Apple docs](https://developer.apple.com/documentation/swiftui/preferencekey) · [DocC JSON](https://developer.apple.com/tutorials/data/documentation/swiftui/preferencekey.json)

_Protocol_

Availability: macOS 10.15

A named value produced by a view.

Declaration:
```swift
protocol PreferenceKey
```


## Overview

A view with multiple children automatically combines its values for a given preference into a single value visible to its ancestors.

Topics:
**Getting the default value**: defaultValue, Value
**Combining preferences**: reduce(value:nextValue:)

---

## FocusState

[Apple docs](https://developer.apple.com/documentation/swiftui/focusstate) · [DocC JSON](https://developer.apple.com/tutorials/data/documentation/swiftui/focusstate.json)

_Structure_

Availability: macOS 12.0

A property wrapper type that can read and write a value that SwiftUI updates as the placement of focus within the scene changes.

Declaration:
```swift
@frozen @propertyWrapper struct FocusState<Value> where Value : Hashable
```


## Overview

Use this property wrapper in conjunction with focused(_:equals:) and focused(_:) to describe views whose appearance and contents relate to the location of focus in the scene. When focus enters the modified view, the wrapped value of this property updates to match a given prototype value. Similarly, when focus leaves, the wrapped value of this property resets to nil or false. Setting the property’s value programmatically has the reverse effect, causing focus to move to the view associated with the updated value.

In the following example of a simple login screen, when the user presses the Sign In button and one of the fields is still empty, focus moves to that field. Otherwise, the sign-in process proceeds.

```swift
struct LoginForm {
    enum Field: Hashable {
        case username
        case password
    }

    @State private var username = ""
    @State private var password = ""
    @FocusState private var focusedField: Field?

    var body: some View {
        Form {
            TextField("Username", text: $username)
                .focused($focusedField, equals: .username)

            SecureField("Password", text: $password)
                .focused($focusedField, equals: .password)

            Button("Sign In") {
                if username.isEmpty {
                    focusedField = .username
                } else if password.isEmpty {
                    focusedField = .password
                } else {
                    handleLogin(username, password)
                }
            }
        }
    }
}
```

To allow for cases where focus is completely absent from a view tree, the wrapped value must be either an optional or a Boolean. Set the focus binding to false or nil as appropriate to remove focus from all bound fields. You can also use this to remove focus from a TextField and thereby dismiss the keyboard.


### Avoid ambiguous focus bindings

The same view can have multiple focus bindings. In the following example, setting focusedField to either name or fullName causes the field to receive focus:

```swift
struct ContentView: View {
    enum Field: Hashable {
        case name
        case fullName
    }
    @FocusState private var focusedField: Field?

    var body: some View {
        TextField("Full Name", ...)
            .focused($focusedField, equals: .name)
            .focused($focusedField, equals: .fullName)
    }
}
```

On the other hand, binding the same value to two views is ambiguous. In the following example, two separate fields bind focus to the name value:

```swift
struct ContentView: View {
    enum Field: Hashable {
        case name
        case fullName
    }
    @FocusState private var focusedField: Field?

    var body: some View {
        TextField("Name", ...)
            .focused($focusedField, equals: .name)
        TextField("Full Name", ...)
            .focused($focusedField, equals: .name) // incorrect re-use of .name
    }
}
```

If the user moves focus to either field, the focusedField binding updates to name. However, if the app programmatically sets the value to name, SwiftUI chooses the first candidate, which in this case is the “Name” field. SwiftUI also emits a runtime warning in this case, since the repeated binding is likely a programmer error.


### Nest focusable views

It is important to consider the difference between focused(_:equals:) and focused(_:) with nested focusable views.

For example, consider the following code:

```swift
struct ContentView: View {
    @FocusState private var fieldIsFocused: Bool
    @FocusState private var containerIsFocused: Bool

    var body: some View {
        VStack {
            TextField("Name", ...)
                .focused($fieldIsFocused)
        }
        .focusable()
        .focused($containerIsFocused)
    }
}
```

The code above uses focused(_:), which binds focus state to the given Boolean state value. focused(_:) sets containerIsFocused to true both when the VStack itself receives focus and just the TextField that it contains receives focus. This behavior occurs because two independent instances of @FocusState are used to observe the focus state of the focusable VStack and the TextField. When the VStack does not have focus, SwiftUI checks the view hierarchy to find the closest view with focus to set the value for containerIsFocused. If the TextField contained within this VStack happens to be focused, focused(_:) will set containerIsFocused to true.

If there is need to observe whether only the VStack has focus, but not the inner TextField, consider using focused(_:equals:) instead, for more granular control.

With focused(_:equals:), the above code can be rewritten as follows:

```swift
struct ContentView: View {
    enum Focus {
        case container
        case field
    }

    @FocusState private var focused: Focus?

    var body: some View {
        VStack {
            TextField("Name", ...)
                .focused($focused, equals: .field)
        }
        .focusable()
        .focused($focused, equals: .container)
    }
}
```

With focused(_:equals:), it is possible to define a custom data structure to represent focus state. In this case, a Focus enumeration is used. It has two cases, one for the focusable VStack and another for the TextField it contains. focused(_:equals:) binds focused to .container only when the VStack itself has focus, and to .field when the TextField has focus. Because now there is only one @FocusState property, SwiftUI is able to disambiguate between cases when VStack contains focus and receives focus itself.

Note that both of the above approaches are acceptable. focused(_:equals:) can be used to observe whether the given view currently receives focus. While focused(_:) can be used for the same purpose, additionally it can observe whether the given view contains focus.

Topics:
**Creating a focus state**: init()
**Inspecting the focus state**: projectedValue, FocusState.Binding, wrappedValue

---

## AppStorage

[Apple docs](https://developer.apple.com/documentation/swiftui/appstorage) · [DocC JSON](https://developer.apple.com/tutorials/data/documentation/swiftui/appstorage.json)

_Structure_

Availability: macOS 11.0

A property wrapper type that reflects a value from UserDefaults and invalidates a view on a change in value in that user default.

Declaration:
```swift
@frozen @propertyWrapper struct AppStorage<Value>
```

Topics:
**Storing a value**: init(wrappedValue:_:store:), init(_:store:)
**Getting the value**: wrappedValue, projectedValue

---

## SceneStorage

[Apple docs](https://developer.apple.com/documentation/swiftui/scenestorage) · [DocC JSON](https://developer.apple.com/tutorials/data/documentation/swiftui/scenestorage.json)

_Structure_

Availability: macOS 11.0

A property wrapper type that reads and writes to persisted, per-scene storage.

Declaration:
```swift
@frozen @propertyWrapper struct SceneStorage<Value>
```


## Overview

You use SceneStorage when you need automatic state restoration of the value.  SceneStorage works very similar to State, except its initial value is restored by the system if it was previously saved, and the value is shared with other SceneStorage variables in the same scene.

The system manages the saving and restoring of SceneStorage on your behalf. The underlying data that backs SceneStorage is not available to you, so you must access it via the SceneStorage property wrapper. The system makes no guarantees as to when and how often the data will be persisted.

Each Scene has its own notion of SceneStorage, so data is not shared between scenes.

Ensure that the data you use with SceneStorage is lightweight. Data of a large size, such as model data, should not be stored in SceneStorage, as poor performance may result.

If the Scene is explicitly destroyed (e.g. the switcher snapshot is destroyed on iPadOS or the window is closed on macOS), the data is also destroyed. Do not use SceneStorage with sensitive data.

Topics:
**Storing a value**: init(wrappedValue:_:), init(_:)
**Getting the value**: wrappedValue, projectedValue
**Initializers**: init(wrappedValue:_:store:)

---
