//
//  ControllerApp.swift
//  Controller
//
//  Created by Toby Yu on 04/04/2026.
//

import SwiftUI

#if os(iOS)
class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        return .landscape
    }
}

struct iOSRootView: View {
    var body: some View {
        if UIDevice.current.userInterfaceIdiom == .pad {
            iPadReceiverView()
        } else {
            ContentView()
        }
    }
}
#endif

@main
struct ControllerApp: App {
    #if os(iOS)
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    #endif

    var body: some Scene {
        WindowGroup {
            #if os(macOS)
            MacContentView()
                .preferredColorScheme(.dark)
            #elseif os(iOS)
            iOSRootView()
                .preferredColorScheme(.dark)
            #endif
        }
    }
}
