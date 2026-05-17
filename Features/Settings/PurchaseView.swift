import SwiftUI
import StoreKit

// MARK: - Product IDs
private enum ProductID: String, CaseIterable {
    case proMonthly      = "com.studiomemo.pro.monthly"
    case proAnnual       = "com.studiomemo.pro.annual"
    case stemLabUnlock   = "com.studiomemo.stemlabunlock"
    case transcriptPack  = "com.studiomemo.transcriptpack.50"
}

// MARK: - PurchaseStore
@MainActor
final class PurchaseStore: ObservableObject {
    @Published private(set) var products: [Product] = []
    @Published private(set) var purchasedIDs: Set<String> = []
    @Published private(set) var isLoading: Bool = false
    @Published private(set) var error: String?

    var isPro: Bool {
        purchasedIDs.contains(ProductID.proMonthly.rawValue) ||
        purchasedIDs.contains(ProductID.proAnnual.rawValue)
    }

    var isStemLabUnlocked: Bool {
        isPro || purchasedIDs.contains(ProductID.stemLabUnlock.rawValue)
    }

    // MARK: - Load
    func loadProducts() async {
        isLoading = true
        error = nil
        do {
            products = try await Product.products(for: ProductID.allCases.map(\.rawValue))
            products.sort { $0.price < $1.price }
            await refreshPurchasedProducts()
        } catch {
            self.error = error.localizedDescription
            AppLogger.error("PurchaseStore: product load failed: \(error)")
        }
        isLoading = false
    }

    // MARK: - Purchase
    func purchase(_ product: Product) async -> Bool {
        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                guard case .verified(let transaction) = verification else { return false }
                await transaction.finish()
                purchasedIDs.insert(product.id)
                AppLogger.info("PurchaseStore: purchased \(product.id)")
                return true
            case .pending:
                AppLogger.info("PurchaseStore: purchase pending \(product.id)")
                return false
            case .userCancelled:
                return false
            @unknown default:
                return false
            }
        } catch {
            self.error = error.localizedDescription
            AppLogger.error("PurchaseStore: purchase error: \(error)")
            return false
        }
    }

    // MARK: - Restore
    func restore() async {
        isLoading = true
        do {
            try await AppStore.sync()
            await refreshPurchasedProducts()
        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
    }

    // MARK: - Refresh entitlements
    private func refreshPurchasedProducts() async {
        for await result in Transaction.currentEntitlements {
            if case .verified(let transaction) = result {
                purchasedIDs.insert(transaction.productID)
            }
        }
    }
}

// MARK: - PurchaseView
struct PurchaseView: View {
    @StateObject private var store = PurchaseStore()
    @State private var purchasingID: String?
    @State private var showSuccess: Bool = false
    @State private var successMessage: String = ""

