import AppKit
import AVFoundation
import CoreImage
import SwiftUI
import Combine

final class CameraManager: NSObject, ObservableObject {
    static let shared = CameraManager()
    
    @Published var frame: CGImage?
    @Published var permissionGranted = false
    /// True once the user has refused (or MDM restricts) camera access, so
    /// the UI can explain instead of spinning forever.
    @Published private(set) var permissionDenied = false
    
    private let captureSession = AVCaptureSession()
    private let videoOutput = AVCaptureVideoDataOutput()
    private let context = CIContext()
    /// Serial queue for start/stop so they always apply in call order —
    /// `startRunning()` blocks and must stay off the main thread.
    private let sessionQueue = DispatchQueue(label: "notchify.camera.session")
    private let videoQueue = DispatchQueue(label: "notchify.camera.video")
    
    private var isConfigured = false
    /// What the UI last asked for. This (not the session's async state) is
    /// the source of truth, so a stop() issued while the permission prompt
    /// or session startup is still in flight is never lost.
    private var wantsRunning = false
    
    private override init() {
        super.init()
    }
    
    func start() {
        guard !wantsRunning else { return }
        wantsRunning = true
        
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            permissionGranted = true
            permissionDenied = false
            startSession()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                DispatchQueue.main.async {
                    guard let self else { return }
                    self.permissionGranted = granted
                    self.permissionDenied = !granted
                    if granted && self.wantsRunning {
                        self.startSession()
                    }
                }
            }
        default:
            permissionGranted = false
            permissionDenied = true
        }
    }
    
    func stop() {
        guard wantsRunning else { return }
        wantsRunning = false
        frame = nil
        let session = captureSession
        sessionQueue.async {
            if session.isRunning {
                session.stopRunning()
            }
        }
    }
    
    /// Opens the Camera pane of Privacy & Security so a user who denied
    /// access can turn it back on.
    func openPrivacySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera") {
            NSWorkspace.shared.open(url)
        }
    }
    
    private func startSession() {
        configureIfNeeded()
        let session = captureSession
        sessionQueue.async {
            if !session.isRunning {
                session.startRunning()
            }
        }
    }
    
    /// Inputs and outputs are added once; re-adding on every start() left
    /// the session in a half-configured state after the first stop.
    private func configureIfNeeded() {
        guard !isConfigured else { return }
        
        captureSession.beginConfiguration()
        defer { captureSession.commitConfiguration() }
        captureSession.sessionPreset = .low
        
        guard let videoDevice = AVCaptureDevice.default(for: .video) else { return }
        
        do {
            let videoDeviceInput = try AVCaptureDeviceInput(device: videoDevice)
            guard captureSession.canAddInput(videoDeviceInput) else { return }
            captureSession.addInput(videoDeviceInput)
        } catch {
            print("Could not create video device input: \(error)")
            return
        }
        
        guard captureSession.canAddOutput(videoOutput) else { return }
        videoOutput.alwaysDiscardsLateVideoFrames = true
        videoOutput.setSampleBufferDelegate(self, queue: videoQueue)
        captureSession.addOutput(videoOutput)
        isConfigured = true
    }
}

extension CameraManager: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        if let cgImage = context.createCGImage(ciImage, from: ciImage.extent) {
            DispatchQueue.main.async {
                // Drop frames that were in flight when the mirror was turned off.
                guard self.wantsRunning else { return }
                self.frame = cgImage
            }
        }
    }
}
