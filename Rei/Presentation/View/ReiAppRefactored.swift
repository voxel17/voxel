//
//  ReiAppRefactored.swift
//  Rei
//
//  Main app entry point - refactored
//

import SwiftUI

@main
struct ReiApp: App {
    var body: some Scene {
        #if os(macOS)
        WindowGroup {
            MainView()
                .frame(minWidth: 800, minHeight: 600)
        }
        .windowStyle(.titleBar)
        .windowResizability(.contentMinSize)
        #else
        WindowGroup {
            MainView()
        }
        #endif
    }
}

#Preview {
    MainView()
}
