import SwiftUI

private let isoDateFormatter: DateFormatter = {
    let f = DateFormatter()
    f.calendar = Calendar(identifier: .gregorian)
    f.locale = Locale(identifier: "en_US_POSIX")
    f.timeZone = .current
    f.dateFormat = "yyyy-MM-dd"
    return f
}()

struct RepositorySearchFiltersView: View {

    static func parseISODate(_ value: String) -> Date? {
        isoDateFormatter.date(from: value)
    }

    static func formatISODate(_ date: Date) -> String {
        isoDateFormatter.string(from: date)
    }

    @Environment(\.dismiss) private var dismiss

    let initial: RepositorySearchQualifiers
    let onApply: (RepositorySearchQualifiers) -> Void

    @State private var inTargets: Set<RepositorySearchInTarget>
    @State private var language: GitHubLanguage?
    @State private var starsMinText: String
    @State private var starsMaxText: String
    @State private var pushedFromDate: Date?
    @State private var pushedToDate: Date?
    @State private var topicsText: String
    @State private var isShowingClearConfirmation = false

    init(initial: RepositorySearchQualifiers, onApply: @escaping (RepositorySearchQualifiers) -> Void) {
        self.initial = initial
        self.onApply = onApply
        _inTargets = State(initialValue: initial.inTargets)
        _language = State(initialValue: initial.language)
        _starsMinText = State(initialValue: initial.stars.min.map(String.init) ?? "")
        _starsMaxText = State(initialValue: initial.stars.max.map(String.init) ?? "")
        _pushedFromDate = State(initialValue: initial.pushed.from.flatMap(Self.parseISODate(_:)))
        _pushedToDate = State(initialValue: initial.pushed.to.flatMap(Self.parseISODate(_:)))
        _topicsText = State(initialValue: initial.topics.joined(separator: ", "))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("検索対象 (in:)") {
                    ForEach(RepositorySearchQualifiers.inTargetOrder, id: \.self) { target in
                        Toggle(label(for: target), isOn: Binding(
                            get: { inTargets.contains(target) },
                            set: { newValue in
                                if newValue { inTargets.insert(target) }
                                else { inTargets.remove(target) }
                            }
                        ))
                    }
                }

                Section("言語") {
                    Picker("language", selection: $language) {
                        Text("指定なし").tag(GitHubLanguage?.none)
                        ForEach(GitHubLanguage.all) { lang in
                            Text(lang.name).tag(GitHubLanguage?.some(lang))
                        }
                    }
                    .pickerStyle(.navigationLink)
                }

                Section("スター数") {
                    TextField("最小", text: $starsMinText)
                        .keyboardType(.numberPad)
                    TextField("最大", text: $starsMaxText)
                        .keyboardType(.numberPad)
                }

                Section("最終 push 日") {
                    OptionalDateRow(label: "以降", selection: $pushedFromDate)
                    OptionalDateRow(label: "以前", selection: $pushedToDate)
                }

                Section("トピック (カンマ区切り)") {
                    TextField("ios, swiftui", text: $topicsText)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                }

                Section {
                    Button(role: .destructive) {
                        isShowingClearConfirmation = true
                    } label: {
                        Text("すべてクリア")
                            .frame(maxWidth: .infinity, alignment: .center)
                    }
                }
            }
            .navigationTitle("検索条件")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("適用") {
                        onApply(buildQualifiers())
                        dismiss()
                    }
                    .disabled(!buildQualifiers().isValid)
                }
            }
            .alert(
                "すべての検索条件をクリアしますか?",
                isPresented: $isShowingClearConfirmation
            ) {
                Button("キャンセル", role: .cancel) {}
                Button("すべてクリア", role: .destructive) { clearAll() }
            } message: {
                Text("入力中の条件はすべて初期状態に戻ります。")
            }
        }
    }

    private func clearAll() {
        inTargets = []
        language = nil
        starsMinText = ""
        starsMaxText = ""
        pushedFromDate = nil
        pushedToDate = nil
        topicsText = ""
    }

    private func label(for target: RepositorySearchInTarget) -> String {
        switch target {
        case .name: return "name"
        case .description: return "description"
        case .readme: return "readme"
        case .topics: return "topics"
        }
    }

    private func buildQualifiers() -> RepositorySearchQualifiers {
        let stars = RepositorySearchStarsRange(
            min: Int(starsMinText.trimmingCharacters(in: .whitespaces)),
            max: Int(starsMaxText.trimmingCharacters(in: .whitespaces))
        )
        let pushed = RepositorySearchPushedRange(
            from: pushedFromDate.map(Self.formatISODate(_:)),
            to: pushedToDate.map(Self.formatISODate(_:))
        )
        let topics = topicsText
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        return RepositorySearchQualifiers(
            inTargets: inTargets,
            language: language,
            stars: stars,
            pushed: pushed,
            topics: topics
        )
    }
}

private struct OptionalDateRow: View {
    let label: String
    @Binding var selection: Date?

    var body: some View {
        HStack {
            Text(label)
            Spacer()
            if let date = selection {
                DatePicker(
                    label,
                    selection: Binding(get: { date }, set: { selection = $0 }),
                    displayedComponents: .date
                )
                .labelsHidden()
                .datePickerStyle(.compact)
                .environment(\.locale, Locale(identifier: "ja_JP"))

                Button {
                    selection = nil
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(label)をクリア")
            } else {
                Button("日付を指定") {
                    selection = Date()
                }
                .accessibilityLabel("\(label)の日付を指定")
            }
        }
    }
}
