import Foundation
import Capacitor
import WidgetKit
import Security

/// يستلم من الواجهة جدول الورديات والتقويم والثيم ويحفظها في App Group ليقرأها ويدجت الشاشة الرئيسية.
@objc(ShiftWidgetPlugin)
public class ShiftWidgetPlugin: CAPPlugin, CAPBridgedPlugin {
    public let identifier = "ShiftWidgetPlugin"
    public let jsName = "ShiftWidget"
    public let pluginMethods: [CAPPluginMethod] = [
        CAPPluginMethod(name: "update", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "setTheme", returnType: CAPPluginReturnPromise),
    ]

    private var group: String? { Bundle.main.object(forInfoDictionaryKey: "KeychainGroup") as? String }

    /// يحفظ في Keychain مشترك مع ويدجت الشاشة الرئيسية
    private func save(_ key: String, _ value: String) -> Bool {
        guard let g = group else { return false }
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "petro.widget",
            kSecAttrAccount as String: key,
            kSecAttrAccessGroup as String: g,
        ]
        SecItemDelete(base as CFDictionary)
        var add = base
        add[kSecValueData as String] = Data(value.utf8)
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        return SecItemAdd(add as CFDictionary, nil) == errSecSuccess
    }
    private let themes = ["petro", "dark", "ocean", "sunset", "glass"]

    @objc func update(_ call: CAPPluginCall) {
        guard let data = call.getString("data"), data.hasPrefix("v1;"), data.count <= 20000 else {
            call.reject("invalid data"); return
        }
        let cal = call.getString("cal")
        if let c = cal, !(c.hasPrefix("c1;") && c.count <= 20000) { call.reject("invalid data"); return }
        guard save("data", data) else { call.reject("keychain unavailable"); return }
        if let c = cal { _ = save("cal", c) }
        if let t = call.getString("theme"), themes.contains(t) { _ = save("theme", t) }
        WidgetCenter.shared.reloadAllTimelines()
        call.resolve()
    }

    @objc func setTheme(_ call: CAPPluginCall) {
        guard let t = call.getString("theme"), themes.contains(t) else { call.reject("invalid theme"); return }
        guard save("theme", t) else { call.reject("keychain unavailable"); return }
        WidgetCenter.shared.reloadAllTimelines()
        call.resolve()
    }
}
