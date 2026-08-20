@preconcurrency import ARKit
import AVFoundation
import CoreLocation
import Foundation
import SwiftUI

@MainActor
final class ARCameraSessionAdapter: NSObject, CameraObservationProvider {
    let session = ARSession()

    private let headingManager = CLLocationManager()
    private let tuning: CandidateTuning
    private var continuation: AsyncStream<CameraPoseObservation>.Continuation?
    private var headingObservation: (degrees: Double, accuracy: Double, observedAt: Date)?
    private var lastEmissionTime: TimeInterval = 0

    init(tuning: CandidateTuning = .default) {
        self.tuning = tuning
        super.init()
        headingManager.delegate = self
        headingManager.headingFilter = 1
        headingManager.headingOrientation = .portrait
    }

    func start() async -> Result<Void, CameraSessionFailure> {
        guard ARWorldTrackingConfiguration.isSupported else {
            return .failure(.unsupported)
        }

        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            break
        case .notDetermined:
            guard await AVCaptureDevice.requestAccess(for: .video) else {
                return .failure(.denied)
            }
        case .denied:
            return .failure(.denied)
        case .restricted:
            return .failure(.restricted)
        @unknown default:
            return .failure(.unavailable)
        }

        guard CLLocationManager.headingAvailable() else {
            return .failure(.unsupported)
        }

        let configuration = ARWorldTrackingConfiguration()
        configuration.worldAlignment = .gravityAndHeading
        session.run(configuration, options: [.resetTracking, .removeExistingAnchors])
        headingManager.startUpdatingHeading()
        return .success(())
    }

    func observations() -> AsyncStream<CameraPoseObservation> {
        AsyncStream { continuation in
            self.continuation?.finish()
            self.continuation = continuation
        }
    }

    func stop() {
        session.pause()
        headingManager.stopUpdatingHeading()
        continuation?.finish()
        continuation = nil
        headingObservation = nil
        lastEmissionTime = 0
    }
}

extension ARCameraSessionAdapter: CLLocationManagerDelegate {
    func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        guard newHeading.trueHeading >= 0, newHeading.headingAccuracy >= 0 else {
            headingObservation = nil
            return
        }
        headingObservation = (
            degrees: newHeading.trueHeading,
            accuracy: newHeading.headingAccuracy,
            observedAt: newHeading.timestamp
        )
    }
}

extension ARCameraSessionAdapter {
    nonisolated func process(frame: ARFrame) {
        let transform = frame.camera.transform
        let forwardY = Double(-transform.columns.2.y)
        let pitch = asin(min(max(forwardY, -1), 1)) * 180 / .pi
        let trackingQuality = trackingQuality(for: frame.camera.trackingState)
        let timestamp = frame.timestamp

        Task { @MainActor [weak self] in
            guard let self, timestamp - lastEmissionTime >= 0.1 else { return }
            lastEmissionTime = timestamp
            guard let headingObservation else { return }
            let headingAge = Date.now.timeIntervalSince(headingObservation.observedAt)
            guard headingAge >= -1, headingAge <= tuning.maximumPoseAgeSeconds else { return }
            continuation?.yield(
                CameraPoseObservation(
                    trueBearingDegrees: headingObservation.degrees,
                    pitchDegrees: pitch,
                    headingAccuracyDegrees: headingObservation.accuracy,
                    observedAt: headingObservation.observedAt,
                    trackingQuality: trackingQuality
                )
            )
        }
    }

    private nonisolated func trackingQuality(
        for state: ARCamera.TrackingState
    ) -> CameraTrackingQuality {
        switch state {
        case .normal:
            return .normal
        case .limited:
            return .limited
        case .notAvailable:
            return .unavailable
        }
    }
}

struct ARCameraPreview: UIViewRepresentable {
    let adapter: ARCameraSessionAdapter

    func makeCoordinator() -> Coordinator {
        Coordinator(adapter: adapter)
    }

    func makeUIView(context: Context) -> ARSCNView {
        let view = ARSCNView(frame: .zero)
        view.session = adapter.session
        view.automaticallyUpdatesLighting = false
        context.coordinator.start()
        return view
    }

    func updateUIView(_ uiView: ARSCNView, context: Context) {
        if uiView.session !== adapter.session {
            uiView.session = adapter.session
        }
    }

    static func dismantleUIView(_ uiView: ARSCNView, coordinator: Coordinator) {
        coordinator.stop()
    }

    final class Coordinator: NSObject {
        private let adapter: ARCameraSessionAdapter
        private var displayLink: CADisplayLink?

        init(adapter: ARCameraSessionAdapter) {
            self.adapter = adapter
        }

        func start() {
            guard displayLink == nil else { return }
            let displayLink = CADisplayLink(target: self, selector: #selector(updateFrame))
            displayLink.preferredFrameRateRange = CAFrameRateRange(minimum: 10, maximum: 10, preferred: 10)
            displayLink.add(to: .main, forMode: .common)
            self.displayLink = displayLink
        }

        func stop() {
            displayLink?.invalidate()
            displayLink = nil
        }

        @objc private func updateFrame() {
            guard let frame = adapter.session.currentFrame else { return }
            adapter.process(frame: frame)
        }
    }
}
