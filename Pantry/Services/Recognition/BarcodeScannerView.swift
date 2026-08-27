import SwiftUI
import AVFoundation
import VisionKit

/// The camera-based barcode scanner, wrapped from VisionKit.
///
/// Barcode scanning is a shortcut, never a dependency: if the camera is unavailable,
/// permission is declined, or the device doesn't support live scanning, the user is
/// pointed at typing the item instead and nothing is blocked.
struct BarcodeScannerView: UIViewControllerRepresentable {

    var onScan: (String) -> Void
    var onFailure: (String) -> Void

    static var isSupported: Bool {
        DataScannerViewController.isSupported && DataScannerViewController.isAvailable
    }

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let controller = DataScannerViewController(
            recognizedDataTypes: [.barcode()],
            qualityLevel: .balanced,
            recognizesMultipleItems: false,
            isHighFrameRateTrackingEnabled: false,
            isHighlightingEnabled: true
        )
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: DataScannerViewController, context: Context) {
        guard !context.coordinator.isScanning else { return }
        do {
            try controller.startScanning()
            context.coordinator.isScanning = true
        } catch {
            onFailure(error.localizedDescription)
        }
    }

    static func dismantleUIViewController(_ controller: DataScannerViewController, coordinator: Coordinator) {
        controller.stopScanning()
        coordinator.isScanning = false
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onScan: onScan)
    }

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        var isScanning = false
        private var hasReported = false
        private let onScan: (String) -> Void

        init(onScan: @escaping (String) -> Void) {
            self.onScan = onScan
        }

        func dataScanner(_ scanner: DataScannerViewController, didAdd addedItems: [RecognizedItem], allItems: [RecognizedItem]) {
            report(addedItems)
        }

        func dataScanner(_ scanner: DataScannerViewController, didTapOn item: RecognizedItem) {
            report([item])
        }

        private func report(_ items: [RecognizedItem]) {
            guard !hasReported else { return }
            for item in items {
                if case .barcode(let barcode) = item, let payload = barcode.payloadStringValue {
                    hasReported = true
                    onScan(payload)
                    return
                }
            }
        }
    }
}

/// Camera permission, asked for at the moment the user taps Scan rather than up front.
enum CameraPermission {
    static var status: AVAuthorizationStatus {
        AVCaptureDevice.authorizationStatus(for: .video)
    }

    static func request() async -> Bool {
        await AVCaptureDevice.requestAccess(for: .video)
    }
}
