import Testing
@testable import YamaLens

struct DevelopmentTanzawaTerrainProfileTests {
    @Test("起動引数で丹沢の地形プロファイルを選べる")
    func selectsProfileFromLaunchArguments() {
        let profile = DevelopmentTanzawaTerrainProfile.selected(
            from: ["YamaLens", "-tanzawa-terrain-profile", "compact"]
        )

        #expect(profile == .compact)
    }

    @Test("値がないまたは不正な起動引数は選択しない")
    func rejectsMissingOrUnknownProfile() {
        #expect(
            DevelopmentTanzawaTerrainProfile.selected(
                from: ["YamaLens", "-tanzawa-terrain-profile"]
            ) == nil
        )
        #expect(
            DevelopmentTanzawaTerrainProfile.selected(
                from: ["YamaLens", "-tanzawa-terrain-profile", "unknown"]
            ) == nil
        )
    }

    @Test("起動引数がない場合は保存した開発用の選択を使う")
    func selectsProfileFromStoredDevelopmentSelection() {
        #expect(
            DevelopmentTanzawaTerrainProfile.selected(
                from: ["YamaLens"],
                storedRawValue: "standard"
            ) == .standard
        )
    }

    @Test("起動引数は保存した開発用の選択より優先する")
    func prioritizesLaunchArgumentOverStoredDevelopmentSelection() {
        #expect(
            DevelopmentTanzawaTerrainProfile.selected(
                from: ["YamaLens", "-tanzawa-terrain-profile", "compact"],
                storedRawValue: "standard"
            ) == .compact
        )
    }

    @Test("プロファイルごとに同梱先を分離する")
    func usesSeparateDevelopmentBundleDirectories() {
        #expect(
            DevelopmentTanzawaTerrainProfile.standard.packageDirectoryName
                == "tanzawa-standard-v1"
        )
        #expect(
            DevelopmentTanzawaTerrainProfile.compact.packageDirectoryName
                == "tanzawa-compact-v1"
        )
        #expect(
            DevelopmentTanzawaTerrainProfile.standard.packageID
                == "jp.kanagawa.tanzawa.terrain-standard-test"
        )
        #expect(DevelopmentTanzawaTerrainProfile.detailed.packageID == "jp.kanagawa.tanzawa")
    }
}