    var body: some View {
        ScrollView {
            VStack(spacing: AppTheme.Spacing.lg) {
                heroHeader
                if store.isLoading {
                    ProgressView().tint(AppTheme.Colors.accent).padding()
                } else if store.products.isEmpty {
                    unavailableState
                } else {
                    productList
                    featureComparison
                    restoreButton
                }
                if let err = store.error {
                    Text(err)
                        .font(AppTheme.Fonts.caption)
                        .foregroundColor(.red)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, AppTheme.Spacing.md)
                }
            }
            .padding(AppTheme.Spacing.md)
        }
        .background(AppTheme.Colors.background.ignoresSafeArea())
        .navigationTitle("Pro")
        .navigationBarTitleDisplayMode(.inline)
        .task { await store.loadProducts() }
        .alert("Purchase Complete", isPresented: $showSuccess) {
            Button("Continue") {}
        } message: {
            Text(successMessage)
        }
    }

    // MARK: - Hero
    private var heroHeader: some View {
        VStack(spacing: AppTheme.Spacing.sm) {
            Image(systemName: "bolt.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(
                    LinearGradient(colors: [AppTheme.Colors.accent, .yellow],
                                   startPoint: .topLeading, endPoint: .bottomTrailing)
                )
            Text("StudioMemo Pro")
                .font(AppTheme.Fonts.display)
                .foregroundColor(AppTheme.Colors.primary)
            Text("Unlock unlimited recording, AI stem separation, and professional export tools.")
                .font(AppTheme.Fonts.body)
                .foregroundColor(AppTheme.Colors.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.top, AppTheme.Spacing.lg)
    }

    // MARK: - Product list
    private var productList: some View {
        VStack(spacing: AppTheme.Spacing.sm) {
            ForEach(store.products, id: \.id) { product in
                ProductCard(
                    product: product,
                    isPurchased: store.purchasedIDs.contains(product.id),
                    isPurchasing: purchasingID == product.id
                ) {
                    Task { await buy(product) }
                }
            }
        }
    }

    // MARK: - Feature comparison
    private var featureComparison: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
            Text("What's included")
                .font(AppTheme.Fonts.headline)
                .foregroundColor(AppTheme.Colors.primary)

            let features: [(String, Bool, Bool)] = [
                ("Unlimited recording sessions", true, true),
                ("Waveform timeline + markers", true, true),
                ("Apple Speech transcription", true, true),
                ("Stem separation (2-stem)", false, true),
                ("Stem separation (4/5-stem)", false, true),
                ("WAV 24-bit export", false, true),
                ("Priority processing", false, true),
                ("iCloud backup", false, true),
            ]

            VStack(spacing: 0) {
                // Header
                HStack {
                    Spacer()
                    Text("Free").font(AppTheme.Fonts.caption).foregroundColor(AppTheme.Colors.secondary).frame(width: 48)
                    Text("Pro").font(AppTheme.Fonts.caption).foregroundColor(AppTheme.Colors.accent).frame(width: 48)
                }
                .padding(.horizontal, AppTheme.Spacing.sm)
                .padding(.bottom, 4)

                ForEach(features, id: \.0) { name, free, pro in
                    HStack {
                        Text(name)
                            .font(AppTheme.Fonts.body)
                            .foregroundColor(AppTheme.Colors.primary)
                        Spacer()
                        Image(systemName: free ? "checkmark" : "xmark")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(free ? .green : AppTheme.Colors.secondary)
                            .frame(width: 48)
                        Image(systemName: pro ? "checkmark" : "xmark")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(pro ? .green : AppTheme.Colors.secondary)
                            .frame(width: 48)
                    }
                    .padding(.vertical, 8)
                    .padding(.horizontal, AppTheme.Spacing.sm)
                    if name != features.last?.0 {
                        Divider().background(AppTheme.Colors.background)
                    }
                }
            }
            .cardStyle()
        }
    }

    // MARK: - Restore
    private var restoreButton: some View {
        Button("Restore Purchases") {
            Task { await store.restore() }
        }
        .font(AppTheme.Fonts.caption)
        .foregroundColor(AppTheme.Colors.secondary)
    }

    // MARK: - Unavailable
    private var unavailableState: some View {
        VStack(spacing: 12) {
            Image(systemName: "wifi.slash").font(.largeTitle).foregroundColor(AppTheme.Colors.secondary)
            Text("Products unavailable")
                .font(AppTheme.Fonts.headline)
                .foregroundColor(AppTheme.Colors.primary)
            Text("Check your connection and try again.")
                .font(AppTheme.Fonts.caption)
                .foregroundColor(AppTheme.Colors.secondary)
            Button("Retry") { Task { await store.loadProducts() } }
                .foregroundColor(AppTheme.Colors.accent)
        }
        .padding(AppTheme.Spacing.xl)
    }

    // MARK: - Buy
    private func buy(_ product: Product) async {
        purchasingID = product.id
        let success = await store.purchase(product)
        purchasingID = nil
        if success {
            successMessage = "You now have access to \(product.displayName)."
            showSuccess = true
        }
    }
}

// MARK: - ProductCard
private struct ProductCard: View {
    let product: Product
    let isPurchased: Bool
    let isPurchasing: Bool
    let onBuy: () -> Void

    private var isSubscription: Bool {
        product.type == .autoRenewable
    }

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(product.displayName)
                        .font(AppTheme.Fonts.headline)
                        .foregroundColor(AppTheme.Colors.primary)
                    if isSubscription {
                        Text("SUBSCRIPTION")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(AppTheme.Colors.accent)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(AppTheme.Colors.accent.opacity(0.15))
                            .cornerRadius(4)
                    }
                }
                Text(product.description)
                    .font(AppTheme.Fonts.caption)
                    .foregroundColor(AppTheme.Colors.secondary)
                    .lineLimit(2)
            }
            Spacer()
            if isPurchased {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
                    .font(.title2)
            } else if isPurchasing {
                ProgressView().tint(AppTheme.Colors.accent)
            } else {
                Button(action: onBuy) {
                    Text(product.displayPrice)
                        .font(AppTheme.Fonts.headline)
                        .foregroundColor(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(AppTheme.Colors.accent)
                        .cornerRadius(AppTheme.Radius.pill)
                }
                .buttonStyle(.plain)
            }
        }
        .cardStyle()
        .overlay(
            isPurchased
            ? RoundedRectangle(cornerRadius: AppTheme.Radius.md).stroke(Color.green.opacity(0.5), lineWidth: 1.5)
            : nil
        )
    }
}
