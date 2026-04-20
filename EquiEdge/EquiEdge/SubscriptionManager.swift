import Foundation
import StoreKit

enum SubscriptionTier: String, Codable {
    case trial
    case basic
    case pro
    case expired
}

enum SubscriptionError: LocalizedError {
    case trialExpired
    case weeklyLimitReached(used: Int, limit: Int)
    case notSignedIn

    var errorDescription: String? {
        switch self {
        case .trialExpired:
            return "Your free trial has ended. Subscribe to continue using Edge AI analysis."
        case .weeklyLimitReached(let used, let limit):
            return "You've used \(used)/\(limit) track analyses this week."
        case .notSignedIn:
            return "Please sign in to use Edge AI analysis."
        }
    }
}

@MainActor
@Observable
final class SubscriptionManager {
    static let shared = SubscriptionManager()

    // Product IDs matching App Store Connect
    static let basicMonthly = "equiedge.basic.monthly"
    static let basicAnnual = "equiedge.basic.annual"
    static let proMonthly = "equiedge.pro.monthly"
    static let proAnnual = "equiedge.pro.annual"
    static let allProductIDs: Set<String> = [basicMonthly, basicAnnual, proMonthly, proAnnual]

    private(set) var currentTier: SubscriptionTier = .expired
    private(set) var trackDaysUsedThisWeek: Int = 0
    private(set) var trackDayLimit: Int? = nil
    private(set) var trialDaysRemaining: Int = 0
    private(set) var trialUsesRemaining: Int = 0
    private(set) var weeklyTracks: [String] = []
    private(set) var products: [Product] = []
    private(set) var isLoading = false
    private(set) var errorMessage: String?

    var isAnnual = false

    private let vercelBaseURL = "https://equiedge-scraper.vercel.app"
    private var updateListenerTask: Task<Void, Never>?

    private init() {
        updateListenerTask = listenForTransactionUpdates()
        Task { await loadProducts() }
    }

    deinit {
        updateListenerTask?.cancel()
    }

    // MARK: - Tier Checks

    var canAnalyse: Bool {
        switch currentTier {
        case .pro: return true
        case .basic: return true // limit checked per-request
        case .trial: return trialUsesRemaining > 0 && trialDaysRemaining > 0
        case .expired: return false
        }
    }

    func canAnalyseTrack(_ slug: String, on date: Date) -> Bool {
        let dateStr = Self.dateFormatter.string(from: date)
        let compositeKey = "\(slug.lowercased())_\(dateStr)"

        switch currentTier {
        case .pro: return true
        case .basic:
            // Already used today = free re-run
            if weeklyTracks.contains(compositeKey) { return true }
            return trackDaysUsedThisWeek < (trackDayLimit ?? 10)
        case .trial:
            return trialUsesRemaining > 0 && trialDaysRemaining > 0
        case .expired:
            return false
        }
    }

    func remainingAnalyses(for trackSlugs: [String], on date: Date) -> Int {
        let dateStr = Self.dateFormatter.string(from: date)

        switch currentTier {
        case .pro: return trackSlugs.count
        case .basic:
            let limit = trackDayLimit ?? 10
            let newTracks = trackSlugs.filter { slug in
                !weeklyTracks.contains("\(slug.lowercased())_\(dateStr)")
            }
            let available = max(0, limit - trackDaysUsedThisWeek)
            return min(newTracks.count, available) + (trackSlugs.count - newTracks.count)
        case .trial:
            return min(trialUsesRemaining, trackSlugs.count)
        case .expired:
            return 0
        }
    }

    // MARK: - Backend Sync

