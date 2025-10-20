import Foundation
import OSLog

enum UniFiControllerError: Error {
    case invalidConfiguration
    case authenticationFailed
    case requestFailed
}

actor UniFiControllerClient {
    private let defaultSession: URLSession
    private let insecureSession: URLSession
    private var cookiesByConfig: [String: [HTTPCookie]] = [:]
    private var csrfTokensByConfig: [String: String] = [:]

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
        guard let baseURL = config.baseURL else {
            Logger.network.error("No base URL configured")
            return []
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
                    Logger.network.warning("Got 401 unauthorized, clearing cookies and retrying")
                    cookiesByConfig[configKey(config)] = nil
                    csrfTokensByConfig[configKey(config)] = nil
                    return try await fetchDevices(config: config)
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

            // Log the request body for debugging
            if let bodyData = request.httpBody, let bodyString = String(data: bodyData, encoding: .utf8) {
                Logger.network.info("Request body: \(bodyString, privacy: .public)")
            }

            do {
                let (data, response) = try await session(for: config).data(for: request)

                guard let httpResponse = response as? HTTPURLResponse else {
                    Logger.network.error("Invalid response type during login")
                    throw UniFiControllerError.requestFailed
                }

                Logger.network.info("Login response status code: \(httpResponse.statusCode)")

                if !(200..<300).contains(httpResponse.statusCode) {
                    if let dataString = String(data: data, encoding: .utf8) {
                        Logger.network.error("Login failed. Response: \(dataString, privacy: .public)")
                    }
                    // Log all response headers to debug 403
                    Logger.network.info("Response headers: \(httpResponse.allHeaderFields, privacy: .public)")
                    lastError = UniFiControllerError.authenticationFailed
                    continue
                }

                // Extract and store cookies
                if let headerFields = httpResponse.allHeaderFields as? [String: String],
                   let url = httpResponse.url {
                    let cookies = HTTPCookie.cookies(withResponseHeaderFields: headerFields, for: url)
                    Logger.network.info("Login successful via \(path). Received \(cookies.count) cookies")
                    cookiesByConfig[configKey(config)] = cookies

                    // Extract CSRF token from response header
                    if let csrfToken = headerFields["x-csrf-token"] ?? headerFields["X-Csrf-Token"] {
                        Logger.network.info("Received CSRF token: \(csrfToken)")
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

    func toggleLED(config: ControllerConfig, enable: Bool) async throws {
        guard let baseURL = config.baseURL else { return }

        // Ensure we're logged in first
        try await ensureAuthenticated(config: config)

        // Try newer API path first, then fall back to legacy
        let ledPaths = [
            "/proxy/network/api/s/\(config.site)/set/setting/mgmt",
            "/api/s/\(config.site)/set/setting/mgmt"
        ]

        var lastError: Error?

        for path in ledPaths {
            var request = URLRequest(url: baseURL.appendingPathComponent(path))
            request.httpMethod = "POST"
            request.addValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONEncoder().encode(["led_enabled": enable])

            // Add cookies from authentication
            if let cookies = cookiesByConfig[configKey(config)] {
                let cookieHeaders = HTTPCookie.requestHeaderFields(with: cookies)
                for (key, value) in cookieHeaders {
                    request.addValue(value, forHTTPHeaderField: key)
                }
            }

            do {
                let (_, response) = try await session(for: config).data(for: request)
                guard let httpResponse = response as? HTTPURLResponse else {
                    lastError = UniFiControllerError.requestFailed
                    continue
                }

                // If 404, try next path
                if httpResponse.statusCode == 404 {
                    continue
                }

                // If 401, clear cookies and retry once
                if httpResponse.statusCode == 401 {
                    cookiesByConfig[configKey(config)] = nil
                    return try await toggleLED(config: config, enable: enable)
                }

                guard (200..<300).contains(httpResponse.statusCode) else {
                    lastError = UniFiControllerError.requestFailed
                    continue
                }

                // Success!
                return
            } catch {
                lastError = error
            }
        }

        throw lastError ?? UniFiControllerError.requestFailed
    }

    func toggleDeviceLED(config: ControllerConfig, deviceId: String, enable: Bool) async throws {
        guard let baseURL = config.baseURL else { return }

        // Ensure we're logged in first
        try await ensureAuthenticated(config: config)

        // Try newer API path first, then fall back to legacy
        let devicePaths = [
            "/proxy/network/api/s/\(config.site)/rest/device/\(deviceId)",
            "/api/s/\(config.site)/rest/device/\(deviceId)"
        ]

        var lastError: Error?

        for path in devicePaths {
            var request = URLRequest(url: baseURL.appendingPathComponent(path))
            request.httpMethod = "PUT"
            request.addValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONEncoder().encode(["led_override": enable ? "on" : "off"])

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
                    cookiesByConfig[configKey(config)] = nil
                    csrfTokensByConfig[configKey(config)] = nil
                    return try await toggleDeviceLED(config: config, deviceId: deviceId, enable: enable)
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
                return
            } catch {
                Logger.network.error("Error toggling device LED: \(error.localizedDescription)")
                lastError = error
            }
        }

        throw lastError ?? UniFiControllerError.requestFailed
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
            // Only return access points (type "uap" or model starting with "U")
            guard let type = type, type == "uap" || model?.starts(with: "U") == true else {
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
