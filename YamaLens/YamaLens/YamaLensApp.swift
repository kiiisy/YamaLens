//
//  YamaLensApp.swift
//  YamaLens
//
//  Created by kisaya on 2026/08/19.
//

import SwiftData
import SwiftUI

@main
struct YamaLensApp: App {
    @UIApplicationDelegateAdaptor(YamaLensAppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            YamaLensRootView(
                repository: appDelegate.appContainer.mountainRepository,
                cameraMountains: appDelegate.appContainer.cameraMountains,
                pointOfInterestRepository: appDelegate.appContainer.mountainPointOfInterestRepository,
                locationObservationProvider: appDelegate.appContainer.locationObservationProvider,
                proximityCalculator: appDelegate.appContainer.proximityCalculator,
                cameraObservationProvider: appDelegate.appContainer.cameraObservationProvider,
                cameraPreview: appDelegate.appContainer.cameraPreview,
                cameraDiagnosticLogRepository: appDelegate.appContainer.cameraDiagnosticLogRepository,
                cameraDiagnosticDevice: appDelegate.appContainer.cameraDiagnosticDevice,
                terrainVisibilityResolver: appDelegate.appContainer.terrainVisibilityResolver,
                terrainHorizonResolver: appDelegate.appContainer.terrainHorizonResolver,
                terrainPackageCoverages: appDelegate.appContainer.terrainPackageCoverages,
                offlinePackageManager: appDelegate.appContainer.offlinePackageManager,
                offlinePackagePresentation: appDelegate.appContainer.offlinePackagePresentation,
                mountainWeatherRepository: appDelegate.appContainer.mountainWeatherRepository
            )
                .modelContainer(for: UserMountainRecord.self)
        }
    }
}

struct MountainDetailPresentation: Identifiable, Equatable {
    enum Origin: Equatable {
        case browsing
        case camera
    }

    let mountain: Mountain
    let sourceID: String
    let sourceArtworkFrame: CGRect
    let origin: Origin

    init(
        mountain: Mountain,
        sourceID: String,
        sourceArtworkFrame: CGRect,
        origin: Origin = .browsing
    ) {
        self.mountain = mountain
        self.sourceID = sourceID
        self.sourceArtworkFrame = sourceArtworkFrame
        self.origin = origin
    }

    var id: String { sourceID }
}

private struct YamaLensRootView: View {
    let repository: any MountainRepository
    let cameraMountains: [Mountain]
    let pointOfInterestRepository: any MountainPointOfInterestRepository
    let proximityCalculator: MountainProximityCalculator
    let cameraPreview: AnyView
    let cameraDiagnosticLogRepository: (any CameraDiagnosticLogRepository)?
    let cameraProjector: MountainCameraProjector
    let mountainWeatherRepository: any MountainWeatherRepository
    let offlinePackagePresentation: OfflinePackagePresentation
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var selectedTab: YamaTab = .home
    @State private var detailPresentation: MountainDetailPresentation?
    @State private var detailTransitionProgress: CGFloat = 1
    @State private var locationModel: LocationSessionModel
    @State private var cameraModel: CameraScreenModel
    @State private var offlinePackageModel: OfflinePackageScreenModel
    @AppStorage("camera.showsTerrainHorizon") private var showsTerrainHorizon = true

