import Foundation
import StreakData
import XCTest

final class FilePanelLocationsTests: XCTestCase {
    func testIndependentDirectoriesPersistAcrossInstances() throws {
        let suite = "FilePanelLocationsTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let locations = FilePanelLocations(defaults: defaults)
        XCTAssertEqual(locations.openDirectory, FileManager.default.homeDirectoryForCurrentUser)
        XCTAssertNil(locations.saveDirectory)

        let input = URL(fileURLWithPath: "/tmp/streak-input", isDirectory: true)
        let output = URL(fileURLWithPath: "/tmp/streak-output", isDirectory: true)
        let otherInput = URL(fileURLWithPath: "/tmp/streak-other-input", isDirectory: true)
        let otherOutput = URL(fileURLWithPath: "/tmp/streak-other-output", isDirectory: true)
        locations.openDirectory = input
        XCTAssertNil(locations.saveDirectory)
        locations.saveDirectory = output
        XCTAssertEqual(locations.openDirectory, input)
        locations.openDirectory = otherInput
        XCTAssertEqual(locations.saveDirectory, output)
        locations.saveDirectory = otherOutput
        XCTAssertEqual(locations.openDirectory, otherInput)

        let restored = FilePanelLocations(defaults: try XCTUnwrap(UserDefaults(suiteName: suite)))
        XCTAssertEqual(restored.openDirectory, otherInput)
        XCTAssertEqual(restored.saveDirectory, otherOutput)
    }
}
