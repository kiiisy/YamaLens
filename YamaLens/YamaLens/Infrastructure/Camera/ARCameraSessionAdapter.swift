@preconcurrency import ARKit
import AVFoundation
import CoreLocation
import Foundation
import simd
import SwiftUI

@MainActor
final class ARCameraSessionAdapter: NSObject, CameraObservationProvider {
    let session = ARSession()

    private let headingManager = CLLocationManager()
    private let tuning: CandidateTuning
    private let diagnosticVideoRecorder: ARCameraDiagnosticVideoRecorder?
    private var continuation: AsyncStream<CameraObservationUpdate>.Continuation?
    private var headingObservation: (degrees: Double, accuracy: Double, observedAt: Date)?
    private var isHeadingRecoveryPending = false
    private var lastEmissionTime: TimeInterval = 0

    init(
        tuning: CandidateTuning = .default,
        diagnosticVideoRecorder: ARCameraDiagnosticVideoRecorder? = nil
    ) {
        self.tuning = tuning
        self.diagnosticVideoRecorder = diagnosticVideoRecorder
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

        runAlignedSession()
        isHeadingRecoveryPending = false
        headingManager.startUpdatingHeading()
        return .success(())
    }

    func observations() -> AsyncStream<CameraObservationUpdate> {
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
        isHeadingRecoveryPending = false
        lastEmissionTime = 0
    }
}

extension ARCameraSessionAdapter: CLLocationManagerDelegate {
    func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        guard
            newHeading.trueHeading >= 0,
            newHeading.headingAccuracy >= 0,
            newHeading.headingAccuracy <= tuning.maximumHeadingAccuracyDegrees
        else {
            headingObservation = nil
            isHeadingRecoveryPending = true
            return
        }
        headingObservation = (
            degrees: newHeading.trueHeading,
            accuracy: newHeading.headingAccuracy,
            observedAt: newHeading.timestamp
        )
        if isHeadingRecoveryPending {
            isHeadingRecoveryPending = false
            runAlignedSession()
        }
    }
}

extension ARCameraSessionAdapter {
    private func runAlignedSession() {
        let configuration = ARWorldTrackingConfiguration()
        configuration.worldAlignment = .gravityAndHeading
        session.run(configuration, options: [.resetTracking, .removeExistingAnchors])
    }

