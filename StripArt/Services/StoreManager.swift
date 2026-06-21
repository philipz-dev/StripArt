import StoreKit

/// Owns the single non-consumable unlock and exposes whether the user has it.
/// StoreKit 2 is the source of truth for `isUnlocked`; the free-export counter
/// lives separately in the view model.
@MainActor
final class StoreManager: ObservableObject {
    static let unlockProductID = "com.philip.stripart.unlock"

    @Published private(set) var unlockProduct: Product?
    @Published private(set) var isUnlocked = false
    @Published private(set) var isLoadingProducts = false
    @Published private(set) var purchaseInProgress = false
    @Published var purchaseError: String?

    private var updatesTask: Task<Void, Never>?

    init() {
        updatesTask = listenForTransactions()
        Task {
            await loadProducts()
            await refreshEntitlements()
        }
    }

    deinit {
        updatesTask?.cancel()
    }

    /// Price string from the store, falling back to a sensible default for the UI.
    var displayPrice: String {
        unlockProduct?.displayPrice ?? "€1,99"
    }

    func loadProducts() async {
        isLoadingProducts = true
        defer { isLoadingProducts = false }

        do {
            let products = try await Product.products(for: [Self.unlockProductID])
            unlockProduct = products.first
        } catch {
            purchaseError = "Could not load the store. Please try again."
        }
    }

    /// Re-checks the App Store for an active entitlement to the unlock.
    func refreshEntitlements() async {
        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result else { continue }
            if transaction.productID == Self.unlockProductID,
               transaction.revocationDate == nil {
                isUnlocked = true
                return
            }
        }
        isUnlocked = false
    }

    func purchase() async {
        if unlockProduct == nil {
            await loadProducts()
        }
        guard let product = unlockProduct else {
            purchaseError = "The unlock is not available right now."
            return
        }

        purchaseInProgress = true
        defer { purchaseInProgress = false }

        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                if case .verified(let transaction) = verification {
                    isUnlocked = true
                    await transaction.finish()
                }
            case .userCancelled, .pending:
                break
            @unknown default:
                break
            }
        } catch {
            purchaseError = "Purchase failed. Please try again."
        }
    }

    /// Restores a previous purchase (required by App Review).
    func restore() async {
        purchaseInProgress = true
        defer { purchaseInProgress = false }

        do {
            try await AppStore.sync()
            await refreshEntitlements()
            if !isUnlocked {
                purchaseError = "No previous purchase found."
            }
        } catch {
            purchaseError = "Could not restore purchases."
        }
    }

    private func listenForTransactions() -> Task<Void, Never> {
        Task(priority: .background) { [weak self] in
            for await result in Transaction.updates {
                guard case .verified(let transaction) = result else { continue }
                await MainActor.run {
                    if transaction.productID == Self.unlockProductID,
                       transaction.revocationDate == nil {
                        self?.isUnlocked = true
                    }
                }
                await transaction.finish()
            }
        }
    }
}
