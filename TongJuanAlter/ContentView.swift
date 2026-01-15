//
//  ContentView.swift
//  TongJuanAlter
//
//  Created by Cheney on 1/15/26.
//

import SwiftUI
import UIKit
import UserNotifications

struct ContentView: View {
    @StateObject private var viewModel = FloorPriceViewModel()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    priceHeader
                    statusCard
                    SparklineCard(prices: viewModel.priceHistory, lastUpdated: viewModel.lastUpdated)
                    settingsCard
                    accountCard
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 24)
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle("地板价提醒")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await viewModel.refreshNow() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .accessibilityLabel("立即刷新")
                }
            }
        }
        .task {
            await viewModel.start()
        }
        .alert("请求失败", isPresented: $viewModel.showingError) {
            Button("确定", role: .cancel) { }
        } message: {
            Text(viewModel.errorMessage)
        }
    }

    private var priceHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(viewModel.projectName)
                .font(.title2.weight(.semibold))

            HStack(alignment: .center, spacing: 16) {
                PriceBadge(price: viewModel.floorPrice, trend: viewModel.trend)
                VStack(alignment: .leading, spacing: 6) {
                    Text("当前地板价")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text(viewModel.floorPriceFormatted)
                        .font(.title.bold())
                    Text("最近成交价 \(viewModel.lastTradePriceFormatted)")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var statusCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("自动刷新", systemImage: "clock")
                    .font(.headline)
                Spacer()
                Text("每 3 分钟")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            if let lastUpdated = viewModel.lastUpdated {
                Text("上次更新：\(lastUpdated.formatted(date: .abbreviated, time: .shortened))")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            HStack {
                if viewModel.isLoading {
                    ProgressView()
                        .progressViewStyle(.circular)
                }
                Text(viewModel.statusText)
                    .font(.subheadline)
                    .foregroundStyle(viewModel.statusColor)
            }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 20).fill(Color(uiColor: .secondarySystemGroupedBackground)))
    }

    private var settingsCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("价格预警", systemImage: "bell")
                .font(.headline)

            Toggle("启用最低价提醒", isOn: $viewModel.notificationsEnabled)

            HStack {
                Text("最低价")
                Spacer()
                TextField("输入最低价", text: $viewModel.minimumPrice)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 140)
            }

            Text("当价格低于设定值时，将推送提醒并震动。")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 20).fill(Color(uiColor: .secondarySystemGroupedBackground)))
    }

    private var accountCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("账号登录", systemImage: "person")
                .font(.headline)

            TextField("手机号", text: $viewModel.account)
                .textContentType(.telephoneNumber)
                .keyboardType(.phonePad)
                .textFieldStyle(.roundedBorder)

            SecureField("密码", text: $viewModel.password)
                .textContentType(.password)
                .textFieldStyle(.roundedBorder)

            Button {
                Task { await viewModel.login() }
            } label: {
                HStack {
                    if viewModel.isLoggingIn {
                        ProgressView()
                    }
                    Text(viewModel.isLoggedIn ? "已登录" : "登录以获取 Token")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 20).fill(Color(uiColor: .secondarySystemGroupedBackground)))
    }
}

final class FloorPriceViewModel: ObservableObject {
    @AppStorage("account") var account: String = ""
    @AppStorage("password") var password: String = ""
    @AppStorage("accessToken") var accessToken: String = ""
    @AppStorage("minimumPrice") var minimumPrice: String = "120"
    @AppStorage("notificationsEnabled") var notificationsEnabled: Bool = true

    @Published var floorPrice: Double = 0
    @Published var lastTradePrice: Double = 0
    @Published var lastUpdated: Date?
    @Published var isLoading = false
    @Published var isLoggingIn = false
    @Published var showingError = false
    @Published var errorMessage = ""
    @Published var projectName = "国文通卷"
    @Published var priceHistory: [Double] = []
    @Published var trend: PriceTrend = .flat

    private let tabId = "a8f56062-6a5e-4852-9ede-7377128d427e"
    private let projectId = "51413706-fa41-4577-b530-075d57d551b5"
    private var refreshTask: Task<Void, Never>?

    var isLoggedIn: Bool {
        !accessToken.isEmpty
    }

    var floorPriceFormatted: String {
        String(format: "¥ %.2f", floorPrice)
    }

    var lastTradePriceFormatted: String {
        String(format: "¥ %.2f", lastTradePrice)
    }

    var statusText: String {
        if isLoading {
            return "获取中..."
        }
        if showingError {
            return "请求失败，请稍后重试"
        }
        return "运行中"
    }

    var statusColor: Color {
        showingError ? .red : .secondary
    }

    @MainActor
    func start() async {
        await requestNotificationPermission()
        await refreshNow()
        startAutoRefresh()
    }

