import SwiftUI

/// A screen's model, made once for the screen's life and there from its first frame. Made in `body` and handed to
/// `@State`, a model is made again on every redraw, though only the first is kept: each one loads, observes and (the
/// movie editor's) composes for nothing, and a model whose making redraws the screen makes the next one.
struct ModelHost<Model: AnyObject, Content: View>: View {
    private let make: () -> Model
    private let content: (Model) -> Content
    @State private var made = Made()

    init(_ make: @escaping () -> Model, @ViewBuilder content: @escaping (Model) -> Content) {
        self.make = make
        self.content = content
    }

    var body: some View { content(made.model(make)) }

    /// Not observed: filling it in while `body` runs redraws nothing.
    private final class Made {
        private var model: Model?

        func model(_ make: () -> Model) -> Model {
            if let model { return model }
            let new = make()
            model = new
            return new
        }
    }
}
