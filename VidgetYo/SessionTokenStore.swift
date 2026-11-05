import Foundation
import Security

struct SessionTokenStore: Sendable {
    var service: String

    static let production = SessionTokenStore(service: "local.vidgetyo.session")

    private enum Account {
        static let access = "accessToken"
        static let refresh = "refreshToken"
    }

    func load() -> (access: String, refresh: String) {
        (
            read(account: Account.access) ?? "",
            read(account: Account.refresh) ?? ""
        )
    }

    func save(access: String, refresh: String) {
        write(account: Account.access, value: access)
        write(account: Account.refresh, value: refresh)
    }

    func clear() {
        delete(account: Account.access)
        delete(account: Account.refresh)
    }

    func migrateFromUserDefaults(
        _ defaults: UserDefaults,
        accessKey: String,
        refreshKey: String
    ) {
        let legacyAccess = defaults.string(forKey: accessKey) ?? ""
        let legacyRefresh = defaults.string(forKey: refreshKey) ?? ""
        guard !legacyAccess.isEmpty || !legacyRefresh.isEmpty else { return }

        let current = load()
        if current.access.isEmpty, current.refresh.isEmpty {
            save(access: legacyAccess, refresh: legacyRefresh)
        }
        defaults.removeObject(forKey: accessKey)
        defaults.removeObject(forKey: refreshKey)
    }

    private func read(account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private func write(account: String, value: String) {
        delete(account: account)
        guard let data = value.data(using: .utf8) else { return }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
        ]
        SecItemAdd(query as CFDictionary, nil)
    }

    private func delete(account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }
}