    func refreshStatus() async {
        guard let userId = AuthManager.shared.userId else { return }

        guard let url = URL(string: "\(vercelBaseURL)/api/user/status") else { return }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(userId)", forHTTPHeaderField: "Authorization")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return }

            let status = try JSONDecoder().decode(UserStatus.self, from: data)
            applyStatus(status)
        } catch {
            // Silently fail — use cached state
        }
    }

    func recordUsage(trackSlug: String, date: Date) async throws {
        guard let userId = AuthManager.shared.userId else {
            throw SubscriptionError.notSignedIn
        }

        let dateStr = Self.dateFormatter.string(from: date)

        guard let url = URL(string: "\(vercelBaseURL)/api/user/record-usage") else {
            throw URLError(.badURL)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(userId)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: String] = ["trackSlug": trackSlug, "date": dateStr]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        let http = response as? HTTPURLResponse

        if http?.statusCode == 403 {
            // Usage limit reached
            let errorBody = try? JSONDecoder().decode(UsageError.self, from: data)
            if errorBody?.tier == "expired" || errorBody?.error.contains("Trial") == true {
                currentTier = .expired
                throw SubscriptionError.trialExpired
            }
            throw SubscriptionError.weeklyLimitReached(
                used: errorBody?.trackDaysUsedThisWeek ?? trackDaysUsedThisWeek,
                limit: errorBody?.trackDayLimit ?? trackDayLimit ?? 10
            )
        }

        guard http?.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }

        let status = try JSONDecoder().decode(UserStatus.self, from: data)
        applyStatus(status)
    }

    // MARK: - StoreKit 2

    func loadProducts() async {
        do {
            products = try await Product.products(for: Self.allProductIDs)
                .sorted { $0.price < $1.price }
        } catch {
            errorMessage = "Failed to load products: \(error.localizedDescription)"
        }
    }

    func purchase(_ product: Product) async throws {
        isLoading = true
        defer { isLoading = false }

        let result = try await product.purchase()

        switch result {
        case .success(let verification):
            let transaction = try checkVerified(verification)
            await transaction.finish()
            // Backend is notified via App Store Server Notifications
            // Refresh status to pick up the new tier
            await refreshStatus()

        case .userCancelled:
            break

        case .pending:
            // Transaction requires approval (e.g. Ask to Buy)
            break

        @unknown default:
            break
        }
    }

    func restorePurchases() async {
        isLoading = true
        defer { isLoading = false }

        try? await AppStore.sync()
        await refreshStatus()
    }

    // MARK: - Products by Tier

    var basicProducts: [Product] {
        products.filter { $0.id.contains("basic") }
    }

    var proProducts: [Product] {
        products.filter { $0.id.contains("pro") }
    }

    func monthlyProduct(for tier: String) -> Product? {
        products.first { $0.id == "equiedge.\(tier).monthly" }
    }

    func annualProduct(for tier: String) -> Product? {
        products.first { $0.id == "equiedge.\(tier).annual" }
    }

    // MARK: - Private

    private func listenForTransactionUpdates() -> Task<Void, Never> {
        Task.detached {
            for await result in Transaction.updates {
                if let transaction = try? result.payloadValue {
                    await transaction.finish()
                    await MainActor.run {
                        Task { await SubscriptionManager.shared.refreshStatus() }
                    }
                }
            }
        }
    }

    private func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .unverified(_, let error):
            throw error
        case .verified(let safe):
            return safe
        }
    }

    private func applyStatus(_ status: UserStatus) {
        currentTier = SubscriptionTier(rawValue: status.tier) ?? .expired
        trackDaysUsedThisWeek = status.trackDaysUsedThisWeek ?? 0
        trackDayLimit = status.trackDayLimit
        trialDaysRemaining = status.trialDaysRemaining ?? 0
        trialUsesRemaining = status.trialUsesRemaining ?? 0
        weeklyTracks = status.weeklyTracks ?? []
    }

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    // MARK: - Response Models

    private struct UserStatus: Codable {
        let tier: String
        let trackDaysUsedThisWeek: Int?
        let trackDayLimit: Int?
        let trialDaysRemaining: Int?
        let trialUsesRemaining: Int?
        let weeklyTracks: [String]?
        let trialUsage: [String]?
        let subscriptionExpiresAt: String?
    }

    private struct UsageError: Codable {
        let error: String
        let tier: String?
        let trackDaysUsedThisWeek: Int?
        let trackDayLimit: Int?
    }
}
