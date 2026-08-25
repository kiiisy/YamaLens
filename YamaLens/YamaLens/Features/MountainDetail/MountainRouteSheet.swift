import SwiftData
import SwiftUI

nonisolated struct MountainRouteDestination: Identifiable, Equatable, Sendable {
    let point: MountainPointOfInterest
    let suggestedMode: ExternalMapTravelMode

    var id: String { point.id }
}

struct MountainRouteSheet: View {
    let destination: MountainRouteDestination
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Query private var savedDeparturePoints: [SavedDeparturePoint]
    @AppStorage("externalMaps.application") private var mapApplicationRawValue = ExternalMapApplication.appleMaps.rawValue
    @State private var selectedOrigin = RouteOriginSelection.currentLocation
    @State private var travelMode: ExternalMapTravelMode
    @State private var showsMapChoice = false

    init(destination: MountainRouteDestination) {
        self.destination = destination
        _travelMode = State(initialValue: destination.suggestedMode)
    }

    var body: some View {
        Form {
            Section("目的地") {
                LabeledContent(destination.point.type.displayName) {
                    Text(destination.point.name)
                        .multilineTextAlignment(.trailing)
                }
            }

            Section("出発地") {
                originButton(
                    title: "現在地",
                    subtitle: "位置情報は地図アプリ側で使用",
                    selection: .currentLocation
                )
                if let savedPoint = savedDeparturePoints.first,
                   !savedPoint.name.isEmpty {
                    originButton(
                        title: savedPoint.name,
                        subtitle: "よく使う出発駅",
                        selection: .savedStation
                    )
                } else {
                    NavigationLink {
                        SavedDeparturePointSettingsView()
                    } label: {
                        Label("よく使う出発駅を登録", systemImage: "tram")
                    }
                }
            }

            Section("移動手段") {
                Picker("移動手段", selection: $travelMode) {
                    Label("公共交通", systemImage: "bus.fill")
                        .tag(ExternalMapTravelMode.publicTransport)
                    Label("車", systemImage: "car.fill")
                        .tag(ExternalMapTravelMode.driving)
                    Label("徒歩", systemImage: "figure.walk")
                        .tag(ExternalMapTravelMode.walking)
                }
                .pickerStyle(.segmented)
            }

            Section {
                Button(action: openRoute) {
                    Label("地図アプリで経路を検索", systemImage: "arrow.triangle.turn.up.right.diamond")
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: 52)
                }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.capsule)
                .tint(YamaColor.forest)
                .accessibilityIdentifier("route-open-maps-button")
            } footer: {
                Text("YamaLensは経路、所要時間、運行状況を計算しません。")
            }
        }
        .scrollContentBackground(.hidden)
        .background(TopographicBackground())
        .navigationTitle("ここへ行く")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("閉じる", systemImage: "xmark") { dismiss() }
                    .labelStyle(.iconOnly)
                    .accessibilityLabel("閉じる")
            }
        }
        .confirmationDialog("地図アプリを選択", isPresented: $showsMapChoice) {
            Button("Appleマップ") { openAppleMaps() }
            if ExternalMapApplicationAvailability.isGoogleMapsAvailable {
                Button("Google Maps") { openGoogleMaps() }
            }
            Button("キャンセル", role: .cancel) {}
        }
        .accessibilityIdentifier("mountain-route-sheet")
        .preferredColorScheme(.dark)
    }

    private func originButton(
        title: String,
        subtitle: String,
        selection: RouteOriginSelection
    ) -> some View {
        Button {
            selectedOrigin = selection
        } label: {
            HStack(spacing: 12) {
                Image(systemName: selectedOrigin == selection ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(selectedOrigin == selection ? YamaColor.alpineTeal : YamaColor.secondaryText)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .foregroundStyle(.primary)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        }
        .accessibilityLabel("出発地、\(title)")
        .accessibilityAddTraits(selectedOrigin == selection ? .isSelected : [])
    }

    private var route: ExternalMapRoute? {
        let origin: ExternalMapRouteOrigin
        switch selectedOrigin {
        case .currentLocation:
            origin = .currentLocation
        case .savedStation:
            guard let savedPoint = savedDeparturePoints.first,
                  !savedPoint.name.isEmpty
            else {
                return nil
            }
            origin = .savedStation(ExternalMapPlace(name: savedPoint.name, coordinate: nil))
        }
        return ExternalMapRoute(
            origin: origin,
            destination: ExternalMapPlace(
                name: destination.point.name,
                coordinate: destination.point.coordinate
            ),
            travelMode: travelMode
        )
    }

    private func openRoute() {
        switch ExternalMapApplication(rawValue: mapApplicationRawValue) ?? .appleMaps {
        case .appleMaps:
            openAppleMaps()
        case .googleMaps:
            if ExternalMapApplicationAvailability.isGoogleMapsAvailable {
                openGoogleMaps()
            } else {
                openAppleMaps()
            }
        case .askEveryTime:
            showsMapChoice = true
        }
    }

    private func openAppleMaps() {
        guard let route, let url = ExternalMapURLBuilder.appleMapsURL(for: route) else { return }
        openURL(url)
    }

    private func openGoogleMaps() {
        guard let route, let url = ExternalMapURLBuilder.googleMapsURL(for: route) else { return }
        openURL(url)
    }
}

private enum RouteOriginSelection: Hashable {
    case currentLocation
    case savedStation
}
