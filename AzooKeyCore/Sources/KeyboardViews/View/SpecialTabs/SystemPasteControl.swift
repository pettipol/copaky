//
//  SystemPasteControl.swift
//  Copaky
//
//  Apple's system paste button (UIPasteControl) wrapped for SwiftUI.
//  システム標準のペーストボタン（UIPasteControl）のSwiftUIラッパー。
//

import os
import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// Copaky: diagnostics for the paste prototype.
///
/// The whole point of the device round is to answer a question the Simulator cannot: does iOS actually
/// route a paste into a keyboard extension's input view? Without these probes a failure is
/// indistinguishable from "the user never tapped", "the control was disabled", "loading failed" and
/// "the text was too long" — all of them produce exactly the same nothing.
///
/// `os.Logger`, not the repo's `debug(…)`: that one compiles away outside DEBUG and prints to stdout,
/// so it does not exist on a phone. These lines are readable in Console.app with the device attached.
///
/// NEVER log the pasted text. Lengths, counts and booleans only: writing a user's clipboard into the
/// system log would damage the privacy invariant far more than any banner this prototype hopes to avoid.
/// 貼り付け内容そのものは絶対に記録しない（長さと件数のみ）。
private let pasteLog = Logger(subsystem: "com.pettipol.copaky", category: "paste-control")

/// Copaky: the system paste button.
///
/// Why it exists: iOS only recognises a few gestures as "the user meant to paste" — ⌘V, the edit
/// menu, and THIS control. A custom button, however explicit it looks, has to read
/// `UIPasteboard.general` itself, which is what raises the "pasted from …" banner every single time.
/// Routed through `UIPasteControl` the text is handed to us as an item provider: no pasteboard read,
/// no banner, and the privacy claim ("we read the clipboard only on your action") stays literally
/// true — the tap on Apple's own control IS the action.
///
/// Apple does not document using this control inside a keyboard extension's input view, so this is
/// deliberately a prototype behind a setting: it must be validated on a real device (the paste
/// dialog does not exist on the Simulator at all).
///
/// Copaky: システム標準のペーストボタン。iOSが「ユーザーの意図」と認めるのは⌘V・編集メニュー・
/// このコントロールだけで、独自ボタンはUIPasteboardを読むためバナーが出る。キーボード拡張内での
/// 利用はApple未文書のため、設定で切り替える試験実装として置く。
@available(iOS 16.0, *)
struct SystemPasteControl: UIViewRepresentable {
    /// Called with the pasted plain text, on the main actor.
    let onPaste: (String) -> Void

    func makeUIView(context: Context) -> UIView {
        let receiver = PasteReceiverView()
        receiver.onPaste = onPaste
        // Only plain text: the clipboard history stores strings, and asking for more would let the
        // control offer pastes we cannot store.
        receiver.pasteConfiguration = UIPasteConfiguration(acceptableTypeIdentifiers: [UTType.plainText.identifier])

        // Deliberately NOT tinted with the keyboard theme. This is Apple's consent control: the system
        // paints foreground and background as a matched pair, while our theme would set only the
        // foreground — and a theme with a pale text colour could render it invisible. During a device
        // round that would read as "the button does nothing" and would poison the one question the
        // round exists to answer. It also keeps the control looking like what App Review expects.
        // テーマで着色しない（前景だけ変えると読めなくなる恐れがあり、実機検証の結果を汚す）。
        let configuration = UIPasteControl.Configuration()
        configuration.displayMode = .iconAndLabel
        configuration.cornerStyle = .capsule
        let control = UIPasteControl(configuration: configuration)
        // The control walks the responder chain; `receiver` is its superview, so it is found first.
        control.target = receiver
        control.translatesAutoresizingMaskIntoConstraints = false
        receiver.addSubview(control)
        NSLayoutConstraint.activate([
            control.centerXAnchor.constraint(equalTo: receiver.centerXAnchor),
            control.centerYAnchor.constraint(equalTo: receiver.centerYAnchor),
            control.heightAnchor.constraint(lessThanOrEqualTo: receiver.heightAnchor),
        ])
        return receiver
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        (uiView as? PasteReceiverView)?.onPaste = onPaste
    }

    /// The responder that actually receives the paste. `UIPasteControl` delivers item providers to
    /// its target instead of exposing the pasteboard, which is the whole point.
    /// ペーストを受け取るレスポンダ。ペーストボードではなくアイテムプロバイダが渡される。
    private final class PasteReceiverView: UIView {
        var onPaste: ((String) -> Void)?

        override func canPaste(_ itemProviders: [NSItemProvider]) -> Bool {
            let textual = itemProviders.filter(Self.carriesText)
            pasteLog.info("canPaste: \(itemProviders.count, privacy: .public) provider, \(textual.count, privacy: .public) testuali")
            return !textual.isEmpty
        }

        override func paste(itemProviders: [NSItemProvider]) {
            pasteLog.info("paste: il sistema ha consegnato \(itemProviders.count, privacy: .public) provider")
            // One item is enough: the history stores a single string per entry.
            guard let provider = itemProviders.first(where: Self.carriesText) else {
                pasteLog.error("paste: nessun provider caricabile come testo — niente da salvare")
                return
            }
            // The load calls back off the main thread and the history is @MainActor: everything that
            // crosses back is a String (Sendable).
            // 読み込みは別スレッドで返るため、Sendable な String だけを戻す。
            Task { [weak self] in
                let text = await Self.loadPlainText(from: provider)
                if let text {
                    pasteLog.info("consegnato: \(text.count, privacy: .public) caratteri")
                    self?.onPaste?(text)
                } else {
                    pasteLog.error("nessun testo consegnato al termine del caricamento")
                }
            }
        }

        private static func carriesText(_ provider: NSItemProvider) -> Bool {
            provider.canLoadObject(ofClass: String.self)
                || provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier)
        }

        /// Two routes, deliberately.
        ///
        /// The obvious one — `loadObject(ofClass: NSString.self)` — is exactly what FAILED on a real
        /// phone (2026-08-12): `canLoadObject` answered yes, iOS delivered the provider on the tap, and
        /// the load then died with «could not cast an item to class NSString». The text was there; only
        /// our way of asking for it was wrong, and the whole prototype read as "iOS refuses to deliver".
        /// So: bridge through Swift's `String` first, and if that refuses, take the raw bytes for
        /// public.plain-text and decode them ourselves.
        /// NSString へのキャストは実機で失敗するため、String ブリッジ→生データの二段構えにする。
        private static func loadPlainText(from provider: NSItemProvider) async -> String? {
            if provider.canLoadObject(ofClass: String.self) {
                let viaObject: String? = await withCheckedContinuation { continuation in
                    _ = provider.loadObject(ofClass: String.self) { object, error in
                        if let error {
                            // Length/kind only — never the value.
                            pasteLog.error("loadObject(String) fallito: \(error.localizedDescription, privacy: .public)")
                        }
                        continuation.resume(returning: object)
                    }
                }
                if let viaObject { return viaObject }
            }
            return await withCheckedContinuation { continuation in
                provider.loadDataRepresentation(forTypeIdentifier: UTType.plainText.identifier) { data, error in
                    if let error {
                        pasteLog.error("loadDataRepresentation fallito: \(error.localizedDescription, privacy: .public)")
                    }
                    guard let data else {
                        continuation.resume(returning: nil)
                        return
                    }
                    continuation.resume(returning: String(data: data, encoding: .utf8))
                }
            }
        }
    }
}
