//
//  YamaLensApp.swift
//  YamaLens
//
//  Created by kisaya on 2026/08/19.
//

import SwiftUI
import SwiftData

@main
struct YamaLensApp: App {
    private let appContainer = AppContainer()

    var body: some Scene {
        WindowGroup {
            YamaLensRootView(repository: appContainer.mountainRepository)
                .modelContainer(for: UserMountainRecord.self)
        }
    }
}

struct MountainDetailPresentation: Identifiable, Equatable {
    let mountain: Mountain
    let sourceID: String
    let sourceArtworkFrame: CGRect

    var id: String { sourceID }
}

private struct YamaLensRootView: View {
    let repository: any MountainRepository
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var selectedTab: YamaTab = .home
    @State private var detailPresentation: MountainDetailPresentation?
    @State private var detailTransitionProgress: CGFloat = 1

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                TabView(selection: $selectedTab) {
                    HomeView(repository: repository) { presentation in
                        openDetail(presentation)
                    }
                    .tabItem {
                        Image(systemName: "mountain.2")
                            .accessibilityLabel("ホーム")
                    }
                    .tag(YamaTab.home)

                    CameraPlaceholderView(selectedTab: $selectedTab)
                        .tabItem {
                            Image(systemName: "camera.viewfinder")
                                .accessibilityLabel("カメラ")
                        }
                        .tag(YamaTab.camera)

                    MyView(repository: repository)
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
        switch style {
        case .zoomToSource:
            if reduceMotion {
                detailPresentation = nil
            } else {
                withAnimation(.spring(response: 0.42, dampingFraction: 0.88)) {
                    detailTransitionProgress = 0
                } completion: {
                    detailPresentation = nil
                    detailTransitionProgress = 1
                }
            }
        case .dragged:
            detailPresentation = nil
            detailTransitionProgress = 1
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
