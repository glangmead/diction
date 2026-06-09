import Foundation

/// A heading-grouped, curated catalog of IFDB games surfaced on the IFDB search
/// screen before the user types anything. Each playable game links to the same
/// detail page a live search result would, because an IFDB `viewgame?id=…` URL's
/// `id` is exactly the `tuid` the detail view consumes.
///
/// The source list lives (gitignored) in `nocommit/ifdb_links.md`; this is the
/// committed, shipped copy. Keep the two in sync by hand when curating.
struct CuratedIFDBList {
  var sections: [CuratedIFDBSection]
}

/// One titled block of the catalog. The title may carry an embedded link on a
/// substring (e.g. a book title); only that run is a link. Plain sections have
/// no link run. Presentation styles whichever run is a link.
struct CuratedIFDBSection: Identifiable {
  var title: AttributedString
  var groups: [CuratedIFDBGroup]
  var id: String { String(title.characters) }
}

/// A run of games under an optional sub-heading (e.g. "Supported", "Not
/// supported yet"). A nil heading renders the games with no sub-heading.
struct CuratedIFDBGroup: Identifiable {
  var heading: String?
  var games: [CuratedIFDBGame]
  var id: String { heading ?? "" }

  /// Games sorted by title for display. The sort ignores a leading article
  /// (`IFDBTitleSort`) so "The Witness" files under W, and uses locale-aware
  /// comparison so accented titles (e.g. "Shōgun") collate correctly. The full
  /// title is a stable tiebreak when two keys match.
  var sortedGames: [CuratedIFDBGame] {
    games.sorted { lhs, rhs in
      let keyOrder = IFDBTitleSort.sortKey(lhs.title)
        .localizedStandardCompare(IFDBTitleSort.sortKey(rhs.title))
      if keyOrder != .orderedSame { return keyOrder == .orderedAscending }
      return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
    }
  }
}

/// A single curated game. `isPlayable` is false for titles IFDB lists but our
/// interpreter can't yet run (graphical Infocom games); those render as plain,
/// non-tappable text. `annotation` carries a trailing note like "French".
struct CuratedIFDBGame: Identifiable {
  var title: String
  var tuid: String
  var isPlayable: Bool
  var annotation: String?

  init(_ title: String, tuid: String, isPlayable: Bool = true, annotation: String? = nil) {
    self.title = title
    self.tuid = tuid
    self.isPlayable = isPlayable
    self.annotation = annotation
  }

  var id: String { tuid }
}

extension CuratedIFDBList {
  /// "Mentioned in 50 Years of Text Games by Aaron A. Reed", with only the book
  /// title carrying the link to the author's site — the rest stays plain text.
  private static var fiftyYearsTitle: AttributedString {
    var title = AttributedString("Mentioned in ")
    var book = AttributedString("50 Years of Text Games")
    book.link = URL(string: "https://aaronareed.net/50-years-of-text-games/")
    title.append(book)
    title.append(AttributedString(" by Aaron A. Reed"))
    return title
  }

