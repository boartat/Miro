//
//  MiroLinks.swift
//  Miro
//
//  Where Miro's source, license and issue tracker live. GPL-3.0 asks the app itself to point at them.
//

import Foundation

enum MiroLinks {
    static let repository = URL(string: "https://github.com/boartat/Miro")!
    static let issues = URL(string: "https://github.com/boartat/Miro/issues")!
    static let license = URL(string: "https://github.com/boartat/Miro/blob/main/LICENSE")!
    static let notices = URL(string: "https://github.com/boartat/Miro/blob/main/THIRD_PARTY_NOTICES.md")!

    static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
    }
}
