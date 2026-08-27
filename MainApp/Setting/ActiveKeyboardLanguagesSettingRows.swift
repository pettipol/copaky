//
//  ActiveKeyboardLanguagesSettingRows.swift
//  MainApp
//

import AzooKeyUtils
import enum KanaKanjiConverterModule.KeyboardLanguage
import SwiftUI
import SwiftUIUtils

struct ActiveKeyboardLanguagesSettingRows: View {
    @State private var setting: SettingUpdater<ActiveKeyboardLanguagesSetting>
    @State private var latinLanguages: [KeyboardLanguage]
    // Owned by SettingTabView and applied to the enclosing Form: only there can the List draw the
    // reorder handles. / 並べ替えハンドルはFormのenvironmentからしか描画されない。
    @Binding var editMode: EditMode

    @MainActor init(editMode: Binding<EditMode>) {
        let setting = SettingUpdater<ActiveKeyboardLanguagesSetting>()
        self._setting = State(initialValue: setting)
        self._latinLanguages = State(
            initialValue: Self.displayedLatinLanguages(from: setting.value)
        )
        self._editMode = editMode
    }

    private var italianEnabled: Bool {
        setting.value.contains(.it_IT)
    }

    // Explicit closures only in this view — @MainActor method references (`perform: reload`)
    // make swift-frontend crash in IRGen (report_at_maximum_capacity, Xcode 17F113 / Swift 6).
    var body: some View {
        Group {
            HStack {
                // The identifier stays on the title ONLY: on the container it propagates to every
                // child and clobbers the edit button's own identifier (seen in the XCUI tree).
                Text(ActiveKeyboardLanguagesSetting.title)
                    .accessibilityIdentifier("active-languages-editor")
                HelpAlertButton(
                    title: ActiveKeyboardLanguagesSetting.title,
                    explanation: ActiveKeyboardLanguagesSetting.explanation
                )
                Spacer()
                editButton
            }
            .onAppear { reload() }

            HStack {
                Text("日本語")
                Spacer()
                Label("先頭に固定", systemImage: "pin.fill")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .moveDisabled(true)
            .accessibilityIdentifier("active-language-row-ja_JP")

            ForEach(latinLanguages, id: \.rawValue) { language in
                languageRow(language)
                    .moveDisabled(!italianEnabled)
                    .accessibilityIdentifier("active-language-row-\(language.rawValue)")
            }
            .onMove { source, destination in moveLatinLanguages(from: source, to: destination) }

            Text(ActiveKeyboardLanguagesSetting.explanation)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func languageRow(_ language: KeyboardLanguage) -> some View {
        switch language {
        case .en_US:
            HStack {
                Text("英語")
                Spacer()
                Label("常に有効", systemImage: "lock.fill")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        case .it_IT:
            Toggle(
                "イタリア語を使う",
                isOn: Binding(
                    get: { italianEnabled },
                    set: { setItalianEnabled($0) }
                )
            )
        case .ja_JP, .el_GR, .none:
            EmptyView()
        }
    }

    @ViewBuilder private var editButton: some View {
        switch editMode {
        case .inactive:
            Button("編集") {
                editMode = .active
            }
            .disabled(!italianEnabled)
            .accessibilityIdentifier("active-language-edit-button")
        case .active, .transient:
            Button("完了") {
                editMode = .inactive
            }
            .accessibilityIdentifier("active-language-edit-button")
        @unknown default:
            Button("完了") {
                editMode = .inactive
            }
            .accessibilityIdentifier("active-language-edit-button")
        }
    }

    private func reload() {
        setting.reload()
        latinLanguages = Self.displayedLatinLanguages(from: setting.value)
        if !italianEnabled {
            editMode = .inactive
        }
    }

    private func setItalianEnabled(_ enabled: Bool) {
        setting.value = [.ja_JP] + latinLanguages.filter { enabled || $0 != .it_IT }
        if !enabled {
            latinLanguages = Self.displayedLatinLanguages(from: setting.value)
            editMode = .inactive
        }
    }

    private func moveLatinLanguages(from source: IndexSet, to destination: Int) {
        guard italianEnabled else {
            return
        }
        latinLanguages.move(fromOffsets: source, toOffset: destination)
        setting.value = [.ja_JP] + latinLanguages
    }

    private static func displayedLatinLanguages(
        from activeLanguages: [KeyboardLanguage]
    ) -> [KeyboardLanguage] {
        var languages = activeLanguages.filter { $0.usesLatinScript }
        if !languages.contains(.en_US) {
            languages.append(.en_US)
        }
        if !languages.contains(.it_IT) {
            languages.append(.it_IT)
        }
        return languages
    }
}
