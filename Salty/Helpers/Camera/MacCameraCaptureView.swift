//
//  MacCameraCaptureView.swift
//  Salty
//
//  The macOS camera sheet: a live preview with Capture and Cancel, handing back a `CGImage`. One
//  implementation for the image importer and the recipe photo editor, which used to carry two
//  near-identical copies of all of this.
//

#if os(macOS)
import SwiftUI
import AppKit
import AVFoundation
import OSLog

/// Presents the camera; a captured frame is written to `capturedImage` and the sheet dismissed.
struct MacCameraCaptureView: NSViewControllerRepresentable {
    @Binding var capturedImage: CGImage?
    @Environment(\.dismiss) private var dismiss

    func makeNSViewController(context: Context) -> NSViewController {
        let controller = MacCameraCaptureViewController()
        controller.delegate = context.coordinator
        return controller
    }

    func updateNSViewController(_ nsViewController: NSViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    final class Coordinator: MacCameraCaptureDelegate {
        private let parent: MacCameraCaptureView

        init(_ parent: MacCameraCaptureView) {
            self.parent = parent
        }

        func cameraCapture(didCapture image: CGImage) {
            parent.capturedImage = image
            parent.dismiss()
        }

        func cameraCaptureDidCancel() {
            parent.dismiss()
        }
    }
}

@MainActor
protocol MacCameraCaptureDelegate: AnyObject {
    func cameraCapture(didCapture image: CGImage)
    func cameraCaptureDidCancel()
}

/// Starts and stops an `AVCaptureSession` off the main thread, in order.
///
/// `startRunning` and `stopRunning` block for hundreds of milliseconds, so Apple's guidance is to call
/// them off the main thread. An actor queues the calls, so a quick appear-then-disappear can't run
/// the stop before the start and leave the camera on, its indicator lit, with nothing showing it --
/// which a concurrent dispatch queue allowed. The session is documented thread-safe for these two
/// calls, and they are all this actor does with it.
actor CaptureSessionRunner {
    private let box: CaptureSessionBox

    init(_ box: CaptureSessionBox) {
        self.box = box
    }

    func start() {
        if !box.session.isRunning {
            box.session.startRunning()
        }
    }

    func stop() {
        if box.session.isRunning {
            box.session.stopRunning()
        }
    }
}

/// `AVCaptureSession` is not `Sendable`, and the controller keeps using the session on the main actor
/// (the preview layer, the photo output) after handing it to the runner, which the compiler's region
/// checking rightly refuses for a bare reference. The box asserts what Apple documents instead: the
/// two calls the runner makes may be made from any thread.
final class CaptureSessionBox: @unchecked Sendable {
    let session: AVCaptureSession

    init(_ session: AVCaptureSession) {
        self.session = session
    }
}

final class MacCameraCaptureViewController: NSViewController {
    private let logger = Logger(subsystem: "Salty", category: "Camera")
    weak var delegate: MacCameraCaptureDelegate?

    private var captureSession: AVCaptureSession?
    private var runner: CaptureSessionRunner?
    private var previewLayer: AVCaptureVideoPreviewLayer?
    private var photoOutput: AVCapturePhotoOutput?
    /// Whether the view is on screen, so a session that finishes setting up after `viewWillAppear`
    /// still starts.
    private var isVisible = false

    private let statusLabel = NSTextField(wrappingLabelWithString: "")
    private var captureButton: NSButton?

    private enum SetupError: Error {
        case inputRefused
        case outputRefused
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        Task { await prepareCamera() }
    }

    override func viewWillAppear() {
        super.viewWillAppear()
        isVisible = true
        if let runner {
            Task { await runner.start() }
        }
    }

    override func viewWillDisappear() {
        super.viewWillDisappear()
        isVisible = false
        if let runner {
            Task { await runner.stop() }
        }
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        previewLayer?.frame = view.bounds
    }

