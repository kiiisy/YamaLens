import SwiftData
import SwiftUI

enum MyMountainCollection: String, Hashable {
    case favorites
    case summited
    case recent

    var title: String {
        switch self {
        case .favorites: "お気に入り"
        case .summited: "登頂済み"
        case .recent: "最近見た山"
        }
    }

    var emptyMessage: String {
        switch self {
        case .favorites: "山詳細の星ボタンから、あとで見返したい山を保存できます。"
        case .summited: "山詳細で、手動で「登頂済み」にした山がここに表示されます。"
        case .recent: "山詳細を開いた山が、ここに新しい順で表示されます。"
        }
    }
}

struct MyMountainCollectionView: View {
    let collection: MyMountainCollection
    let mountains: [Mountain]
    let records: [UserMountainRecord]

    private var displayedMountains: [Mountain] {
        let filteredRecords: [UserMountainRecord]
        switch collection {
        case .favorites:
            filteredRecords = records.filter(\.isFavorite)
        case .summited:
            filteredRecords = records.filter(\.isSummited).sorted {
                ($0.summitedAt ?? .distantPast) > ($1.summitedAt ?? .distantPast)
            }
        case .recent:
            filteredRecords = records.filter { $0.lastViewedAt != nil }.sorted {
                ($0.lastViewedAt ?? .distantPast) > ($1.lastViewedAt ?? .distantPast)
            }
        }

        return filteredRecords.compactMap { record in
            mountains.first { $0.id == record.mountainID }
        }
    }

    var body: some View {
        Group {
            if displayedMountains.isEmpty {
                ContentUnavailableView(
                    collection.title,
                    systemImage: collection == .favorites ? "star" : collection == .summited ? "flag" : "clock",
                    description: Text(collection.emptyMessage)
                )
            } else {
                List(displayedMountains) { mountain in
                    NavigationLink(value: mountain) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(mountain.name).font(.headline)
                            Text("\(mountain.elevationMeters.formatted())m ・ \(mountain.regionName)")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        .frame(minHeight: 44, alignment: .leading)
                    }
                }
            }
        }
        .navigationTitle(collection.title)
        .navigationBarTitleDisplayMode(.inline)
    }
}
