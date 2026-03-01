import Foundation

/// Syncs sleep data from HealthKit to the backend for agent access.
/// Uses the same JWT auth flow as PatternAPIService.
actor AgentSyncService {

    enum SyncError: LocalizedError {
        case notConfigured
        case notEnabled
        case networkError(String)
        case authenticationFailed

        var errorDescription: String? {
            switch self {
            case .notConfigured:
                return "API endpoint is not configured."
            case .notEnabled:
                return "Agent access is not enabled."
            case .networkError(let message):
                return message
            case .authenticationFailed:
                return "Could not authenticate with the server."
            }
        }
    }

    struct RegisterResponse: Decodable {
        let apiKey: String
        let connectionCode: String
    }

    struct SyncResponse: Decodable {
        let synced: Int
        let syncedAt: String
    }

    struct RevokeResponse: Decodable {
        let revoked: Bool
    }

    private let baseURL: URL?
    private let urlSession: URLSession
    private let keyManager: DeviceKeyManager

    // Cache the JWT from PatternAPIService's auth flow
    private var cachedToken: (value: String, expiry: Date)?

    init(
        baseURL: URL? = PatternAPIService.defaultBaseURL(),
        urlSession: URLSession = .shared,
        keyManager: DeviceKeyManager = DeviceKeyManager()
    ) {
        self.baseURL = baseURL
        self.urlSession = urlSession
        self.keyManager = keyManager
    }

    // MARK: - Agent Key Registration

    /// Register an API key for agent access. Returns the connection code.
    func registerApiKey() async throws -> RegisterResponse {
        guard let baseURL else { throw SyncError.notConfigured }

        let token = try await validAccessToken(forceRefresh: false)
        var request = URLRequest(url: baseURL.appendingPathComponent("v1/agent/register"))
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let (data, response) = try await urlSession.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw SyncError.networkError("Invalid response")
        }

        if http.statusCode == 401 {
            // Retry with fresh token
            let freshToken = try await validAccessToken(forceRefresh: true)
            request.setValue("Bearer \(freshToken)", forHTTPHeaderField: "Authorization")
            let (retryData, retryResponse) = try await urlSession.data(for: request)
            guard let retryHttp = retryResponse as? HTTPURLResponse,
                  (200...299).contains(retryHttp.statusCode) else {
                throw SyncError.authenticationFailed
            }
            return try JSONDecoder().decode(RegisterResponse.self, from: retryData)
        }

        guard (200...299).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw SyncError.networkError("Registration failed (\(http.statusCode)): \(body)")
        }

        return try JSONDecoder().decode(RegisterResponse.self, from: data)
    }

    /// Revoke agent access and delete all synced data.
    func revokeAccess() async throws {
        guard let baseURL else { throw SyncError.notConfigured }

        let token = try await validAccessToken(forceRefresh: false)
        var request = URLRequest(url: baseURL.appendingPathComponent("v1/agent/revoke"))
        request.httpMethod = "DELETE"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await urlSession.data(for: request)
        guard let http = response as? HTTPURLResponse,
              (200...299).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw SyncError.networkError("Revocation failed: \(body)")
        }
    }

    // MARK: - Data Sync

    /// Sync sleep data to the backend (encrypted at rest on the server).
    func syncDays(_ payload: AgentSyncPayload) async throws -> SyncResponse {
        guard let baseURL else { throw SyncError.notConfigured }

        let token = try await validAccessToken(forceRefresh: false)

        var request = URLRequest(url: baseURL.appendingPathComponent("v1/data/sync"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONEncoder().encode(payload)

        let (data, response) = try await urlSession.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw SyncError.networkError("Invalid response")
        }

        if http.statusCode == 401 {
            let freshToken = try await validAccessToken(forceRefresh: true)
            request.setValue("Bearer \(freshToken)", forHTTPHeaderField: "Authorization")
            let (retryData, retryResponse) = try await urlSession.data(for: request)
            guard let retryHttp = retryResponse as? HTTPURLResponse,
                  (200...299).contains(retryHttp.statusCode) else {
                throw SyncError.authenticationFailed
            }
            return try JSONDecoder().decode(SyncResponse.self, from: retryData)
        }

        guard (200...299).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw SyncError.networkError("Sync failed (\(http.statusCode)): \(body)")
        }

        return try JSONDecoder().decode(SyncResponse.self, from: data)
    }

    // MARK: - JWT Auth (reuses same flow as PatternAPIService)

    private func validAccessToken(forceRefresh: Bool) async throws -> String {
        if !forceRefresh,
           let cachedToken,
           cachedToken.expiry.timeIntervalSinceNow > 30 {
            return cachedToken.value
        }

        guard let baseURL else { throw SyncError.notConfigured }

        let installID = keyManager.installID()
        let publicKey = try keyManager.publicKeyBase64()

        // Step 1: Get challenge
        let challengeBody = ChallengeBody(installId: installID, publicKey: publicKey)
        let challengeResponse: ChallengeResponse = try await postJSON(
            path: "v1/auth/challenge",
            baseURL: baseURL,
            body: challengeBody
        )

        // Step 2: Sign challenge
        let signature = try keyManager.signatureBase64(for: Data(challengeResponse.challengeToken.utf8))

        // Step 3: Exchange for JWT
        let exchangeBody = ExchangeBody(
            installId: challengeResponse.installId,
            publicKey: publicKey,
            challengeToken: challengeResponse.challengeToken,
            signature: signature
        )
        let exchangeResponse: ExchangeResponse = try await postJSON(
            path: "v1/auth/exchange",
            baseURL: baseURL,
            body: exchangeBody
        )

        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard let expiry = isoFormatter.date(from: exchangeResponse.expiresAt) else {
            throw SyncError.networkError("Invalid token expiry")
        }

        cachedToken = (value: exchangeResponse.accessToken, expiry: expiry)
        return exchangeResponse.accessToken
    }

    private func postJSON<Body: Encodable, Output: Decodable>(
        path: String,
        baseURL: URL,
        body: Body
    ) async throws -> Output {
        let endpoint = baseURL.appendingPathComponent(path)
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await urlSession.data(for: request)
        guard let http = response as? HTTPURLResponse,
              (200...299).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw SyncError.networkError("Request failed: \(body)")
        }

        return try JSONDecoder().decode(Output.self, from: data)
    }

    // MARK: - Request Models

    private struct ChallengeBody: Encodable {
        let installId: String
        let publicKey: String
    }

    private struct ChallengeResponse: Decodable {
        let installId: String
        let challengeToken: String
        let expiresAt: String
    }

    private struct ExchangeBody: Encodable {
        let installId: String
        let publicKey: String
        let challengeToken: String
        let signature: String
    }

    private struct ExchangeResponse: Decodable {
        let accessToken: String
        let expiresAt: String
    }
}