    init(
        repository: any MountainRepository,
        cameraMountains: [Mountain],
        pointOfInterestRepository: any MountainPointOfInterestRepository,
        locationObservationProvider: any LocationObservationProvider,
        proximityCalculator: MountainProximityCalculator,
        cameraObservationProvider: any CameraObservationProvider,
        cameraPreview: AnyView,
        cameraDiagnosticLogRepository: (any CameraDiagnosticLogRepository)?,
        cameraDiagnosticDevice: CameraDiagnosticDevice?,
        terrainVisibilityResolver: (any TerrainVisibilityResolving)?,
        terrainHorizonResolver: (any TerrainHorizonResolving)?,
        terrainPackageCoverages: [TerrainPackageCoverage],
        offlinePackageManager: any OfflinePackageManaging,
        offlinePackagePresentation: OfflinePackagePresentation,
        mountainWeatherRepository: any MountainWeatherRepository
    ) {
        self.repository = repository
        self.cameraMountains = cameraMountains
        self.pointOfInterestRepository = pointOfInterestRepository
        self.proximityCalculator = proximityCalculator
        self.cameraPreview = cameraPreview
        self.mountainWeatherRepository = mountainWeatherRepository
        self.offlinePackagePresentation = offlinePackagePresentation
        _locationModel = State(
            initialValue: LocationSessionModel(
                provider: locationObservationProvider,
                proximityCalculator: proximityCalculator
            )
        )
        let projector = MountainCameraProjector(
            proximityCalculator: proximityCalculator
        )
        let diagnosticRecorder: CameraDiagnosticRecorder?
        if let cameraDiagnosticLogRepository, let cameraDiagnosticDevice {
            diagnosticRecorder = CameraDiagnosticRecorder(
                repository: cameraDiagnosticLogRepository,
                device: cameraDiagnosticDevice
            )
        } else {
            diagnosticRecorder = nil
        }
        _cameraModel = State(
            initialValue: CameraScreenModel(
                provider: cameraObservationProvider,
                mountains: cameraMountains,
                projector: projector,
                terrainVisibilityResolver: terrainVisibilityResolver,
                terrainHorizonResolver: terrainHorizonResolver,
                terrainPackageCoverages: terrainPackageCoverages,
                diagnosticRecorder: diagnosticRecorder
            )
        )
        _offlinePackageModel = State(
            initialValue: OfflinePackageScreenModel(manager: offlinePackageManager)
        )
        self.cameraDiagnosticLogRepository = cameraDiagnosticLogRepository
        self.cameraProjector = projector
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                TabView(selection: $selectedTab) {
                    HomeView(
                        repository: repository,
                        pointOfInterestRepository: pointOfInterestRepository,
                        mountainWeatherRepository: mountainWeatherRepository,
                        locationModel: locationModel,
                        proximityCalculator: proximityCalculator
                    ) { presentation in
                        openDetail(presentation)
                    }
                    .tabItem {
                        Image(systemName: "mountain.2")
                            .accessibilityLabel("ホーム")
                    }
                    .tag(YamaTab.home)

                    CameraView(
                        selectedTab: $selectedTab,
                        showsTerrainHorizon: $showsTerrainHorizon,
                        model: cameraModel,
                        locationModel: locationModel,
                        preview: cameraPreview,
                        dataContextTitle: offlinePackagePresentation.cameraContextTitle
                    ) { mountain in
                        openDetail(
                            MountainDetailPresentation(
                                mountain: mountain,
                                sourceID: "camera-\(mountain.id)",
                                sourceArtworkFrame: .zero,
                                origin: .camera
                            )
                        )
                    }
                        .tabItem {
                            Image(systemName: "camera.viewfinder")
                                .accessibilityLabel("カメラ")
                        }
                        .tag(YamaTab.camera)

                    MyView(
                        repository: repository,
                        pointOfInterestRepository: pointOfInterestRepository,
                        mountainWeatherRepository: mountainWeatherRepository,
                        showsTerrainHorizon: $showsTerrainHorizon,
                        diagnosticLogRepository: cameraDiagnosticLogRepository,
                        cameraProjector: cameraProjector,
                        offlinePackageModel: offlinePackageModel,
                        offlinePackagePresentation: offlinePackagePresentation
                    )
                        .tabItem {
                            Image(systemName: "person.crop.circle")
                                .accessibilityLabel("マイ")
                        }
                        .tag(YamaTab.my)
                }
                .tint(YamaColor.forest)

                if let detailPresentation {
                    let containerFrame = geometry.frame(in: .global)
                    let artworkFrame = transitionArtworkFrame(
                        presentation: detailPresentation,
                        containerFrame: containerFrame,
                        topInset: geometry.safeAreaInsets.top
                    )

                    MountainDetailView(
                        mountain: detailPresentation.mountain,
                        weatherRepository: mountainWeatherRepository,
                        pointOfInterestRepository: pointOfInterestRepository,
                        currentLocationState: locationModel.state,
                        proximityCalculator: proximityCalculator,
                        overlayTopInset: geometry.safeAreaInsets.top
                    ) { style in
                        closeDetail(style: style)
                    }
                    .opacity(detailContentOpacity)
                    .zIndex(1)

                    transitionArtwork(
                        mountain: detailPresentation.mountain,
                        frame: artworkFrame,
                        containerFrame: containerFrame
                    )
                    .zIndex(2)
                    .task(id: detailPresentation.id) {
                        guard !reduceMotion, detailTransitionProgress < 1 else { return }
                        await Task.yield()
                        withAnimation(.spring(response: 0.42, dampingFraction: 0.88)) {
                            detailTransitionProgress = 1
                        }
                    }
                }
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase == .active else { return }
            Task { await locationModel.refreshAfterReturningFromSettings() }
        }
        .task {
            await offlinePackageModel.load()
        }
    }

    private var detailContentOpacity: CGFloat {
        guard !reduceMotion else { return 1 }
        return min(max((detailTransitionProgress - 0.35) / 0.5, 0), 1)
    }

    private var transitionArtworkOpacity: CGFloat {
        guard !reduceMotion else { return 0 }
        return min(max((1 - detailTransitionProgress) / 0.15, 0), 1)
    }

    private func openDetail(_ presentation: MountainDetailPresentation) {
        detailTransitionProgress = reduceMotion ? 1 : 0
        detailPresentation = presentation
    }

    private func closeDetail(style: MountainDetailDismissalStyle) {
        let shouldResumeCamera = detailPresentation?.origin == .camera
            && selectedTab == .camera

        switch style {
        case .zoomToSource:
            if reduceMotion {
                detailPresentation = nil
                resumeCameraIfNeeded(shouldResumeCamera)
            } else {
                withAnimation(.spring(response: 0.42, dampingFraction: 0.88)) {
                    detailTransitionProgress = 0
                } completion: {
                    detailPresentation = nil
                    detailTransitionProgress = 1
                    resumeCameraIfNeeded(shouldResumeCamera)
                }
            }
        case .dragged:
            detailPresentation = nil
            detailTransitionProgress = 1
            resumeCameraIfNeeded(shouldResumeCamera)
        }
    }

    private func resumeCameraIfNeeded(_ shouldResumeCamera: Bool) {
        guard shouldResumeCamera else { return }
        Task {
            await cameraModel.start()
            if cameraModel.state == .waitingForSensors {
                await locationModel.requestLocation()
            }
        }
    }

    private func transitionArtworkFrame(
        presentation: MountainDetailPresentation,
        containerFrame: CGRect,
        topInset: CGFloat
    ) -> CGRect {
        let destinationFrame = CGRect(
            x: containerFrame.minX,
            y: containerFrame.minY - topInset,
            width: containerFrame.width,
            height: 350
        )

        guard
            !reduceMotion,
            presentation.sourceArtworkFrame.width > 0,
            presentation.sourceArtworkFrame.height > 0
        else {
            return destinationFrame
        }

        return CGRect(
            x: interpolated(
                from: presentation.sourceArtworkFrame.minX,
                to: destinationFrame.minX
            ),
            y: interpolated(
                from: presentation.sourceArtworkFrame.minY,
                to: destinationFrame.minY
            ),
            width: interpolated(
                from: presentation.sourceArtworkFrame.width,
                to: destinationFrame.width
            ),
            height: interpolated(
                from: presentation.sourceArtworkFrame.height,
                to: destinationFrame.height
            )
        )
    }

    private func transitionArtwork(
        mountain: Mountain,
        frame: CGRect,
        containerFrame: CGRect
    ) -> some View {
        MountainArtworkView(mountain: mountain, height: frame.height)
            .overlay {
                LinearGradient(
                    colors: [.clear, YamaColor.canvas],
                    startPoint: .center,
                    endPoint: .bottom
                )
                .opacity(detailTransitionProgress)
            }
            .frame(width: frame.width, height: frame.height)
            .clipShape(
                RoundedRectangle(
                    cornerRadius: 20 * (1 - detailTransitionProgress),
                    style: .continuous
                )
            )
            .position(
                x: frame.midX - containerFrame.minX,
                y: frame.midY - containerFrame.minY
            )
            .opacity(transitionArtworkOpacity)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    private func interpolated(from start: CGFloat, to end: CGFloat) -> CGFloat {
        start + ((end - start) * detailTransitionProgress)
    }
}

enum YamaTab: Hashable {
    case home
    case camera
    case my
}
