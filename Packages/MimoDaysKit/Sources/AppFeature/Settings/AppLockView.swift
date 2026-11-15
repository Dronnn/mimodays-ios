import DesignSystem
import SwiftUI
import UIKit

/// L02: what covers MimoDays while it's locked.
struct AppLockView: View {
    let biometry: AppLock.Biometry
    let unlock: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            Icon.glyphLock.image
                .resizable()
                .frame(width: 30, height: 30)
                .foregroundStyle(ColorToken.textPrimary.color)
                .frame(width: 88, height: 88)
                .background(Circle().fill(ColorToken.accentPeach.color))
                .accessibilityHidden(true)
            Text(verbatim: "MimoDays")
                .textStyle(.displayHeadline)
                .foregroundStyle(ColorToken.textPrimary.color)
                .accessibilityAddTraits(.isHeader)
                .padding(.top, 28)
            Text("Locked", bundle: .module)
                .textStyle(.body)
                .foregroundStyle(ColorToken.textSecondary.color)
                .padding(.top, 6)
            Spacer()
            Button(action: unlock) {
                Text("Unlock with \(biometry.name)", bundle: .module, comment: "The lock screen's button, e.g. 'Unlock with Face ID'")
            }
            .buttonStyle(.primary)
            .accessibilityIdentifier("appLock.unlock")
            .padding(.horizontal, 20)
            .padding(.bottom, 16)
        }
        .frame(maxWidth: .infinity)
        .background(ColorToken.canvas.color.ignoresSafeArea())
    }
}

/// Puts the lock screen in a window above everything, sheets and full-screen covers included.
struct AppLockWindow: UIViewRepresentable {
    let lock: AppLock
    let isLocked: Bool

    func makeUIView(context: Context) -> Anchor { Anchor(lock: lock) }

    func updateUIView(_ view: Anchor, context: Context) {
        view.update(isLocked: isLocked)
    }

    final class Anchor: UIView {
        private let lock: AppLock
        private var window_: UIWindow?
        private var isLocked = false

        init(lock: AppLock) {
            self.lock = lock
            super.init(frame: .zero)
            isUserInteractionEnabled = false
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            guard window_ == nil, let scene = window?.windowScene else { return }
            let window = UIWindow(windowScene: scene)
            window.windowLevel = .alert + 1
            let lock = lock
            let host = UIHostingController(rootView: AppLockView(biometry: lock.biometry) { Task { await lock.unlock() } })
            host.view.backgroundColor = .clear
            window.rootViewController = host
            window_ = window
            update(isLocked: isLocked)
        }

        func update(isLocked: Bool) {
            self.isLocked = isLocked
            guard let window_ else { return }
            if isLocked {
                // S04's light, dark and contrast choice, as on the app's own window.
                if let main = window {
                    window_.overrideUserInterfaceStyle = main.overrideUserInterfaceStyle
                    if main.traitOverrides.contains(UITraitAccessibilityContrast.self) {
                        window_.traitOverrides.accessibilityContrast = main.traitOverrides.accessibilityContrast
                    } else if window_.traitOverrides.contains(UITraitAccessibilityContrast.self) {
                        window_.traitOverrides.remove(UITraitAccessibilityContrast.self)
                    }
                }
                window_.makeKeyAndVisible()
            } else {
                window_.isHidden = true
                window?.makeKey()
            }
        }
    }
}
