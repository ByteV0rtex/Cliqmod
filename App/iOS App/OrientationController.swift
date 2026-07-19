//
//  OrientationController.swift
//  Cliqmod
//
//  Created by Doruk Arpali on 18.07.2026.
//


import UIKit
import SwiftUI

/// Bridges SwiftUI to the one piece of orientation control that has no SwiftUI-native
/// API: which orientations are allowed right now. `supportedInterfaceOrientationsFor`
/// is only ever queried on the app's root view controller, so this has to live at the
/// UIApplicationDelegate level — there's no per-View equivalent.
///
/// IMPORTANT: this can only ever RESTRICT what the Xcode project already declares.
/// In the target's General tab → Deployment Info → Supported Interface Orientations,
/// both Portrait and Landscape Left/Right need to be checked, or nothing here will be
/// able to rotate into landscape at all.
final class AppDelegate: NSObject, UIApplicationDelegate {
    static var orientationLock = UIInterfaceOrientationMask.portrait

    func application(_ application: UIApplication,
                      supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        AppDelegate.orientationLock
    }
}

enum OrientationController {
    /// Sets the lock AND forces an immediate rotation — just setting the static var
    /// isn't enough on its own, since nothing tells the system to re-query it until
    /// something (a rotation, a fresh window) triggers that naturally.
    static func lock(to mask: UIInterfaceOrientationMask) {
        AppDelegate.orientationLock = mask
        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene else { return }
        scene.requestGeometryUpdate(.iOS(interfaceOrientations: mask)) { error in
            // Geometry update can be rejected (e.g. mid-transition) — attemptRotationToDeviceOrientation
            // below is the fallback nudge for that case, so a failure here isn't fatal.
        }
        UIViewController.attemptRotationToDeviceOrientation()
    }

    static func lockLandscape() { lock(to: .landscape) }
    static func lockPortrait() { lock(to: .portrait) }
}
