//  KeePassium Password Manager
//  Copyright © 2018–2019 Andrei Popleteev <info@keepassium.com>
// 
//  This program is free software: you can redistribute it and/or modify it
//  under the terms of the GNU General Public License version 3 as published
//  by the Free Software Foundation: https://www.gnu.org/licenses/).
//  For commercial licensing, please contact the author.

import UIKit
import KeePassiumLib
import LocalAuthentication

class AppDelegate: UIResponder, UIApplicationDelegate {

    var window: UIWindow?
    fileprivate var watchdog: Watchdog
    fileprivate var appCoverWindow: UIWindow?
    fileprivate var appLockWindow: UIWindow?
    fileprivate var biometricsBackgroundWindow: UIWindow?
    fileprivate var isBiometricAuthShown = false
    
    override init() {
        watchdog = Watchdog.shared 
        super.init()
        watchdog.delegate = self
    }
    
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
        ) -> Bool
    {
        AppGroup.applicationShared = application
        SettingsMigrator.processAppLaunch(with: Settings.current)
        
        showAppCoverScreen()
        return true
    }
    
    func application(
        _ application: UIApplication,
        open inputURL: URL,
        options: [UIApplication.OpenURLOptionsKey : Any] = [:]
        ) -> Bool
    {
        AppGroup.applicationShared = application
        let isOpenInPlace = (options[.openInPlace] as? Bool) ?? false

        Diag.info("Opened with URL: \(inputURL.redacted) [inPlace: \(isOpenInPlace)]")
        
        FileKeeper.shared.prepareToAddFile(
            url: inputURL,
            mode: isOpenInPlace ? .openInPlace : .import)
        
        DatabaseManager.shared.closeDatabase(clearStoredKey: false)
        return true
    }
}

extension AppDelegate: WatchdogDelegate {
    var isAppCoverVisible: Bool {
        return appCoverWindow != nil
    }
    var isAppLockVisible: Bool {
        return appLockWindow != nil || isBiometricAuthShown
    }
    func showAppCover(_ sender: Watchdog) {
        showAppCoverScreen()
    }
    func hideAppCover(_ sender: Watchdog) {
        hideAppCoverScreen()
    }
    func showAppLock(_ sender: Watchdog) {
        showAppLockScreen()
    }
    func hideAppLock(_ sender: Watchdog) {
        hideAppLockScreen()
    }
    
    private func showAppCoverScreen()  {
        guard appCoverWindow == nil else { return }
        
        let _appCoverWindow = UIWindow(frame: UIScreen.main.bounds)
        _appCoverWindow.screen = UIScreen.main
        _appCoverWindow.windowLevel = UIWindow.Level.alert
        let coverVC = AppCoverVC.make()
        
        UIView.performWithoutAnimation {
            _appCoverWindow.rootViewController = coverVC
            _appCoverWindow.makeKeyAndVisible()
        }
        self.appCoverWindow = _appCoverWindow
        print("App cover shown")
        
        coverVC.view.snapshotView(afterScreenUpdates: true)
    }
    
    private func hideAppCoverScreen() {
        guard let appCoverWindow = appCoverWindow else { return }
        appCoverWindow.isHidden = true
        self.appCoverWindow = nil
        print("App cover hidden")
    }
    
    private var canUseBiometrics: Bool {
        return isBiometricsAvailable() && Settings.current.isBiometricAppLockEnabled
    }
    
    private func showAppLockScreen() {
        guard !isAppLockVisible else { return }
        if canUseBiometrics {
            performBiometricUnlock()
        } else {
            showPasscodeRequest()
        }
    }
    
    private func hideAppLockScreen() {
        guard isAppLockVisible else { return }
        appLockWindow?.resignKey()
        appLockWindow?.isHidden = true
        appLockWindow = nil
        print("appLockWindow hidden")
    }
    
    private func showPasscodeRequest() {
        let passcodeInputVC = PasscodeInputVC.instantiateFromStoryboard()
        passcodeInputVC.delegate = self
        passcodeInputVC.mode = .verification
        passcodeInputVC.isCancelAllowed = false 
        passcodeInputVC.isBiometricsAllowed = canUseBiometrics
        
        let _appLockWindow = UIWindow(frame: UIScreen.main.bounds)
        _appLockWindow.screen = UIScreen.main
        _appLockWindow.windowLevel = UIWindow.Level.alert
        UIView.performWithoutAnimation {
            _appLockWindow.rootViewController = passcodeInputVC
            _appLockWindow.makeKeyAndVisible()
        }
        self.appLockWindow = _appLockWindow
        print("passcode request shown")
    }
    
    private func isBiometricsAvailable() -> Bool {
        let context = LAContext()
        let policy = LAPolicy.deviceOwnerAuthenticationWithBiometrics
        return context.canEvaluatePolicy(policy, error: nil)
    }
    
    private func performBiometricUnlock() {
        assert(isBiometricsAvailable())
        guard Settings.current.isBiometricAppLockEnabled else { return }
        guard !isBiometricAuthShown else { return }
        
        let context = LAContext()
        let policy = LAPolicy.deviceOwnerAuthenticationWithBiometrics
        context.localizedFallbackTitle = "" // hide "Enter Password" fallback; nil won't work
        print("Showing biometrics request")
        
        showBiometricsBackground()
        context.evaluatePolicy(policy, localizedReason: LString.titleTouchID) {
            [weak self] (authSuccessful, authError) in
            DispatchQueue.main.async { [weak self] in
                if authSuccessful {
                    self?.watchdog.unlockApp(fromAnotherWindow: true)
                } else {
                    Diag.warning("TouchID failed [message: \(authError?.localizedDescription ?? "nil")]")
                    self?.showPasscodeRequest()
                }
                self?.hideBiometricsBackground()
                self?.isBiometricAuthShown = false
            }
        }
        isBiometricAuthShown = true
    }
    
    private func showBiometricsBackground()  {
        guard biometricsBackgroundWindow == nil else { return }
        
        let window = UIWindow(frame: UIScreen.main.bounds)
        window.screen = UIScreen.main
        window.windowLevel = UIWindow.Level.alert + 1 
        let coverVC = AppCoverVC.make()
        
        UIView.performWithoutAnimation {
            window.rootViewController = coverVC
            window.makeKeyAndVisible()
        }
        print("Biometrics background shown")
        self.biometricsBackgroundWindow = window
        
        coverVC.view.snapshotView(afterScreenUpdates: true)
    }
    
    private func hideBiometricsBackground() {
        guard let window = biometricsBackgroundWindow else { return }
        window.isHidden = true
        self.biometricsBackgroundWindow = nil
        print("Biometrics background hidden")
    }
    
}

extension AppDelegate: PasscodeInputDelegate {
    func passcodeInput(_ sender: PasscodeInputVC, didEnterPasscode passcode: String) {
        do {
            if try Keychain.shared.isAppPasscodeMatch(passcode) { 
                watchdog.unlockApp(fromAnotherWindow: false)
            } else {
                sender.animateWrongPassccode()
                if Settings.current.isLockAllDatabasesOnFailedPasscode {
                    try? Keychain.shared.removeAllDatabaseKeys()
                    DatabaseManager.shared.closeDatabase(clearStoredKey: true)
                }
            }
        } catch {
            let alert = UIAlertController.make(
                title: LString.titleKeychainError,
                message: error.localizedDescription)
            sender.present(alert, animated: true, completion: nil)
        }
    }
    
    func passcodeInputDidRequestBiometrics(_ sender: PasscodeInputVC) {
        assert(canUseBiometrics)
        performBiometricUnlock()
    }
}
