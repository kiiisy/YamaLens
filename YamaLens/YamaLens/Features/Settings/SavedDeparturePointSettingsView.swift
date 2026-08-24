import SwiftData
import SwiftUI

struct SavedDeparturePointSettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var savedPoints: [SavedDeparturePoint]
    @State private var query = ""
    @State private var results: [StationSearchResult] = []
    @State private var state: SearchState = .idle
    private let stationSearch: any StationSearching

    init(stationSearch: any StationSearching = MapKitStationSearchService()) {
        self.stationSearch = stationSearch
    }

    var body: some View {
        List {
            currentStationSection
            searchSection
            resultsSection
        }
        .navigationTitle("よく使う出発駅")
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("saved-departure-settings")
    }

    @ViewBuilder
    private var currentStationSection: some View {
        if let savedPoint = savedPoints.first {
            Section("登録中") {
                LabeledContent("駅", value: savedPoint.name)
                Button("登録を削除", role: .destructive) {
                    modelContext.delete(savedPoint)
                }
            }
        }
    }

    private var searchSection: some View {
        Section {
            TextField("駅名を入力", text: $query)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .onSubmit(search)
                .accessibilityIdentifier("station-search-field")
            Button(action: search) {
                if state == .loading {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text("検索中")
                    }
                } else {
                    Label("駅を検索", systemImage: "magnifyingglass")
                }
            }
            .disabled(query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || state == .loading)
            .accessibilityIdentifier("station-search-button")
        } header: {
            Text("駅を検索")
        } footer: {
            Text("駅名と座標だけをこのiPhone内に保存します。検索語と検索履歴は保存しません。")
        }
    }

    @ViewBuilder
    private var resultsSection: some View {
        switch state {
        case .idle, .loading:
            EmptyView()
        case .loaded where results.isEmpty:
            Section {
                ContentUnavailableView(
                    "駅が見つかりません",
                    systemImage: "tram",
                    description: Text("駅名を変えて、もう一度検索してください。")
                )
            }
        case .loaded:
            Section("検索結果") {
                ForEach(results) { result in
                    Button {
                        save(result)
                    } label: {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(result.name)
                                .foregroundStyle(.primary)
                            if let locality = result.locality {
                                Text(locality)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    }
                    .accessibilityLabel("\(result.name)をよく使う出発駅に登録")
                }
            }
        case .failed:
            Section {
                ContentUnavailableView(
                    "駅を検索できません",
                    systemImage: "wifi.exclamationmark",
                    description: Text("通信を確認して、もう一度お試しください。")
                )
            }
        }
    }

    private func search() {
        let submittedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !submittedQuery.isEmpty else { return }
        state = .loading
        results = []
        Task {
            do {
                let newResults = try await stationSearch.searchStations(query: submittedQuery)
                guard query.trimmingCharacters(in: .whitespacesAndNewlines) == submittedQuery else {
                    return
                }
                results = newResults
                state = .loaded
            } catch is CancellationError {
                return
            } catch {
                guard query.trimmingCharacters(in: .whitespacesAndNewlines) == submittedQuery else {
                    return
                }
                state = .failed
            }
        }
    }

    private func save(_ result: StationSearchResult) {
        if let savedPoint = savedPoints.first {
            savedPoint.replace(name: result.name, coordinate: result.coordinate)
        } else {
            modelContext.insert(
                SavedDeparturePoint(name: result.name, coordinate: result.coordinate)
            )
        }
        results = []
        query = ""
        state = .idle
    }
}

private enum SearchState: Equatable {
    case idle
    case loading
    case loaded
    case failed
}
