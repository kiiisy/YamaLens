import SwiftData
import SwiftUI

struct SavedDeparturePointSettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var savedPoints: [SavedDeparturePoint]
    @State private var stationName = ""

    var body: some View {
        Form {
            currentStationSection
            stationNameSection
        }
        .navigationTitle("よく使う出発駅")
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("saved-departure-settings")
        .onAppear {
            guard stationName.isEmpty else { return }
            stationName = savedPoints.first?.name ?? ""
        }
    }

    @ViewBuilder
    private var currentStationSection: some View {
        if let savedPoint = savedPoints.first {
            Section("登録中") {
                LabeledContent("駅", value: savedPoint.name)
                Button("登録を削除", role: .destructive) {
                    modelContext.delete(savedPoint)
                    stationName = ""
                }
            }
        }
    }

    private var stationNameSection: some View {
        Section {
            TextField("例: JR新宿駅", text: $stationName)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.done)
                .accessibilityIdentifier("station-name-field")
            Button(action: save) {
                Label(savedPoints.isEmpty ? "出発駅を登録" : "出発駅を更新", systemImage: "checkmark")
            }
            .disabled(trimmedStationName.isEmpty)
            .accessibilityIdentifier("save-departure-station-button")
        } header: {
            Text("外部地図で使う出発駅名")
        } footer: {
            Text("JR・私鉄・地下鉄を含む、地図アプリで検索できる正式名称を入力してください。例: JR新宿駅。入力した名称を外部地図の出発地検索語として使います。")
        }
    }

    private var trimmedStationName: String {
        stationName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func save() {
        guard !trimmedStationName.isEmpty else { return }
        if let savedPoint = savedPoints.first {
            savedPoint.replace(name: trimmedStationName)
        } else {
            modelContext.insert(SavedDeparturePoint(name: trimmedStationName))
        }
        stationName = trimmedStationName
    }
}
