import XCTest

final class GitHubReleaseUpdateTests: XCTestCase {
    func testVersionCompareOrdersSemver() {
        XCTAssertEqual(AppVersion.compare("0.1.12", "0.1.11"), .orderedDescending)
        XCTAssertEqual(AppVersion.compare("0.2.0", "0.1.99"), .orderedDescending)
        XCTAssertEqual(AppVersion.compare("0.1.12", "0.1.12"), .orderedSame)
        XCTAssertEqual(AppVersion.compare("0.1.11", "0.1.12"), .orderedAscending)
        XCTAssertTrue(AppVersion.isVersion("0.1.13", newerThan: "0.1.12"))
        XCTAssertFalse(AppVersion.isVersion("0.1.12", newerThan: "0.1.12"))
    }

    func testParseReleasePicksArchitectureDMG() throws {
        let json = #"""
        {
          "tag_name": "v0.1.13",
          "html_url": "https://github.com/ZeppelinOFF/vidgetYo/releases/tag/v0.1.13",
          "assets": [
            {"name": "VidgetYo-0.1.13-macOS27-x86_64.dmg", "browser_download_url": "https://example.com/intel.dmg"},
            {"name": "VidgetYo-0.1.13-macOS27-arm64.dmg", "browser_download_url": "https://example.com/arm.dmg"}
          ]
        }
        """#.data(using: .utf8)!
        let info = try GitHubReleaseFetcher.parseRelease(data: json, architecture: "arm64")
        XCTAssertEqual(info.version, "0.1.13")
        XCTAssertEqual(info.assetFileName, "VidgetYo-0.1.13-macOS27-arm64.dmg")
        XCTAssertEqual(info.downloadURL.absoluteString, "https://example.com/arm.dmg")
    }

    func testDmgAssetNameMatchesCI() {
        XCTAssertEqual(
            GitHubReleaseFetcher.dmgAssetName(version: "0.1.12", architecture: "arm64"),
            "VidgetYo-0.1.12-macOS27-arm64.dmg"
        )
    }

    func testTaskDefaultsUseNameValueM() throws {
        let json = #"""
        [
          {"groupValue":"Настройки задач","nameValueM":"global_setting.task.simple.default_type","settingIds":"2"},
          {"groupValue":"Настройки задач","nameValueM":"global_setting.task.simple.default_hierarchy_level","settingIds":"2"},
          {"groupValue":"Настройки задач","nameValueM":"global_setting.task.simple.default_priority","settingIds":"2"}
        ]
        """#.data(using: .utf8)!
        let rows = try JSONSerialization.jsonObject(with: json) as? [[String: Any]]
        XCTAssertEqual(rows?.count, 3)
        var typeID: Int?
        var hierarchyLevelID: Int?
        var priorityID: Int?
        for row in rows ?? [] {
            let key = row["nameValueM"] as? String ?? ""
            guard let raw = row["settingIds"] as? String, let value = Int(raw) else { continue }
            if key.hasSuffix("default_type") { typeID = value }
            if key.hasSuffix("default_hierarchy_level") { hierarchyLevelID = value }
            if key.hasSuffix("default_priority") { priorityID = value }
        }
        XCTAssertEqual(typeID, 2)
        XCTAssertEqual(hierarchyLevelID, 2)
        XCTAssertEqual(priorityID, 2)
    }
}
