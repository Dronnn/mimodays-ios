import SwiftUI

extension View {
    /// P3.5 X07: Delete all and Replace everything wait while Make smaller replaces files.
    func shrinkInUseAlert(_ isPresented: Binding<Bool>) -> some View {
        alert(Text("Videos are being made smaller", bundle: .module, comment: "P3.5: an action needs files Make smaller replaces"), isPresented: isPresented) {
            Button(role: .cancel) {} label: { Text("OK", bundle: .module) }
        } message: {
            Text("Stop it first in Settings › Storage: it replaces these files.", bundle: .module, comment: "P3.5: under Videos are being made smaller")
        }
    }
}
