import StoreKit

/// StoreKit 2 商店：v1 只做一个非消耗型「解锁无限」终身购买——最简单的付费模型。
/// FLAG: 订阅 vs 买断、以及定价，都是 Trent 待定；这里先用占位符 product id，真实商品需在
/// App Store Connect 创建后替换。模拟器测试用 `Configuration.storekit`（见仓库根目录）。
@MainActor
final class StoreManager: ObservableObject {
    static let shared = StoreManager()

    /// FLAG: Trent 待定——占位符 product id，App Store Connect 里创建真实商品后替换成正式 id。
    static let unlockProductID = "com.trentct.riddle.unlimited"

    @Published private(set) var products: [Product] = []
    @Published private(set) var isUnlocked: Bool = false
    @Published private(set) var isLoading = false
    @Published var lastError: String?

    private let usageStore: UsageStore
    private var updatesTask: Task<Void, Never>?

    /// `usageStore` 默认 nil、方法体内落到 `.shared`——与 TurnEngine/Oracle 同一套理由（见那两处注释），
    /// 默认参数表达式在非隔离上下文求值，不能直接引用 @MainActor 静态属性。
    init(usageStore: UsageStore? = nil) {
        self.usageStore = usageStore ?? .shared
        updatesTask = Task { [weak self] in
            guard let self else { return }
            for await update in Transaction.updates {
                if case .verified(let transaction) = update {
                    await transaction.finish()
                }
                await self.refreshEntitlements()
            }
        }
        Task { [weak self] in
            await self?.loadProducts()
            await self?.refreshEntitlements()
        }
    }

    deinit {
        updatesTask?.cancel()
    }

    func loadProducts() async {
        isLoading = true
        defer { isLoading = false }
        do {
            products = try await Product.products(for: [Self.unlockProductID])
        } catch {
            lastError = "商品加载失败：\(error.localizedDescription)"
        }
    }

    func purchase() async {
        guard let product = products.first else {
            // 商品还没加载好（比如网络还没回来），先尝试补一次。
            await loadProducts()
            guard let product = products.first else { return }
            await purchase(product)
            return
        }
        await purchase(product)
    }

    private func purchase(_ product: Product) async {
        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                if case .verified(let transaction) = verification {
                    await transaction.finish()
                }
                await refreshEntitlements()
            case .userCancelled, .pending:
                break
            @unknown default:
                break
            }
        } catch {
            lastError = "购买失败：\(error.localizedDescription)"
        }
    }

    func restore() async {
        do {
            try await AppStore.sync()
            await refreshEntitlements()
        } catch {
            lastError = "恢复失败：\(error.localizedDescription)"
        }
    }

    /// 用当前有效交易重新计算解锁状态，并把结果写进 UsageStore（付费即绕过每日额度门控）。
    /// internal（非 private）以便测试直接驱动，不必真的走一遍购买流程。
    func refreshEntitlements() async {
        var unlocked = false
        for await entitlement in Transaction.currentEntitlements {
            if case .verified(let transaction) = entitlement, transaction.productID == Self.unlockProductID {
                unlocked = true
            }
        }
        isUnlocked = unlocked
        usageStore.isPaidUnlocked = unlocked
    }
}