    nonisolated func process(
        frame: ARFrame,
        viewportSize: CGSize,
        interfaceOrientation: UIInterfaceOrientation
    ) {
        let transform = frame.camera.transform
        let forwardY = Double(-transform.columns.2.y)
        let pitch = asin(min(max(forwardY, -1), 1)) * 180 / .pi
        let trackingQuality = trackingQuality(for: frame.camera.trackingState)
        let timestamp = frame.timestamp
        let projectionGeometry = projectionGeometry(
            frame: frame,
            viewportSize: viewportSize,
            interfaceOrientation: interfaceOrientation
        )

        Task { @MainActor [weak self] in
            guard let self, timestamp - lastEmissionTime >= 0.1 else { return }
            diagnosticVideoRecorder?.receive(frame: frame)
            lastEmissionTime = timestamp
            headingManager.headingOrientation = headingOrientation(for: interfaceOrientation)
            guard let headingObservation else {
                continuation?.yield(.temporarilyUnavailable)
                return
            }
            let headingAge = Date.now.timeIntervalSince(headingObservation.observedAt)
            guard
                headingAge >= -1,
                headingAge <= tuning.maximumPoseAgeSeconds,
                let projectionGeometry
            else {
                continuation?.yield(.temporarilyUnavailable)
                return
            }
            continuation?.yield(.pose(
                CameraPoseObservation(
                    trueBearingDegrees: headingObservation.degrees,
                    pitchDegrees: pitch,
                    headingAccuracyDegrees: headingObservation.accuracy,
                    observedAt: headingObservation.observedAt,
                    trackingQuality: trackingQuality,
                    projectionGeometry: projectionGeometry
                )
            ))
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

    private nonisolated func projectionGeometry(
        frame: ARFrame,
        viewportSize: CGSize,
        interfaceOrientation: UIInterfaceOrientation
    ) -> CameraProjectionGeometry? {
        guard viewportSize.width > 0, viewportSize.height > 0 else { return nil }

        let camera = frame.camera
        let transform = camera.transform
        let intrinsics = camera.intrinsics
        let resolution = camera.imageResolution
        let displayTransform = frame.displayTransform(
            for: interfaceOrientation,
            viewportSize: viewportSize
        )
        let fieldOfView = effectiveFieldOfView(
            intrinsics: intrinsics,
            resolution: resolution,
            viewportSize: viewportSize,
            interfaceOrientation: interfaceOrientation
        )

        return CameraProjectionGeometry(
            cameraRightInWorld: SpatialVector(
                x: Double(transform.columns.0.x),
                y: Double(transform.columns.0.y),
                z: Double(transform.columns.0.z)
            ),
            cameraUpInWorld: SpatialVector(
                x: Double(transform.columns.1.x),
                y: Double(transform.columns.1.y),
                z: Double(transform.columns.1.z)
            ),
            cameraBackInWorld: SpatialVector(
                x: Double(transform.columns.2.x),
                y: Double(transform.columns.2.y),
                z: Double(transform.columns.2.z)
            ),
            focalLengthXPixels: Double(intrinsics.columns.0.x),
            focalLengthYPixels: Double(intrinsics.columns.1.y),
            principalPointXPixels: Double(intrinsics.columns.2.x),
            principalPointYPixels: Double(intrinsics.columns.2.y),
            imageSizePixels: ViewportSize(
                width: Double(resolution.width),
                height: Double(resolution.height)
            ),
            normalizedImageToViewport: NormalizedImageTransform(
                a: Double(displayTransform.a),
                b: Double(displayTransform.b),
                c: Double(displayTransform.c),
                d: Double(displayTransform.d),
                translationX: Double(displayTransform.tx),
                translationY: Double(displayTransform.ty)
            ),
            viewportSizePoints: ViewportSize(
                width: Double(viewportSize.width),
                height: Double(viewportSize.height)
            ),
            horizontalFieldOfViewDegrees: fieldOfView.horizontal,
            verticalFieldOfViewDegrees: fieldOfView.vertical
        )
    }

    private nonisolated func effectiveFieldOfView(
        intrinsics: simd_float3x3,
        resolution: CGSize,
        viewportSize: CGSize,
        interfaceOrientation: UIInterfaceOrientation
    ) -> (horizontal: Double, vertical: Double) {
        let nativeHorizontal = 2 * atan(
            Double(resolution.width) / (2 * Double(intrinsics.columns.0.x))
        )
        let nativeVertical = 2 * atan(
            Double(resolution.height) / (2 * Double(intrinsics.columns.1.y))
        )
        let isPortrait = interfaceOrientation == .portrait
            || interfaceOrientation == .portraitUpsideDown
        var horizontal = isPortrait ? nativeVertical : nativeHorizontal
        var vertical = isPortrait ? nativeHorizontal : nativeVertical
        let sourceAspect = isPortrait
            ? Double(resolution.height / resolution.width)
            : Double(resolution.width / resolution.height)
        let viewportAspect = Double(viewportSize.width / viewportSize.height)

        if viewportAspect < sourceAspect {
            horizontal = 2 * atan(tan(horizontal / 2) * viewportAspect / sourceAspect)
        } else if viewportAspect > sourceAspect {
            vertical = 2 * atan(tan(vertical / 2) * sourceAspect / viewportAspect)
        }
        return (horizontal * 180 / .pi, vertical * 180 / .pi)
    }

    private func headingOrientation(
        for interfaceOrientation: UIInterfaceOrientation
    ) -> CLDeviceOrientation {
        switch interfaceOrientation {
        case .portrait:
            return .portrait
        case .portraitUpsideDown:
            return .portraitUpsideDown
        case .landscapeLeft:
            return .landscapeLeft
        case .landscapeRight:
            return .landscapeRight
        default:
            return .portrait
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
        context.coordinator.start(view: view)
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
        private weak var view: ARSCNView?
        private var displayLink: CADisplayLink?

        init(adapter: ARCameraSessionAdapter) {
            self.adapter = adapter
        }

        func start(view: ARSCNView) {
            guard displayLink == nil else { return }
            self.view = view
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
            guard
                let view,
                let frame = adapter.session.currentFrame
            else {
                return
            }
            let orientation = view.window?.windowScene?.effectiveGeometry.interfaceOrientation
                ?? .portrait
            adapter.process(
                frame: frame,
                viewportSize: view.bounds.size,
                interfaceOrientation: orientation
            )
        }
    }
}
