import Testing
import Foundation
@testable import Diction

// `StoryFile.supportedExtensions` is the single source of truth for both the
// import picker (LibraryView) and library discovery (StoryFileManager). It
// drifted twice when those were separate lists — silently dropping valid v4
// stories like AMFV — so pin the supported range here. ZVM runs v3/4/5/8;
// v1/v2 (ancient) and v6/v7 (graphical/obscure) are intentionally excluded.

@Test("Supported extensions cover the Z-machine versions ZVM runs (v3/4/5/8)")
func supportedExtensionsCoverZMachineRange() {
  for version in [3, 4, 5, 8] {
    #expect(StoryFile.supportedExtensions.contains("z\(version)"))
  }
  for version in [1, 2, 6, 7] {
    #expect(!StoryFile.supportedExtensions.contains("z\(version)"))
  }
}

@Test("Supported extensions cover Glulx and Blorb containers")
func supportedExtensionsCoverGlulxAndBlorb() {
  for ext in ["ulx", "gblorb", "zblorb", "blorb", "blb"] {
    #expect(StoryFile.supportedExtensions.contains(ext))
  }
}
