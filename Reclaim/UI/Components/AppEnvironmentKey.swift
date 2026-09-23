//
//  AppEnvironmentKey.swift
//  Reclaim
//
//  Document 04 §1: AppEnvironment is "threaded down via the SwiftUI
//  environment or explicit initializer injection — no singletons accessed
//  ad hoc from inside a ViewModel". Leaf UI components (thumbnails in grid
//  cells) would otherwise need the environment passed through every level,
//  so the composition root is exposed as a SwiftUI environment value
//  instead. Default is nil: only test previews that never request images
//  render without it — a missing composition root is a programming error
//  at the call site, not something to paper over with a global.
//

import SwiftUI

private struct AppEnvironmentKey: EnvironmentKey {
    static let defaultValue: AppEnvironment? = nil
}

extension EnvironmentValues {
    var appEnvironment: AppEnvironment? {
        get { self[AppEnvironmentKey.self] }
        set { self[AppEnvironmentKey.self] = newValue }
    }
}
