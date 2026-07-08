import SwiftUI
import StoreKit

/// 水墨风付费页——今日免费额度用尽（或后端返回 402）时弹出。纸色底、墨色手写字，贴合日记本的
/// 气质，不做通用科技感 modal。功能性购买流程走 StoreManager；恢复购买/直接合上本子都在这。
struct PaywallView: View {
    let onDismiss: () -> Void
    @ObservedObject var store: StoreManager

    var body: some View {
        ZStack {
            Color(Ink.paperColor).ignoresSafeArea()
            Image(uiImage: PaperTexture.tile)
                .resizable(resizingMode: .tile)
                .opacity(0.05)
                .ignoresSafeArea()
                .allowsHitTesting(false)
            RadialGradient(colors: [.clear, .black.opacity(0.12)],
                           center: .center, startRadius: 200, endRadius: 900)
                .ignoresSafeArea()
                .allowsHitTesting(false)

            VStack(spacing: 22) {
                Spacer()

                VStack(spacing: 6) {
                    Text("今日的墨已用尽。")
                    Text("解锁无尽的纸与笔。")
                }
                .font(.custom(ReplyHands.shouze.fontName, size: 32))

                if let product = store.products.first {
                    Text(product.displayPrice)
                        .font(.custom(ReplyHands.shouze.fontName, size: 22))
                        .opacity(0.65)
                } else if store.isLoading {
                    ProgressView().tint(Color(Ink.quillColor))
                }

                if let error = store.lastError {
                    Text(error)
                        .font(.custom(ReplyHands.shouze.fontName, size: 15))
                        .foregroundStyle(.red.opacity(0.7))
                }

                unlockButton
                restoreButton

                Spacer()

                Button(action: onDismiss) {
                    Text("先合上本子")
                        .font(.custom(ReplyHands.shouze.fontName, size: 16))
                        .opacity(0.55)
                }
                .padding(.bottom, 28)
            }
            .foregroundStyle(Color(Ink.quillColor))
            .multilineTextAlignment(.center)
            .padding(.horizontal, 48)
        }
        .onChange(of: store.isUnlocked) { _, unlocked in
            if unlocked { onDismiss() }
        }
    }

    private var unlockButton: some View {
        Button {
            Task { await store.purchase() }
        } label: {
            Text("解锁无限")
                .font(.custom(ReplyHands.shouze.fontName, size: 22))
                .padding(.horizontal, 36)
                .padding(.vertical, 14)
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(Color(Ink.quillColor), lineWidth: 1.5)
                )
        }
        .disabled(store.isLoading)
    }

    private var restoreButton: some View {
        Button {
            Task { await store.restore() }
        } label: {
            Text("恢复购买")
                .font(.custom(ReplyHands.shouze.fontName, size: 16))
                .underline()
                .opacity(0.7)
        }
    }
}
