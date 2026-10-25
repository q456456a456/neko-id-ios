import SwiftUI

struct AccountDeletionView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appModel: NekoAppModel
    @State private var confirmsDeletion = false
    @State private var deletionError: String?

    private var accountName: String {
        let name = appModel.catProfile?.name.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return name.isEmpty ? "猫咪主人" : name
    }

    var body: some View {
        AccountDeletionPage(
            accountName: accountName,
            loginIdentifier: appModel.session?.user.loginIdentifier ?? "已登录账号",
            avatarURL: appModel.catProfile?.avatarURL,
            avatarObjectKey: appModel.catProfile?.avatarObjectKey,
            isDeletingAccount: appModel.isDeletingAccount,
            isActionDisabled: appModel.isBusy || appModel.session == nil,
            deletionError: deletionError,
            onBack: { dismiss() },
            onDelete: { confirmsDeletion = true }
        )
        .toolbar(.hidden, for: .navigationBar)
        .navigationBarBackButtonHidden(true)
        .nekoEdgeSwipeBack(isEnabled: !appModel.isDeletingAccount && !confirmsDeletion) {
            dismiss()
        }
        .interactiveDismissDisabled(appModel.isDeletingAccount)
        .alert("确定永久注销当前账号？", isPresented: $confirmsDeletion) {
            Button("取消", role: .cancel) {}
            Button("永久注销", role: .destructive) {
                deletionError = nil
                Task {
                    do {
                        try await appModel.deleteAccount()
                        // Root navigation resets when the account is cleared.
                    } catch {
                        deletionError = NekoUserFacingError.message(for: error)
                    }
                }
            }
        } message: {
            Text("账号、猫咪档案、人格结果、心声和云端媒体将永久删除，无法恢复。")
        }
    }
}

// Keep the presentation separate from the destructive action so previews and
// layout checks never need a live account or invoke the deletion API.
struct AccountDeletionPage: View {
    let accountName: String
    let loginIdentifier: String
    var avatarURL: URL? = nil
    var avatarObjectKey: String? = nil
    var isDeletingAccount = false
    var isActionDisabled = false
    var deletionError: String? = nil
    let onBack: () -> Void
    let onDelete: () -> Void

    private let warningColor = Color(red: 0.64, green: 0.28, blue: 0.36)

    var body: some View {
        ZStack {
            NekoBackground()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    AccountTopBar(title: "注销账号", back: onBack)
                        .disabled(isDeletingAccount)
                        .padding(.top, 52)

                    accountCard
                        .padding(.top, 20)

                    deletionScopeCard
                        .padding(.top, 16)

                    reminderCard
                        .padding(.top, 16)

                    if let deletionError {
                        Label {
                            Text(deletionError)
                                .fixedSize(horizontal: false, vertical: true)
                        } icon: {
                            Image(systemName: "exclamationmark.circle.fill")
                        }
                        .nekoText(.caption)
                        .foregroundStyle(warningColor)
                        .padding(16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(NekoTheme.softPink.opacity(0.50), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .padding(.top, 16)
                        .accessibilityIdentifier("accountDeletionError")
                    }

                    deleteButton
                        .padding(.top, 24)

                    Text(isDeletingAccount ? "正在清理账号数据，请勿关闭 App" : "点击后还需再次确认，不会立即注销")
                        .nekoText(.tiny)
                        .foregroundStyle(NekoTheme.muted)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 12)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 40)
                .frame(maxWidth: 600)
                .frame(maxWidth: .infinity)
            }
        }
    }

    private var accountCard: some View {
        NekoGlassCard(cornerRadius: 26, tint: true) {
            HStack(spacing: 16) {
                CatAvatarView(localImage: nil, remoteURL: avatarURL, objectKey: avatarObjectKey, size: 68)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 5) {
                    Text("当前登录账号")
                        .nekoText(.tiny)
                        .foregroundStyle(NekoTheme.muted)
                    Text(accountName)
                        .nekoText(.button)
                        .foregroundStyle(NekoTheme.ink)
                    Text(loginIdentifier)
                        .nekoText(.caption)
                        .foregroundStyle(NekoTheme.inkSoft)
                }
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(20)
        }
    }

    private var deletionScopeCard: some View {
        AccountSectionCard {
            VStack(alignment: .leading, spacing: 18) {
                Text("注销后，将永久删除")
                    .nekoText(.badge)
                    .foregroundStyle(NekoTheme.ink)
                    .accessibilityAddTraits(.isHeader)

                scopeRow(icon: "person.crop.circle", title: "账号与个人资料", detail: "登录账号及个人资料")
                scopeRow(icon: "pawprint", title: "猫咪档案与心声", detail: "问卷、人格分析及历史记录")
                scopeRow(icon: "photo.on.rectangle", title: "云端照片与本机数据", detail: "云端照片、登录状态及图片缓存")
            }
        }
    }

    private func scopeRow(icon: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .nekoText(.iconMedium)
                .foregroundStyle(NekoTheme.menuIcon)
                .frame(width: 40, height: 40)
                .background(NekoTheme.menuIconGradient.opacity(0.65), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .nekoText(.support)
                    .foregroundStyle(NekoTheme.ink)
                Text(detail)
                    .nekoText(.caption)
                    .foregroundStyle(NekoTheme.muted)
            }
            .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }

    private var reminderCard: some View {
        AccountSectionCard {
            VStack(alignment: .leading, spacing: 10) {
                Label("注销不是退出登录，且无法恢复", systemImage: "exclamationmark.circle")
                    .nekoText(.caption)
                    .foregroundStyle(warningColor)
                    .accessibilityAddTraits(.isHeader)

                Text("之后使用同一手机号登录，将创建新账号，旧数据不会恢复。")
                    .nekoText(.caption)
                    .foregroundStyle(NekoTheme.inkSoft)

                Text("已保存到手机相册的图片不会被删除。")
                    .nekoText(.caption)
                    .foregroundStyle(NekoTheme.inkSoft)
            }
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var deleteButton: some View {
        Button(role: .destructive, action: onDelete) {
            HStack(spacing: 10) {
                if isDeletingAccount {
                    ProgressView().tint(warningColor)
                }
                Text(isDeletingAccount ? "正在注销…" : "注销账号")
                    .nekoText(.button)
            }
            .foregroundStyle(warningColor)
            .frame(maxWidth: .infinity, minHeight: 52)
            .padding(.horizontal, 16)
            .background(Color.white.opacity(0.78), in: Capsule())
            .overlay {
                Capsule()
                    .stroke(warningColor.opacity(0.32), lineWidth: 1)
            }
            .shadow(color: NekoTheme.soulPink.opacity(0.16), radius: 18, x: 0, y: 8)
            .opacity(isActionDisabled && !isDeletingAccount ? 0.5 : 1)
        }
        .buttonStyle(.plain)
        .disabled(isActionDisabled || isDeletingAccount)
        .accessibilityIdentifier("deleteAccountButton")
    }
}

#Preview {
    AccountDeletionPage(
        accountName: "丸子", loginIdentifier: "+86 138 0000 0000",
        onBack: {}, onDelete: {}
    )
    .environmentObject(NekoAppModel())
}
