//
//  neko_idApp.swift
//  neko-id
//
//  Created by Amadeus on 2026/8/15.
//

import SwiftUI

@main
struct neko_idApp: App {
    @UIApplicationDelegateAdaptor(NekoAppDelegate.self) private var appDelegate
    @StateObject private var appModel = NekoAppModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appModel)
                .preferredColorScheme(.light)
                .tint(.pink)
        }
    }
}