    @MainActor
    func login() async {
        guard !account.isEmpty, !password.isEmpty else {
            showError("请输入账号和密码")
            return
        }
        isLoggingIn = true
        defer { isLoggingIn = false }

        do {
            let loginData = try await APIClient.shared.login(account: account, password: password)
            accessToken = loginData.accessToken
            await refreshNow()
        } catch {
            showError("登录失败：\(error.localizedDescription)")
        }
    }

    @MainActor
    func refreshNow() async {
        isLoading = true
        defer { isLoading = false }

        do {
            let project = try await APIClient.shared.fetchFloorPrice(tabId: tabId, projectId: projectId, token: accessToken)
            guard let project else {
                showError("未找到指定藏品")
                return
            }
            updatePrice(project: project)
            showingError = false
        } catch {
            showError("获取失败：\(error.localizedDescription)")
        }
    }

    private func startAutoRefresh() {
        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            while let self, !Task.isCancelled {
                try? await Task.sleep(for: .seconds(180))
                await self.refreshNow()
            }
        }
    }

    private func updatePrice(project: FloorPriceProject) {
        let previous = floorPrice
        floorPrice = project.floorPriceValue
        lastTradePrice = project.lastTradeValue
        projectName = project.name
        lastUpdated = Date()

        priceHistory.append(floorPrice)
        if priceHistory.count > 24 {
            priceHistory.removeFirst()
        }

        if floorPrice > previous {
            trend = .up
        } else if floorPrice < previous {
            trend = .down
        } else {
            trend = .flat
        }

        handleLowPriceAlert()
    }

    private func handleLowPriceAlert() {
        guard notificationsEnabled else { return }
        guard let minimumValue = Double(minimumPrice), floorPrice > 0 else { return }

        if floorPrice <= minimumValue {
            let content = UNMutableNotificationContent()
            content.title = "地板价过低"
            content.body = "当前价格 \(floorPriceFormatted)，低于设定阈值。"
            content.sound = .default

            let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
            UNUserNotificationCenter.current().add(request)

            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.warning)
        }
    }

    @MainActor
    private func requestNotificationPermission() async {
        do {
            let granted = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
            if !granted {
                notificationsEnabled = false
            }
        } catch {
            showError("通知权限请求失败")
        }
    }

    private func showError(_ message: String) {
        errorMessage = message
        showingError = true
    }
}

enum PriceTrend {
    case up
    case down
    case flat

    var color: Color {
        switch self {
        case .up:
            return .green
        case .down:
            return .red
        case .flat:
            return .orange
        }
    }

    var symbol: String {
        switch self {
        case .up:
            return "arrow.up"
        case .down:
            return "arrow.down"
        case .flat:
            return "minus"
        }
    }
}

struct PriceBadge: View {
    let price: Double
    let trend: PriceTrend
    @State private var pulse = false

    var body: some View {
        ZStack {
            Circle()
                .fill(LinearGradient(colors: [trend.color.opacity(0.9), trend.color.opacity(0.4)], startPoint: .topLeading, endPoint: .bottomTrailing))
                .overlay {
                    Circle()
                        .stroke(trend.color.opacity(0.6), lineWidth: 2)
                }
                .frame(width: 88, height: 88)
                .scaleEffect(pulse ? 1.03 : 0.97)
                .animation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true), value: pulse)

            VStack(spacing: 4) {
                Image(systemName: trend.symbol)
                Text(String(format: "%.2f", price))
                    .font(.footnote.weight(.semibold))
            }
            .foregroundStyle(.white)
        }
        .onAppear { pulse = true }
    }
}

struct SparklineCard: View {
    let prices: [Double]
    let lastUpdated: Date?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("价格走势")
                .font(.headline)

            GeometryReader { proxy in
                let size = proxy.size
                let normalized = normalize(prices: prices)
                Path { path in
                    guard normalized.count > 1 else { return }
                    let step = size.width / CGFloat(normalized.count - 1)
                    path.move(to: CGPoint(x: 0, y: size.height * (1 - normalized[0])))
                    for index in normalized.indices {
                        let x = CGFloat(index) * step
                        let y = size.height * (1 - normalized[index])
                        path.addLine(to: CGPoint(x: x, y: y))
                    }
                }
                .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
                .shadow(color: Color.accentColor.opacity(0.2), radius: 4, x: 0, y: 2)
            }
            .frame(height: 120)

            if let lastUpdated {
                Text("更新时间 \(lastUpdated.formatted(date: .omitted, time: .shortened))")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 20).fill(Color(uiColor: .secondarySystemGroupedBackground)))
    }

    private func normalize(prices: [Double]) -> [CGFloat] {
        guard let min = prices.min(), let max = prices.max(), max > min else {
            return prices.map { _ in 0.5 }
        }
        return prices.map { CGFloat(($0 - min) / (max - min)) }
    }
}

#Preview {
    ContentView()
}
