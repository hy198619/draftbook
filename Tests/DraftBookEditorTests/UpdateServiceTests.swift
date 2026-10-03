import XCTest
@testable import DraftBook

final class UpdateServiceTests: XCTestCase {
    func testVersionComparisonAndInvalidVersions() {
        XCTAssertTrue(AppVersion("0.9.5")! > AppVersion("0.9.4")!)
        XCTAssertTrue(AppVersion("0.10.0")! > AppVersion("0.9.9")!)
        XCTAssertNil(AppVersion("0.9.5-beta"))
        XCTAssertNil(AppVersion("0.9"))
    }

    func testReleaseAssetsMustMatchOfficialRepositoryAndTag() throws {
        let release = try JSONDecoder().decode(UpdateRelease.self, from: Data("""
        {
          "tag_name": "v0.9.5",
          "body": "更新说明",
          "draft": false,
          "assets": [
            {"name":"DraftBook-v0.9.5-macOS-unsigned.dmg","browser_download_url":"https://github.com/hy198619/draftbook/releases/download/v0.9.5/DraftBook-v0.9.5-macOS-unsigned.dmg"},
            {"name":"SHA256SUMS.txt","browser_download_url":"https://example.com/SHA256SUMS.txt"}
          ]
        }
        """.utf8))
        XCTAssertEqual(release.version, AppVersion("0.9.5"))
        XCTAssertNotNil(release.verifiedAsset(named: "DraftBook-v0.9.5-macOS-unsigned.dmg"))
        XCTAssertNil(release.verifiedAsset(named: "SHA256SUMS.txt"))
    }

    func testPublishedPrereleasesAreIncludedAndDraftsExcluded() throws {
        let releases = try JSONDecoder().decode([UpdateRelease].self, from: Data("""
        [
          {"tag_name":"v0.9.4","draft":false,"body":null,"assets":[]},
          {"tag_name":"v0.9.5","draft":false,"body":null,"assets":[]},
          {"tag_name":"v0.9.6","draft":true,"body":null,"assets":[]}
        ]
        """.utf8))
        XCTAssertEqual(UpdateService.newestPublishedRelease(in: releases)?.tagName, "v0.9.5")
    }

    func testChecksumLookupUsesExactFilenameAndValidDigest() {
        let digest = String(repeating: "a", count: 64)
        let sums = "\(digest)  other.dmg\n\(digest)  DraftBook-v0.9.5-macOS-unsigned.dmg\n"
        XCTAssertEqual(
            UpdateService.expectedChecksum(for: "DraftBook-v0.9.5-macOS-unsigned.dmg", in: sums),
            digest
        )
        XCTAssertNil(UpdateService.expectedChecksum(for: "DraftBook-v0.9.4-macOS-unsigned.dmg", in: sums))
        XCTAssertNil(UpdateService.expectedChecksum(for: "test.dmg", in: "bad  test.dmg"))
    }
}
