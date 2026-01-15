//
//  FloorPriceService.swift
//  TongJuanAlter
//
//  Created by Cheney on 1/15/26.
//

import Foundation

struct ProjectTabResponse: Decodable {
    let isSuccess: Bool
    let code: String
    let msg: String
    let data: ProjectTabData
}

struct ProjectTabData: Decodable {
    let projects: [FloorPriceProject]
    let total: Int
}

struct FloorPriceProject: Decodable, Identifiable {
    let project_id: String
    let name: String
    let img_url: String
    let floor_price: String
    let last_trade_price: String

    var id: String { project_id }

    var floorPriceValue: Double {
        Double(floor_price) ?? 0
    }

    var lastTradeValue: Double {
        Double(last_trade_price) ?? 0
    }
}

struct LoginResponse: Decodable {
    let isSuccess: Bool
    let code: String
    let msg: String
    let data: LoginData
}

struct LoginData: Decodable {
    let userID: String
    let accessToken: String
    let expiresIn: Int
}

struct LoginRequest: Encodable {
    let account: String
    let password: String
    let dialingCode: String
    let captcha: String
    let clientInfo: ClientInfo

    struct ClientInfo: Encodable {
        let device: String
        let device_id: String
    }
}

actor APIClient {
    static let shared = APIClient()

    private let baseURL = URL(string: "https://x.gwht.jscaee.cn")!

    func fetchFloorPrice(tabId: String, projectId: String, token: String?) async throws -> FloorPriceProject? {
        var components = URLComponents(url: baseURL.appendingPathComponent("/v1/nft/project/tab/items"), resolvingAgainstBaseURL: false)
        components?.queryItems = [URLQueryItem(name: "tab_id", value: tabId)]
        guard let url = components?.url else {
            throw URLError(.badURL)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "accept")
        request.setValue("application/json", forHTTPHeaderField: "content-type")

        if let token, !token.isEmpty {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "authorization")
        }

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, 200..<300 ~= httpResponse.statusCode else {
            throw URLError(.badServerResponse)
        }

        let decoded = try JSONDecoder().decode(ProjectTabResponse.self, from: data)
        return decoded.data.projects.first { $0.project_id == projectId }
    }

    func login(account: String, password: String) async throws -> LoginData {
        let url = baseURL.appendingPathComponent("/v1/user/auth/login")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "accept")
        request.setValue("application/json", forHTTPHeaderField: "content-type")

        let payload = LoginRequest(
            account: account,
            password: password,
            dialingCode: "+86",
            captcha: "",
            clientInfo: .init(device: "ios", device_id: UUID().uuidString)
        )
        request.httpBody = try JSONEncoder().encode(payload)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, 200..<300 ~= httpResponse.statusCode else {
            throw URLError(.badServerResponse)
        }

        let decoded = try JSONDecoder().decode(LoginResponse.self, from: data)
        return decoded.data
    }
}
