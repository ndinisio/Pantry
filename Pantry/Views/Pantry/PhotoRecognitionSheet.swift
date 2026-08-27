import SwiftUI
import SwiftData
import PhotosUI

/// Adding food from a photo.
///
/// Nothing is added without confirmation. The classifier proposes; the person decides.
/// Recognition runs on device, which is stated on screen because it is the reason this
/// feature is comfortable to use at all.
struct PhotoRecognitionSheet: View {

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @State private var selection: PhotosPickerItem?
    @State private var imageData: Data?
    @State private var state: RecognitionState = .waitingForPhoto
    @State private var chosen: Set<FoodCandidate> = []

    private let service: FoodRecognising = VisionFoodRecognitionService()

    private enum RecognitionState {
        case waitingForPhoto
        case working
        case found([FoodCandidate])
        case failed(FoodRecognitionError)
    }

    var body: some View {
        NavigationStack {
            Group {
                switch state {
                case .waitingForPhoto:
                    picker
                case .working:
                    AIProgressView(message: String(localized: "Looking at your photo…"))
                case .found(let candidates):
                    candidateList(candidates)
                case .failed(let error):
                    ContentUnavailableView {
                        Label(error.errorDescription ?? String(localized: "Recognition didn't work"), systemImage: "photo.badge.exclamationmark")
                    } description: {
                        if let suggestion = error.recoverySuggestion {
                            Text(suggestion)
                        }
                    } actions: {
                        Button(String(localized: "Choose Another Photo")) {
                            state = .waitingForPhoto
                            imageData = nil
                            selection = nil
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }
            .navigationTitle(Text("Add from Photo"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "Cancel")) { dismiss() }
                }
                if case .found = state {
                    ToolbarItem(placement: .confirmationAction) {
                        Button(String(localized: "Add \(chosen.count)"), action: addChosen)
                            .disabled(chosen.isEmpty)
                    }
                }
            }
            .task(id: selection) { await loadAndRecognise() }
        }
    }

    private var picker: some View {
        ContentUnavailableView {
            Label(String(localized: "Add from a Photo"), systemImage: "camera")
        } description: {
            Text("Take or choose a photo and Pantry will suggest what's in it. Recognition happens on your device — the photo isn't sent anywhere.")
        } actions: {
            PhotosPicker(selection: $selection, matching: .images, photoLibrary: .shared()) {
                Text("Choose Photo")
                    .frame(maxWidth: 220)
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private func candidateList(_ candidates: [FoodCandidate]) -> some View {
        List {
            if let imageData, let image = UIImage(data: imageData) {
                Section {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(height: 160)
                        .clipped()
                        .listRowInsets(EdgeInsets())
                        .accessibilityLabel(String(localized: "The photo you chose"))
                }
            }

            Section {
                ForEach(candidates) { candidate in
                    Button {
                        toggle(candidate)
                    } label: {
                        HStack(spacing: 12) {
                            CategoryGlyph(category: candidate.category)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(candidate.name)
                                    .foregroundStyle(.primary)
                                Text(candidate.confidenceDescription)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: chosen.contains(candidate) ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(chosen.contains(candidate) ? Color.accentColor : Color.secondary)
                                .imageScale(.large)
                        }
                    }
                    .accessibilityAddTraits(chosen.contains(candidate) ? [.isSelected] : [])
                }
            } header: {
                Text("What Pantry Thinks It Sees")
            } footer: {
                Text("These are guesses. Pick the ones that are right — you can fix names afterwards.")
            }
        }
    }

    private func toggle(_ candidate: FoodCandidate) {
        if chosen.contains(candidate) {
            chosen.remove(candidate)
        } else {
            chosen.insert(candidate)
        }
    }

    private func loadAndRecognise() async {
        guard let selection else { return }
        state = .working
        chosen = []
        guard let data = try? await selection.loadTransferable(type: Data.self) else {
            state = .failed(.invalidImage)
            return
        }
        imageData = data
        do {
            let candidates = try await service.recognise(imageData: data)
            state = .found(candidates)
        } catch let error as FoodRecognitionError {
            state = .failed(error)
        } catch {
            state = .failed(.failed(error.localizedDescription))
        }
    }

    private func addChosen() {
        let items = chosen.map { candidate in
            PantryItem(
                name: candidate.name,
                category: candidate.category,
                quantity: 1,
                unit: CategoryGuesser.unit(for: candidate.name),
                expirationDate: ExpirationCalculator.suggestedExpiration(for: candidate.category)
            )
        }
        InventoryService(context: modelContext).add(items)
        dismiss()
    }
}
