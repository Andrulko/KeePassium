//  KeePassium Password Manager
//  Copyright © 2018–2019 Andrei Popleteev <info@keepassium.com>
// 
//  This program is free software: you can redistribute it and/or modify it
//  under the terms of the GNU General Public License version 3 as published
//  by the Free Software Foundation: https://www.gnu.org/licenses/).
//  For commercial licensing, please contact the author.

import UIKit
import LocalAuthentication
import KeePassiumLib

class SettingsAppLockVC: UITableViewController, Refreshable {
    @IBOutlet weak var appLockEnabledSwitch: UISwitch!
    @IBOutlet weak var appLockTimeoutCell: UITableViewCell!
    @IBOutlet weak var lockDatabasesOnFailedPasscodeCell: UITableViewCell!
    @IBOutlet weak var lockDatabasesOnFailedPasscodeSwitch: UISwitch!
    @IBOutlet weak var biometricsCell: UITableViewCell!
    @IBOutlet weak var biometricsIcon: UIImageView!
    @IBOutlet weak var allowBiometricsLabel: UILabel!
    @IBOutlet weak var biometricsSwitch: UISwitch!

    private var settingsNotifications: SettingsNotifications!
    private var isBiometricsSupported = false
    private var passcodeInputVC: PasscodeInputVC?
    
    private enum Sections: Int {
        static let allValues: [Sections] = [.passcode, .biometrics, .timeout, .protectDatabases]
        case passcode = 0
        case biometrics = 1
        case timeout = 2
        case protectDatabases = 3
    }
    
    
    override func viewDidLoad() {
        super.viewDidLoad()
        clearsSelectionOnViewWillAppear = true
        settingsNotifications = SettingsNotifications(observer: self)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        settingsNotifications.startObserving()

        refreshBiometricsSupport()
        refresh()
    }

    override func viewWillDisappear(_ animated: Bool) {
        settingsNotifications.stopObserving()
        super.viewWillDisappear(animated)
    }
    
    
    private func refreshBiometricsSupport() {
        let context = LAContext()
        isBiometricsSupported = context.canEvaluatePolicy(
            LAPolicy.deviceOwnerAuthenticationWithBiometrics,
            error: nil)
        if !isBiometricsSupported {
            Settings.current.isBiometricAppLockEnabled = false
        }
        
        let biometryTypeName = context.biometryType.name ?? "Touch ID/Face ID"
        allowBiometricsLabel.text = NSLocalizedString(
            "Use \(biometryTypeName)",
            comment: "Settings switch: whether AppLock is allowed to use Touch ID/Face ID.")
        biometricsIcon.image = context.biometryType.icon
    }
    
    func refresh() {
        let settings = Settings.current
        let isAppLockEnabled = settings.isAppLockEnabled
        appLockEnabledSwitch.isOn = isAppLockEnabled
        appLockTimeoutCell.detailTextLabel?.text = settings.appLockTimeout.shortTitle
        lockDatabasesOnFailedPasscodeSwitch.isOn = settings.isLockAllDatabasesOnFailedPasscode
        biometricsSwitch.isOn = settings.isBiometricAppLockEnabled
        
        appLockTimeoutCell.setEnabled(isAppLockEnabled)
        lockDatabasesOnFailedPasscodeCell.setEnabled(isAppLockEnabled)
        biometricsCell.setEnabled(isAppLockEnabled && isBiometricsSupported)
        biometricsSwitch.isEnabled = isAppLockEnabled && isBiometricsSupported
    }

    
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard let selectedCell = tableView.cellForRow(at: indexPath) else { return }
        if selectedCell === appLockTimeoutCell {
            let timeoutVC = SettingsAppTimeoutVC.make()
            show(timeoutVC, sender: self)
        }
    }
    
    
    @IBAction func didChangeAppLockEnabledSwitch(_ sender: Any) {
        if !appLockEnabledSwitch.isOn {
            Settings.current.isAppLockEnabled = false
            do {
                try Keychain.shared.removeAppPasscode() 
            } catch {
                Diag.error(error.localizedDescription)
                let alert = UIAlertController.make(
                    title: LString.titleKeychainError,
                    message: error.localizedDescription)
                present(alert, animated: true, completion: nil)
            }
        } else {
            let passcodeInputVC = PasscodeInputVC.instantiateFromStoryboard()
            passcodeInputVC.delegate = self
            passcodeInputVC.mode = .setup
            passcodeInputVC.modalPresentationStyle = .formSheet
            passcodeInputVC.isCancelAllowed = true
            present(passcodeInputVC, animated: true, completion: nil)
            self.passcodeInputVC = passcodeInputVC
        }
    }
    
    @IBAction func didChangeLockDatabasesOnFailedPasscodeSwitch(_ sender: UISwitch) {
        Settings.current.isLockAllDatabasesOnFailedPasscode = lockDatabasesOnFailedPasscodeSwitch.isOn
    }
    
    @IBAction func didToggleBiometricsSwitch(_ sender: Any) {
        Settings.current.isBiometricAppLockEnabled = biometricsSwitch.isOn
    }
}

extension SettingsAppLockVC: SettingsObserver {
    func settingsDidChange(key: Settings.Keys) {
        switch key {
        case .appLockEnabled, .appLockTimeout, .biometricAppLockEnabled:
            refresh()
        default:
            break
        }
    }
}

extension SettingsAppLockVC: PasscodeInputDelegate {
    func passcodeInputDidCancel(_ sender: PasscodeInputVC) {
        Settings.current.isAppLockEnabled = false
        passcodeInputVC?.dismiss(animated: true, completion: nil)
        refresh()
    }
    
    func passcodeInput(_sender: PasscodeInputVC, canAcceptPasscode passcode: String) -> Bool {
        return passcode.count > 0
    }
    
    func passcodeInput(_ sender: PasscodeInputVC, didEnterPasscode passcode: String) {
        passcodeInputVC?.dismiss(animated: true) {
            [weak self] in
            do {
                try Keychain.shared.setAppPasscode(passcode)
                Settings.current.isAppLockEnabled = true
            } catch {
                Diag.error(error.localizedDescription)
                let alert = UIAlertController.make(
                    title: LString.titleKeychainError,
                    message: error.localizedDescription)
                self?.present(alert, animated: true, completion: nil)
            }
        }
    }
}
