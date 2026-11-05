import SwiftUI

struct InteractionPanel: View {
    let interaction: PendingInteraction
    @Bindable var store: HermesStore
    @State private var answer = ""
    @State private var isResponding = false
    @State private var selectedChoices: Set<String> = []

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(interaction.title, systemImage: interaction.kind == .approval ? "hand.raised" : "questionmark.bubble")
                .font(.headline)
            Text(interaction.message).textSelection(.enabled)
            if interaction.kind == .approval, interaction.message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || interaction.choices.isEmpty {
                Text("Approval details or choices are unavailable. Refresh them before deciding.")
                    .foregroundStyle(.secondary)
                Button("Refresh Details", systemImage: "arrow.clockwise") {
                    guard let id = store.selectedThreadID else { return }
                    Task { await store.openThread(id) }
                }
                .frame(minHeight: 44)
                .disabled(store.connection != .connected)
            } else if interaction.choices.isEmpty {
                if interaction.isSensitive {
                    SecureField("Your Answer", text: $answer)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } else {
                    TextField("Your Answer", text: $answer, axis: .vertical)
                        .lineLimit(1...5)
                }
                Button("Send Answer") { respond(answer) }
                    .disabled(answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isResponding || store.connection != .connected)
                    .frame(minHeight: 44)
            } else if interaction.allowsMultipleSelection {
                Text("Choose all that apply, then send your answer.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                ForEach(interaction.choices, id: \.self) { choice in
                    Button {
                        if selectedChoices.contains(choice) { selectedChoices.remove(choice) }
                        else { selectedChoices.insert(choice) }
                    } label: {
                        Label(choice, systemImage: selectedChoices.contains(choice) ? "checkmark.square.fill" : "square")
                            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    }
                    .buttonStyle(.bordered)
                    .disabled(isResponding || store.connection != .connected)
                    .accessibilityValue(selectedChoices.contains(choice) ? "Selected" : "Not Selected")
                }
                Button("Send Answer") { respond(interaction.choices.filter { selectedChoices.contains($0) }) }
                    .buttonStyle(.borderedProminent)
                    .frame(minHeight: 44)
                    .disabled(selectedChoices.isEmpty || isResponding || store.connection != .connected)
            } else {
                ViewThatFits(in: .horizontal) {
                    HStack {
                        ForEach(interaction.choices, id: \.self) { choice in choiceButton(choice) }
                    }
                    VStack(alignment: .leading) {
                        ForEach(interaction.choices, id: \.self) { choice in choiceButton(choice) }
                    }
                }
            }
            HStack {
                if isResponding { ProgressView("Sending Decision…") }
                Spacer()
                if interaction.kind != .approval {
                    Button("Skip Request") {
                        isResponding = true
                        Task { await store.cancelInteraction(); isResponding = false }
                    }
                    .frame(minHeight: 44)
                    .disabled(isResponding || store.connection != .connected)
                }
            }
        }
        .padding(16)
        .background(.quaternary, in: .rect(cornerRadius: 16))
        .overlay { RoundedRectangle(cornerRadius: 16).stroke(.secondary, lineWidth: 1) }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(interaction.kind == .approval ? "Approval required" : "Hermes needs your answer")
        .onChange(of: interaction.message) { _, _ in answer = ""; selectedChoices.removeAll() }
        .onChange(of: interaction.questionIndex) { _, _ in answer = ""; selectedChoices.removeAll() }
    }

    private func choiceButton(_ choice: String) -> some View {
        Button(choice) { respond(choice) }
            .buttonStyle(.bordered)
            .frame(minHeight: 44)
            .disabled(isResponding || store.connection != .connected)
    }

    private func respond(_ value: String) {
        guard !isResponding else { return }
        isResponding = true
        Task { await store.respondToInteraction(value); isResponding = false }
    }

    private func respond(_ values: [String]) {
        guard !isResponding else { return }
        isResponding = true
        Task { await store.respondToInteraction(values); isResponding = false }
    }
}