  /// The shipped curated catalog. Mirrors `nocommit/ifdb_links.md`.
  static let all = CuratedIFDBList(sections: [
    CuratedIFDBSection(
      title: AttributedString("Lost Treasures of Infocom I, II, CD-ROM"),
      groups: [
        CuratedIFDBGroup(heading: "Supported by Diction", games: [
          CuratedIFDBGame("Zork I", tuid: "0dbnusxunq7fw5ro"),
          CuratedIFDBGame("Zork II", tuid: "yzzm4puxyjakk8c4"),
          CuratedIFDBGame("Zork III", tuid: "vrsot1zgy1wfcdru"),
          CuratedIFDBGame("Beyond Zork", tuid: "9h6o1charof548ii"),
          CuratedIFDBGame("Zork Zero", tuid: "17coplfu323xif76"),
          CuratedIFDBGame("Enchanter", tuid: "vu4xhul3abknifcr"),
          CuratedIFDBGame("Sorcerer", tuid: "lidg5nx9ig0bwk55"),
          CuratedIFDBGame("Spellbreaker", tuid: "wqsmrahzozosu3r"),
          CuratedIFDBGame("Deadline", tuid: "p976o7x5ies9ltdh"),
          CuratedIFDBGame("The Witness", tuid: "6963a47vqgms8wi0"),
          CuratedIFDBGame("Suspect", tuid: "tdbss1ekrp4ua7h4"),
          CuratedIFDBGame("The Lurking Horror", tuid: "jhbd0kja1t57uop"),
          CuratedIFDBGame("Ballyhoo", tuid: "b0i6bx7g4rkrekgg"),
          CuratedIFDBGame("Infidel", tuid: "anu79a4n1jedg5mm"),
          CuratedIFDBGame("Moonmist", tuid: "c66u816v8kx2jzm2"),
          CuratedIFDBGame("Starcross", tuid: "y42oje3ryqi6lohn"),
          CuratedIFDBGame("Suspended", tuid: "t47hei9uq10xoar8"),
          CuratedIFDBGame("Planetfall", tuid: "xe6kb3cuqwie2q38"),
          CuratedIFDBGame("Stationfall", tuid: "9nlbhqnlyb169uge"),
          CuratedIFDBGame("The Hitchhiker's Guide to the Galaxy", tuid: "ouv80gvsl32xlion"),
          CuratedIFDBGame("Border Zone", tuid: "7epwz167lgruvm0u"),
          CuratedIFDBGame("A Mind Forever Voyaging", tuid: "4h62dvooeg9ajtfa"),
          CuratedIFDBGame("Plundered Hearts", tuid: "ddagftras22bnz8h"),
          CuratedIFDBGame("Bureaucracy", tuid: "zjyxds3s57pgis3x"),
          CuratedIFDBGame("Cutthroats", tuid: "4ao65o1u0xuvj8jf"),
          CuratedIFDBGame("Hollywood Hijinx", tuid: "jnfkbgdgopwfqist"),
          CuratedIFDBGame("Seastalker", tuid: "56wb8hflec2isvzm"),
          CuratedIFDBGame("Sherlock: The Riddle of the Crown Jewels", tuid: "j8lmspy4iz73mx26"),
          CuratedIFDBGame("Wishbringer", tuid: "z02joykzh66wfhcl"),
          CuratedIFDBGame("Nord and Bert Couldn't Make Head or Tail of It", tuid: "zxb8pq3qrkvdob4i"),
          CuratedIFDBGame("Trinity", tuid: "j18kjz80hxjtyayw"),
          CuratedIFDBGame("Leather Goddesses of Phobos", tuid: "3p9fdt4fxr2goctw"),
          CuratedIFDBGame("Shogun", tuid: "w3pz3v8wckaw1wgb")
        ]),
        CuratedIFDBGroup(heading: "Not supported yet", games: [
          CuratedIFDBGame("Arthur: The Quest for Excalibur", tuid: "zoohwv5nqye7up2t", isPlayable: false),
          CuratedIFDBGame("Journey", tuid: "2752o3sh6y05ob1p", isPlayable: false)
        ])
      ]
    ),
    CuratedIFDBSection(
      title: fiftyYearsTitle,
      groups: [
        CuratedIFDBGroup(heading: nil, games: [
          CuratedIFDBGame("Adventure", tuid: "fft6pu91j85y4acv"),
          CuratedIFDBGame("Zork", tuid: "4gxk83ja4twckm6j"),
          CuratedIFDBGame("Suspended", tuid: "t47hei9uq10xoar8"),
          CuratedIFDBGame("The Hitchhiker's Guide to the Galaxy", tuid: "ouv80gvsl32xlion"),
          CuratedIFDBGame("A Mind Forever Voyaging", tuid: "4h62dvooeg9ajtfa"),
          CuratedIFDBGame("Plundered Hearts", tuid: "ddagftras22bnz8h"),
          CuratedIFDBGame("Curses", tuid: "plvzam05bmz3enh8"),
          CuratedIFDBGame("So Far", tuid: "rcrihauxixy48svr"),
          CuratedIFDBGame("Photopia", tuid: "ju778uv5xaswnlpl"),
          CuratedIFDBGame("Galatea", tuid: "urxrv27t7qtu52lb"),
          CuratedIFDBGame("The Fire Tower", tuid: "fcm1ikz9ttr6i99a"),
          CuratedIFDBGame("Lieux Communs", tuid: "utd2or64zwqfaa7", annotation: "(French)"),
          CuratedIFDBGame("El Museo de las Consciencias", tuid: "oe62obqziewqgik", annotation: "(Spanish)"),
          CuratedIFDBGame("Violet", tuid: "4glrrfh7wrp9zz7b"),
          CuratedIFDBGame("Scents & Semiosis", tuid: "h8lrej4fid9cd3u3")
        ])
      ]
    )
  ])
}
