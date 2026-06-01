import Testing
import Foundation
@testable import Diction

// `StoryFile.supportedExtensions` is the single source of truth for both the
// import picker (LibraryView) and library discovery (StoryFileManager). It
// drifted twice when those were separate lists — silently dropping valid v4
// stories like AMFV — so pin the full range here.

@Test("Supported extensions cover the whole Z-machine range FormatDetector accepts")
func supportedExtensionsCoverZMachineRange() {
  for version in 1...8 {
    #expect(StoryFile.supportedExtensions.contains("z\(version)"))
  }
}

@Test("Supported extensions cover Glulx and Blorb containers")
func supportedExtensionsCoverGlulxAndBlorb() {
  for ext in ["ulx", "gblorb", "zblorb", "blorb", "blb"] {
    #expect(StoryFile.supportedExtensions.contains(ext))
  }
}
