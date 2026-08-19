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
    let sourceFrame: CGRect

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
                    HomeView(
                        repository: repository,
                        detailPresentation: $detailPresentation
                    )
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
                    MountainDetailView(
                        mountain: detailPresentation.mountain,
                        overlayTopInset: geometry.safeAreaInsets.top
                    ) { style in
                        closeDetail(style: style)
                    }
                    .clipShape(
                        RoundedRectangle(
                            cornerRadius: 24 * (1 - detailTransitionProgress),
                            style: .continuous
                        )
                    )
                    .scaleEffect(
                        transitionScale(
                            presentation: detailPresentation,
                            containerFrame: geometry.frame(in: .global)
                        )
                    )
                    .offset(
                        transitionOffset(
                            presentation: detailPresentation,
                            containerFrame: geometry.frame(in: .global)
                        )
                    )
                    .zIndex(1)
                    .task(id: detailPresentation.id) {
                        detailTransitionProgress = reduceMotion ? 1 : 0
                        guard !reduceMotion else { return }
                        await Task.yield()
                        withAnimation(.spring(response: 0.42, dampingFraction: 0.88)) {
                            detailTransitionProgress = 1
                        }
                    }
                }
            }
        }
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

    private func transitionScale(
        presentation: MountainDetailPresentation,
        containerFrame: CGRect
    ) -> CGFloat {
        guard !reduceMotion, containerFrame.width > 0, presentation.sourceFrame.width > 0 else {
            return 1
        }
        let sourceScale = min(max(presentation.sourceFrame.width / containerFrame.width, 0.2), 1)
        return sourceScale + ((1 - sourceScale) * detailTransitionProgress)
    }

    private func transitionOffset(
        presentation: MountainDetailPresentation,
        containerFrame: CGRect
    ) -> CGSize {
        guard !reduceMotion else { return .zero }
        let remainingTransition = 1 - detailTransitionProgress
        return CGSize(
            width: (presentation.sourceFrame.midX - containerFrame.midX) * remainingTransition,
            height: (presentation.sourceFrame.midY - containerFrame.midY) * remainingTransition
        )
    }
}

enum YamaTab: Hashable {
    case home
    case camera
    case my
}