    /// Asks for camera access, then builds the session. A denied, missing or failing camera is said
    /// so on the sheet; before, it left a black preview whose Capture button silently did nothing.
    private func prepareCamera() async {
        guard await AVCaptureDevice.requestAccess(for: .video) else {
            showStatus("Salty doesn't have permission to use the camera. Allow it in System Settings › Privacy & Security › Camera.")
            return
        }
        guard let camera = AVCaptureDevice.default(for: .video) else {
            showStatus("No camera is available on this Mac.")
            return
        }

        let session = AVCaptureSession()
        session.sessionPreset = .photo
        let output = AVCapturePhotoOutput()
        do {
            let input = try AVCaptureDeviceInput(device: camera)
            guard session.canAddInput(input) else { throw SetupError.inputRefused }
            session.addInput(input)
            guard session.canAddOutput(output) else { throw SetupError.outputRefused }
            session.addOutput(output)
        } catch {
            logger.error("Error setting up camera: \(error)")
            showStatus("The camera couldn't be started.")
            return
        }

        let preview = AVCaptureVideoPreviewLayer(session: session)
        preview.videoGravity = .resizeAspectFill
        preview.frame = view.bounds
        view.layer?.insertSublayer(preview, at: 0)

        captureSession = session
        photoOutput = output
        previewLayer = preview
        statusLabel.isHidden = true
        captureButton?.isEnabled = true

        let runner = CaptureSessionRunner(CaptureSessionBox(session))
        self.runner = runner
        if isVisible {
            await runner.start()
        }
    }

    private func showStatus(_ message: String) {
        statusLabel.stringValue = message
        statusLabel.isHidden = false
        captureButton?.isEnabled = false
    }

    private func setupUI() {
        view.wantsLayer = true

        // Set a minimum size for the view
        view.frame = NSRect(x: 0, y: 0, width: 600, height: 500)

        // Where the camera's state is explained while there is no preview to show.
        statusLabel.alignment = .center
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        statusLabel.isHidden = true
        view.addSubview(statusLabel)

        // Create a semi-transparent background for buttons
        let buttonBackground = NSView()
        buttonBackground.wantsLayer = true
        buttonBackground.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.6).cgColor
        buttonBackground.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(buttonBackground)

        // Create capture button; enabled once the camera is running
        let captureButton = NSButton(title: "Capture", target: self, action: #selector(capturePhoto))
        captureButton.bezelStyle = .push
        captureButton.keyEquivalent = "\r"
        captureButton.isEnabled = false
        captureButton.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(captureButton)
        self.captureButton = captureButton

        // Create cancel button
        let cancelButton = NSButton(title: "Cancel", target: self, action: #selector(cancelCapture))
        cancelButton.bezelStyle = .push
        cancelButton.keyEquivalent = "\u{1b}"
        cancelButton.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(cancelButton)

        // Layout constraints
        NSLayoutConstraint.activate([
            // Status text
            statusLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            statusLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            statusLabel.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 40),
            statusLabel.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -40),

            // Button background
            buttonBackground.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            buttonBackground.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            buttonBackground.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            buttonBackground.heightAnchor.constraint(equalToConstant: 80),

            // Capture button
            captureButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            captureButton.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -20),
            captureButton.widthAnchor.constraint(equalToConstant: 120),
            captureButton.heightAnchor.constraint(equalToConstant: 32),

            // Cancel button
            cancelButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            cancelButton.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -20),
            cancelButton.widthAnchor.constraint(equalToConstant: 100),
            cancelButton.heightAnchor.constraint(equalToConstant: 32),
        ])
    }

    @objc private func capturePhoto() {
        guard let photoOutput else { return }
        photoOutput.capturePhoto(with: AVCapturePhotoSettings(), delegate: self)
    }

    @objc private func cancelCapture() {
        delegate?.cameraCaptureDidCancel()
    }
}

// MARK: - AVCapturePhotoCaptureDelegate

extension MacCameraCaptureViewController: AVCapturePhotoCaptureDelegate {
    // AVFoundation invokes this on a background queue, so it must be nonisolated; the photo is decoded
    // here and the (main-actor) delegate told on the main actor.
    nonisolated func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        if let error {
            logger.error("Error capturing photo: \(error)")
            return
        }

        guard let imageData = photo.fileDataRepresentation(),
              let image = NSImage(data: imageData),
              let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            logger.error("Failed to create CGImage from photo")
            return
        }

        Task { @MainActor [weak self] in
            guard let self else { return }
            delegate?.cameraCapture(didCapture: cgImage)
        }
    }
}
#endif
