import SwiftUI
import AVFoundation
import UIKit

/// The scanning experience, including every way it can fail.
///
/// A scanned barcode identifies a *package*, not a name — so rather than inventing a
/// product, Pantry hands the code to the add form with the barcode filled in and lets
/// the user name it. Honest and one field of typing, instead of a wrong guess.
struct BarcodeScanSheet: View {

    @Environment(\.dismiss) private var dismiss
    @State private var state: ScanState = .checkingPermission
    @State private var scannedCode: String?

    private enum ScanState: Equatable {
        case checkingPermission
        case scanning
        case denied
        case unsupported
        case failed(String)
    }

    var body: some View {
        NavigationStack {
            Group {
                switch state {
                case .checkingPermission:
                    ProgressView()
                        .controlSize(.large)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)

                case .scanning:
                    BarcodeScannerView(
                        onScan: { code in
                            scannedCode = code
                        },
                        onFailure: { message in
                            state = .failed(message)
                        }
                    )
                    .ignoresSafeArea(edges: .bottom)
                    .overlay(alignment: .bottom) {
                        Text("Point the camera at a barcode.")
                            .font(.callout)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .background(.regularMaterial, in: .capsule)
                            .padding(.bottom, 32)
                            .accessibilityHidden(true)
                    }

                case .denied:
                    ContentUnavailableView {
                        Label(String(localized: "Camera Access Is Off"), systemImage: "camera.badge.ellipsis")
                    } description: {
                        Text("Pantry needs the camera to read barcodes. You can turn it on in Settings, or just type the item instead.")
                    } actions: {
                        Button(String(localized: "Open Settings")) {
                            if let url = URL(string: UIApplication.openSettingsURLString) {
                                UIApplication.shared.open(url)
                            }
                        }
                        .buttonStyle(.borderedProminent)
                    }

                case .unsupported:
                    ContentUnavailableView {
                        Label(String(localized: "Scanning Isn't Available"), systemImage: "barcode.viewfinder")
                    } description: {
                        Text("This device can't scan barcodes. Adding an item by hand takes a few seconds.")
                    }

                case .failed(let message):
                    ContentUnavailableView {
                        Label(String(localized: "Couldn't Start the Camera"), systemImage: "exclamationmark.triangle")
                    } description: {
                        Text(message)
                    } actions: {
                        Button(String(localized: "Try Again")) { state = .scanning }
                            .buttonStyle(.bordered)
                    }
                }
            }
            .navigationTitle(Text("Scan Barcode"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "Cancel")) { dismiss() }
                }
            }
            .task { await prepare() }
            .sheet(item: Binding(
                get: { scannedCode.map(ScannedCode.init(value:)) },
                set: { if $0 == nil { scannedCode = nil } }
            )) { code in
                AddItemFromBarcodeView(barcode: code.value) { dismiss() }
            }
        }
    }

    private func prepare() async {
        guard BarcodeScannerView.isSupported else {
            state = .unsupported
            return
        }
        switch CameraPermission.status {
        case .authorized:
            state = .scanning
        case .notDetermined:
            state = await CameraPermission.request() ? .scanning : .denied
        default:
            state = .denied
        }
    }

    private struct ScannedCode: Identifiable {
        var value: String
        var id: String { value }
    }
}

/// Wraps the add form so a scan lands somewhere useful with the code already filled in.
private struct AddItemFromBarcodeView: View {
    var barcode: String
    var onFinish: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @State private var name = ""
    @State private var quantity: Double = 1
    @State private var unit: MeasurementUnit = .piece
    @FocusState private var isNameFocused: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(String(localized: "Name"), text: $name)
                        .focused($isNameFocused)
                        .textInputAutocapitalization(.words)
                    QuantityStepper(quantity: $quantity, unit: unit, title: String(localized: "Quantity"))
                    Picker(String(localized: "Unit"), selection: $unit) {
                        ForEach(MeasurementUnit.allCases) { option in
                            Text(option.name).tag(option)
                        }
                    }
                } header: {
                    Text("Scanned")
                } footer: {
                    Text("Barcode \(barcode). Pantry doesn't look products up online, so give it a name you'll recognise.")
                }
            }
            .navigationTitle(Text("Add Item"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "Cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "Add")) {
                        let category = CategoryGuesser.category(for: name)
                        let item = PantryItem(
                            name: name.trimmingCharacters(in: .whitespaces),
                            category: category,
                            quantity: quantity,
                            unit: unit,
                            expirationDate: ExpirationCalculator.suggestedExpiration(for: category),
                            barcode: barcode
                        )
                        InventoryService(context: modelContext).add(item)
                        dismiss()
                        onFinish()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear { isNameFocused = true }
        }
    }
}