// MARK: - Sync Payload (matches backend dataSyncRequestSchema)

struct AgentSyncPayload: Codable {
    let days: [PatternDayPayload]
}

// MARK: - Agent Settings Persistence

enum AgentSettings {
    private static let keychainService = "com.adithya.sleeplab.agent"
    private static let apiKeyAccount = "agent-api-key"
    private static let connectionCodeAccount = "agent-connection-code"
    private static let enabledKey = "agent.sync.enabled"
    private static let lastSyncKey = "agent.sync.lastSync"

    static var isEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: enabledKey) }
        set { UserDefaults.standard.set(newValue, forKey: enabledKey) }
    }

    static var lastSyncDate: Date? {
        get { UserDefaults.standard.object(forKey: lastSyncKey) as? Date }
        set { UserDefaults.standard.set(newValue, forKey: lastSyncKey) }
    }

    /// Stored in Keychain so it persists across app reinstalls.
    static var apiKey: String? {
        get { keychainRead(account: apiKeyAccount) }
        set {
            if let newValue {
                keychainWrite(account: apiKeyAccount, value: newValue)
            } else {
                keychainDelete(account: apiKeyAccount)
            }
        }
    }

    static var connectionCode: String? {
        get { keychainRead(account: connectionCodeAccount) }
        set {
            if let newValue {
                keychainWrite(account: connectionCodeAccount, value: newValue)
            } else {
                keychainDelete(account: connectionCodeAccount)
            }
        }
    }

    static func clearAll() {
        isEnabled = false
        lastSyncDate = nil
        apiKey = nil
        connectionCode = nil
    }

    // MARK: - Keychain Helpers

    private static func keychainRead(account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private static func keychainWrite(account: String, value: String) {
        guard let data = value.data(using: .utf8) else { return }

        // Try to update first
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: account
        ]
        let update: [String: Any] = [kSecValueData as String: data]

        let updateStatus = SecItemUpdate(query as CFDictionary, update as CFDictionary)
        if updateStatus == errSecSuccess { return }

        // If not found, add new
        var attributes = query
        attributes[kSecValueData as String] = data
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(attributes as CFDictionary, nil)
    }

    private static func keychainDelete(account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }
}
