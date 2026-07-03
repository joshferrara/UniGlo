import Foundation
import OSLog

enum UniFiControllerError: Error {
    case invalidConfiguration
    case authenticationFailed
    case ledControlUnsupported
    case ledStateVerificationFailed
    case rateLimited
    case requestFailed
}

actor UniFiControllerClient {
    private let defaultSession: URLSession
    private let insecureSession: URLSession
    private var cookiesByConfig: [String: [HTTPCookie]] = [:]
    private var csrfTokensByConfig: [String: String] = [:]
    private let ledUpdateFields = [
        "name",
        "snmp_contact",
        "snmp_location",
        "mgmt_network_id",
        "afc_enabled",
        "outdoor_mode_override",
        "led_override",
        "led_override_color",
        "led_override_color_brightness",
        "atf_enabled",
        "config_network",
        "mesh_sta_vap_enabled",
        "radio_table"
    ]

    init() {
        let configuration = URLSessionConfiguration.ephemeral  // Use ephemeral to avoid caching
        configuration.timeoutIntervalForRequest = 15
        configuration.timeoutIntervalForResource = 30
        configuration.httpShouldUsePipelining = false  // Disable pipelining like curl
        configuration.httpMaximumConnectionsPerHost = 1  // Single connection like curl
        defaultSession = URLSession(configuration: configuration)

        let insecureConfiguration = URLSessionConfiguration.ephemeral
        insecureConfiguration.timeoutIntervalForRequest = 15
        insecureConfiguration.timeoutIntervalForResource = 30
        insecureConfiguration.httpShouldUsePipelining = false
        insecureConfiguration.httpMaximumConnectionsPerHost = 1
        insecureSession = URLSession(configuration: insecureConfiguration, delegate: InsecureSessionDelegate.shared, delegateQueue: nil)
    }

    func fetchDevices(config: ControllerConfig) async throws -> [AccessPoint] {
        try await fetchDevices(config: config, hasRetriedAfterUnauthorized: false)
    }

    private func fetchDevices(config: ControllerConfig, hasRetriedAfterUnauthorized: Bool) async throws -> [AccessPoint] {
        guard let baseURL = config.baseURL else {
            Logger.network.error("No base URL configured")
            throw UniFiControllerError.invalidConfiguration
        }

        Logger.network.info("Fetching devices from \(baseURL.absoluteString)")

        // Ensure we're logged in first
        try await ensureAuthenticated(config: config)

        // Try newer API path first, then fall back to legacy
        let devicePaths = [
            "/proxy/network/api/s/\(config.site)/stat/device",
            "/api/s/\(config.site)/stat/device"
        ]

        var lastError: Error?

        for path in devicePaths {
            let url = baseURL.appendingPathComponent(path)
            var request = URLRequest(url: url)
            request.httpMethod = "GET"

            Logger.network.info("Trying device request URL: \(url.absoluteString)")

            // Add cookies from authentication
            if let cookies = cookiesByConfig[configKey(config)] {
                let cookieHeaders = HTTPCookie.requestHeaderFields(with: cookies)
                for (key, value) in cookieHeaders {
                    request.addValue(value, forHTTPHeaderField: key)
                }
                Logger.network.info("Added \(cookies.count) cookies to request")
            }

            // Add CSRF token if we have one
            if let csrfToken = csrfTokensByConfig[configKey(config)] {
                request.addValue(csrfToken, forHTTPHeaderField: "X-Csrf-Token")
                Logger.network.info("Added CSRF token to request")
            }

            do {
                let (data, response) = try await session(for: config).data(for: request)
                guard let httpResponse = response as? HTTPURLResponse else {
                    Logger.network.error("Invalid response type")
                    lastError = UniFiControllerError.requestFailed
                    continue
                }

                Logger.network.info("Response status code: \(httpResponse.statusCode)")

                // If 404, try next path
                if httpResponse.statusCode == 404 {
                    Logger.network.info("Got 404, trying next path...")
                    continue
                }

                // If 401, clear cookies and CSRF token, then retry once
                if httpResponse.statusCode == 401 {
                    guard !hasRetriedAfterUnauthorized else {
                        Logger.network.error("Device request still unauthorized after re-authentication")
                        throw UniFiControllerError.authenticationFailed
                    }
                    Logger.network.warning("Got 401 unauthorized, clearing cookies and retrying")
                    clearAuthentication(for: config)
                    return try await fetchDevices(config: config, hasRetriedAfterUnauthorized: true)
                }

                guard (200..<300).contains(httpResponse.statusCode) else {
                    Logger.network.error("Request failed with status code: \(httpResponse.statusCode)")
                    if let dataString = String(data: data, encoding: .utf8) {
                        Logger.network.debug("Response: \(dataString)")
                    }
                    lastError = UniFiControllerError.requestFailed
                    continue
                }

                // Success! Decode the response
                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = .secondsSince1970
                do {
                    let envelope = try decoder.decode(DeviceEnvelope.self, from: data)
                    Logger.network.info("Successfully decoded \(envelope.data.count) devices from \(path)")
                    let accessPoints = envelope.data.compactMap { $0.toAccessPoint() }
                    Logger.network.info("Filtered to \(accessPoints.count) access points")
                    return accessPoints
                } catch {
                    Logger.network.error("Failed to decode device response: \(error.localizedDescription, privacy: .public)")
                    Logger.network.error("Decoding error details: \(String(describing: error), privacy: .public)")
                    if let dataString = String(data: data, encoding: .utf8) {
                        Logger.network.debug("Response data: \(dataString, privacy: .public)")
                    }
                    lastError = UniFiControllerError.requestFailed
                    continue  // Try next path instead of throwing
                }
            } catch {
                Logger.network.error("Error fetching devices from \(path): \(error.localizedDescription)")
                lastError = error
            }
        }

        throw lastError ?? UniFiControllerError.requestFailed
    }

    private func ensureAuthenticated(config: ControllerConfig) async throws {
        // Check if we already have valid cookies
        if cookiesByConfig[configKey(config)] != nil {
            return
        }

        // Perform login
        try await login(config: config)
    }

    private func login(config: ControllerConfig) async throws {
        guard let baseURL = config.baseURL else {
            Logger.network.error("Cannot login: no base URL configured")
            throw UniFiControllerError.invalidConfiguration
        }

        let loginPaths = ["/proxy/network/api/auth/login", "/api/auth/login", "/api/login"]
        var lastError: Error?

        for path in loginPaths {
            // Remove trailing slash from baseURL and construct full URL string
            let baseURLString = baseURL.absoluteString.hasSuffix("/")
                ? String(baseURL.absoluteString.dropLast())
                : baseURL.absoluteString
            guard let loginURL = URL(string: baseURLString + path) else {
                Logger.network.error("Failed to construct login URL for path: \(path)")
                continue
            }
            Logger.network.info("Attempting login to \(loginURL.absoluteString)")
            Logger.network.info("Username: \(config.username)")

            var request = URLRequest(url: loginURL)
            request.httpMethod = "POST"
            request.addValue("application/json", forHTTPHeaderField: "Content-Type")
            request.addValue("UniFi LED Controller/1.0", forHTTPHeaderField: "User-Agent")
            request.addValue("*/*", forHTTPHeaderField: "Accept")

            // DO NOT add Origin and Referer - they cause 403 Forbidden errors
            // The UniFi controller accepts requests without these CSRF headers

            Logger.network.info("Full request URL: \(loginURL.absoluteString, privacy: .public)")
            Logger.network.info("Request headers: \(request.allHTTPHeaderFields ?? [:], privacy: .public)")

            // Manually construct JSON to guarantee exact field order (username before password)
            // Must properly escape JSON string values
            func escapeJSON(_ string: String) -> String {
                return string
                    .replacingOccurrences(of: "\\", with: "\\\\")
                    .replacingOccurrences(of: "\"", with: "\\\"")
                    .replacingOccurrences(of: "\n", with: "\\n")
                    .replacingOccurrences(of: "\r", with: "\\r")
                    .replacingOccurrences(of: "\t", with: "\\t")
            }
            let jsonString = "{\"username\":\"\(escapeJSON(config.username))\",\"password\":\"\(escapeJSON(config.password))\"}"
            request.httpBody = jsonString.data(using: .utf8)

            Logger.network.debug("Request body prepared (credentials redacted)")

            do {
                let (data, response) = try await session(for: config).data(for: request)

                guard let httpResponse = response as? HTTPURLResponse else {
                    Logger.network.error("Invalid response type during login")
                    throw UniFiControllerError.requestFailed
                }

                Logger.network.info("Login response status code: \(httpResponse.statusCode)")

                if httpResponse.statusCode == 404 {
                    Logger.network.info("Login path not found, trying next path: \(path)")
                    continue
                }

                if !(200..<300).contains(httpResponse.statusCode) {
                    if let dataString = String(data: data, encoding: .utf8) {
                        Logger.network.error("Login failed. Response: \(dataString, privacy: .public)")
                    }
                    throw classifyLoginFailure(data: data, statusCode: httpResponse.statusCode)
                }

                // Extract and store cookies
                if let headerFields = httpResponse.allHeaderFields as? [String: String],
                   let url = httpResponse.url {
                    let cookies = HTTPCookie.cookies(withResponseHeaderFields: headerFields, for: url)
                    Logger.network.info("Login successful via \(path). Received \(cookies.count) cookies")
                    cookiesByConfig[configKey(config)] = cookies

                    // Extract CSRF token from response header
                    if let csrfToken = headerFields["x-csrf-token"] ?? headerFields["X-Csrf-Token"] {
                        Logger.network.info("Received CSRF token")
                        csrfTokensByConfig[configKey(config)] = csrfToken
                    }

                    return
                } else {
                    Logger.network.warning("Login succeeded via \(path) but no cookies received")
                    cookiesByConfig[configKey(config)] = []
                    return
                }
            } catch {
                Logger.network.error("Login error via \(path): \(error.localizedDescription)")
                lastError = error
            }
        }

        throw lastError ?? UniFiControllerError.authenticationFailed
    }

    private func configKey(_ config: ControllerConfig) -> String {
        return "\(config.baseURL?.absoluteString ?? "")_\(config.username)"
    }

    private func clearAuthentication(for config: ControllerConfig) {
        cookiesByConfig[configKey(config)] = nil
        csrfTokensByConfig[configKey(config)] = nil
    }

    private func classifyLoginFailure(data: Data, statusCode: Int) -> UniFiControllerError {
        if statusCode == 429 {
            Logger.network.error("Login was rate limited with HTTP 429")
            return .rateLimited
        }

        if let responseText = String(data: data, encoding: .utf8)?.lowercased() {
            if responseText.contains("authentication_failed_limit_reached") ||
                responseText.contains("login attempt limit") {
                Logger.network.error("Login attempt limit reached")
                return .rateLimited
            }

            if responseText.contains("invalid username or password") ||
                responseText.contains("authentication_failed_invalid_credentials") {
                return .authenticationFailed
            }
        }

        if statusCode == 401 {
            return .authenticationFailed
        }

        return .requestFailed
    }

    func toggleLED(config: ControllerConfig, enable: Bool) async throws {
        let devices = try await fetchDevices(config: config)

        guard !devices.isEmpty else {
            Logger.network.warning("No access points available for bulk LED toggle")
            return
        }

        for device in devices {
            try await toggleDeviceLED(config: config, deviceId: device.deviceId, enable: enable)
        }
    }

    func toggleDeviceLED(config: ControllerConfig, deviceId: String, enable: Bool) async throws {
        try await toggleDeviceLED(config: config, deviceId: deviceId, enable: enable, hasRetriedAfterUnauthorized: false)
    }

    private func toggleDeviceLED(config: ControllerConfig, deviceId: String, enable: Bool, hasRetriedAfterUnauthorized: Bool) async throws {
        guard let baseURL = config.baseURL else {
            throw UniFiControllerError.invalidConfiguration
        }

        // Ensure we're logged in first
        try await ensureAuthenticated(config: config)

        // Try newer API path first, then fall back to legacy
        let devicePaths = [
            "/proxy/network/api/s/\(config.site)/rest/device/\(deviceId)",
            "/api/s/\(config.site)/rest/device/\(deviceId)"
        ]

        let payload = try await deviceLEDUpdatePayload(config: config, deviceId: deviceId, enable: enable)
        var lastError: Error?

        for path in devicePaths {
            var request = URLRequest(url: baseURL.appendingPathComponent(path))
            request.httpMethod = "PUT"
            request.addValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: payload)

            Logger.network.info("Toggling LED for device \(deviceId) to \(enable ? "on" : "off")")

            // Add cookies from authentication
            if let cookies = cookiesByConfig[configKey(config)] {
                let cookieHeaders = HTTPCookie.requestHeaderFields(with: cookies)
                for (key, value) in cookieHeaders {
                    request.addValue(value, forHTTPHeaderField: key)
                }
            }

            // Add CSRF token if we have one
            if let csrfToken = csrfTokensByConfig[configKey(config)] {
                request.addValue(csrfToken, forHTTPHeaderField: "X-Csrf-Token")
            }

            do {
                let (data, response) = try await session(for: config).data(for: request)
                guard let httpResponse = response as? HTTPURLResponse else {
                    lastError = UniFiControllerError.requestFailed
                    continue
                }

                Logger.network.info("Device LED toggle response status: \(httpResponse.statusCode)")

                // If 404, try next path
                if httpResponse.statusCode == 404 {
                    continue
                }

                // If 401, clear cookies and retry once
                if httpResponse.statusCode == 401 {
                    guard !hasRetriedAfterUnauthorized else {
                        throw UniFiControllerError.authenticationFailed
                    }
                    clearAuthentication(for: config)
                    return try await toggleDeviceLED(config: config, deviceId: deviceId, enable: enable, hasRetriedAfterUnauthorized: true)
                }

                if !(200..<300).contains(httpResponse.statusCode) {
                    if let dataString = String(data: data, encoding: .utf8) {
                        Logger.network.error("Device LED toggle failed. Response: \(dataString)")
                    }
                    lastError = UniFiControllerError.requestFailed
                    continue
                }

                // Success!
                Logger.network.info("Successfully toggled LED for device \(deviceId)")
                try await verifyDeviceLEDOverride(config: config, deviceId: deviceId, enable: enable)
                return
            } catch {
                Logger.network.error("Error toggling device LED: \(error.localizedDescription)")
                lastError = error
            }
        }

        throw lastError ?? UniFiControllerError.requestFailed
    }

    private func verifyDeviceLEDOverride(config: ControllerConfig, deviceId: String, enable: Bool) async throws {
        try? await Task.sleep(for: .seconds(1))
        let deviceConfig = try await fetchRawDeviceConfig(config: config, deviceId: deviceId)
        let expected = enable ? "on" : "off"
        let actual = deviceConfig["led_override"] as? String

        guard actual == expected else {
            Logger.network.error("LED override verification failed for device \(deviceId): expected \(expected), got \(actual ?? "missing")")
            throw UniFiControllerError.ledStateVerificationFailed
        }

        Logger.network.info("Verified LED override for device \(deviceId)")
    }

    private func deviceLEDUpdatePayload(config: ControllerConfig, deviceId: String, enable: Bool) async throws -> [String: Any] {
        let deviceConfig = try await fetchRawDeviceConfig(config: config, deviceId: deviceId)

        guard deviceConfig["led_override"] != nil else {
            Logger.network.error("Device \(deviceId) does not expose led_override in its configuration")
            throw UniFiControllerError.ledControlUnsupported
        }

        var payload: [String: Any] = ["_id": deviceId]
        for field in ledUpdateFields {
            if let value = deviceConfig[field] {
                payload[field] = value
            }
        }
        payload["led_override"] = enable ? "on" : "off"
        return payload
    }

    private func fetchRawDeviceConfig(config: ControllerConfig, deviceId: String, hasRetriedAfterUnauthorized: Bool = false) async throws -> [String: Any] {
        guard let baseURL = config.baseURL else {
            throw UniFiControllerError.invalidConfiguration
        }

        try await ensureAuthenticated(config: config)

        let devicePaths = [
            "/proxy/network/api/s/\(config.site)/stat/device",
            "/api/s/\(config.site)/stat/device"
        ]
        var lastError: Error?

        for path in devicePaths {
            var request = URLRequest(url: baseURL.appendingPathComponent(path))
            request.httpMethod = "GET"
            addAuthenticationHeaders(to: &request, config: config)

            do {
                let (data, response) = try await session(for: config).data(for: request)
                guard let httpResponse = response as? HTTPURLResponse else {
                    lastError = UniFiControllerError.requestFailed
                    continue
                }

                if httpResponse.statusCode == 404 {
                    continue
                }

                if httpResponse.statusCode == 401 {
                    guard !hasRetriedAfterUnauthorized else {
                        throw UniFiControllerError.authenticationFailed
                    }
                    clearAuthentication(for: config)
                    return try await fetchRawDeviceConfig(config: config, deviceId: deviceId, hasRetriedAfterUnauthorized: true)
                }

                guard (200..<300).contains(httpResponse.statusCode) else {
                    lastError = UniFiControllerError.requestFailed
                    continue
                }

                guard let envelope = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let devices = envelope["data"] as? [[String: Any]] else {
                    throw UniFiControllerError.requestFailed
                }

                if let device = devices.first(where: { $0["_id"] as? String == deviceId }) {
                    return device
                }
            } catch {
                lastError = error
            }
        }

        throw lastError ?? UniFiControllerError.requestFailed
    }

    private func addAuthenticationHeaders(to request: inout URLRequest, config: ControllerConfig) {
        if let cookies = cookiesByConfig[configKey(config)] {
            let cookieHeaders = HTTPCookie.requestHeaderFields(with: cookies)
            for (key, value) in cookieHeaders {
                request.addValue(value, forHTTPHeaderField: key)
            }
        }

        if let csrfToken = csrfTokensByConfig[configKey(config)] {
            request.addValue(csrfToken, forHTTPHeaderField: "X-Csrf-Token")
        }
    }

    private func session(for config: ControllerConfig) -> URLSession {
        config.acceptInvalidCertificates ? insecureSession : defaultSession
    }

    private final class InsecureSessionDelegate: NSObject, URLSessionDelegate {
        static let shared = InsecureSessionDelegate()

        private override init() { }

        func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge, completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
            if let trust = challenge.protectionSpace.serverTrust {
                completionHandler(.useCredential, URLCredential(trust: trust))
            } else {
                completionHandler(.performDefaultHandling, nil)
            }
        }
    }

    private struct DeviceEnvelope: Decodable {
        let data: [Device]
    }

    private struct Device: Decodable {
        let _id: String?  // UniFi uses _id, not deviceId
        let name: String?
        let ip: String?
        let mac: String
        let type: String?  // Device type (e.g., "uap" for access point, "usw" for switch)
        let model: String?
        let ledOverride: String?  // Can be "on", "off", or "default"
        let ledOverrideColorBrightness: Int?
        let ledEnabled: Bool?
        let lastSeen: TimeInterval?
        let state: Int?

        enum CodingKeys: String, CodingKey {
            case _id, name, ip, mac, type, model
            case ledOverride = "led_override"
            case ledOverrideColorBrightness = "led_override_color_brightness"
            case ledEnabled = "led_enabled"
            case lastSeen = "last_seen"
            case state
        }

        func toAccessPoint() -> AccessPoint? {
            // Only return access points. Some gateways also have model IDs that
            // start with "U", so the UniFi device type is the safer filter.
            guard type == "uap" else {
                return nil
            }

            // Require device ID for API calls
            guard let deviceId = _id else {
                return nil
            }

            return AccessPoint(
                deviceId: deviceId,
                name: name ?? model ?? mac,
                ipAddress: ip ?? "",
                macAddress: mac,
                ledEnabled: ledOverride == "on" || (ledOverride != "off" && (ledEnabled ?? true)),
                lastSeen: Date(timeIntervalSince1970: lastSeen ?? 0),
                tags: [],
                isOnline: (state ?? 0) == 1
            )
        }
    }
}
