//
//  ContentView.swift
//  neko-id
//
//  Created by Amadeus on 2026/8/15.
//

import PhotosUI
import SwiftUI
import UIKit
import Combine

struct ContentView: View {
    @EnvironmentObject private var appModel: NekoAppModel
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        NavigationStack {
            ZStack {
                NekoBackground()

                switch appModel.phase {
                case .launching:
                    LaunchingView()
                case .signedOut:
                    LoginView()
                case .onboarding:
                    NativeOnboardingFlowView()
                case .home:
                    MainTabRootView()
                }
            }
            .navigationBarTitleDisplayMode(.inline)
        }
        .nekoDismissKeyboardOnTap()
        .id(appModel.phase)
        .task {
            await appModel.bootstrap()
        }
        .nekoToastHost(
            errorMessage: $appModel.errorMessage,
            noticeMessage: $appModel.noticeMessage
        )
        .sheet(item: $appModel.loginPrompt) { prompt in
            LoginView(
                title: "继续前先登录",
                subtitle: prompt.message,
                allowDismiss: true,
                reloadCloudStateAfterLogin: false,
                onAuthenticated: {
                    appModel.dismissLoginPrompt()
                },
                onCancel: {
                    appModel.dismissLoginPrompt()
                }
            )
            .presentationDetents([.large])
            .nekoToastHost(
                errorMessage: $appModel.errorMessage,
                noticeMessage: $appModel.noticeMessage
            )
        }
        .onChange(of: scenePhase) { _, nextPhase in
            guard nextPhase == .active else { return }
            Task {
                await appModel.refreshSignedMediaURLs()
            }
        }
    }
}

private struct MainTabRootView: View {
    @State private var activeTab: HomeTabBar.Selection = .home

    var body: some View {
        ZStack {
            HomeView {
                switchTo(.me)
            }
            .opacity(activeTab == .home ? 1 : 0)
            .allowsHitTesting(activeTab == .home)
            .accessibilityHidden(activeTab != .home)

            MeView {
                switchTo(.home)
            }
            .opacity(activeTab == .me ? 1 : 0)
            .allowsHitTesting(activeTab == .me)
            .accessibilityHidden(activeTab != .me)
        }
        .transaction { transaction in
            transaction.animation = nil
            transaction.disablesAnimations = true
        }
    }

    private func switchTo(_ tab: HomeTabBar.Selection) {
        guard activeTab != tab else { return }
        var transaction = Transaction(animation: nil)
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            activeTab = tab
        }
    }
}

private enum NekoToastKind: Equatable {
    case error
    case notice
}

private struct NekoToastPayload: Equatable {
    let kind: NekoToastKind
    let message: String

    var id: String {
        "\(kind)-\(message)"
    }
}

private struct NekoToastHostModifier: ViewModifier {
    @Binding var errorMessage: String?
    @Binding var noticeMessage: String?
    @State private var dismissTask: Task<Void, Never>?

    private var activeToast: NekoToastPayload? {
        if let message = errorMessage?.trimmingCharacters(in: .whitespacesAndNewlines),
           !message.isEmpty {
            return NekoToastPayload(kind: .error, message: message)
        }
        if let message = noticeMessage?.trimmingCharacters(in: .whitespacesAndNewlines),
           !message.isEmpty {
            return NekoToastPayload(kind: .notice, message: message)
        }
        return nil
    }

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .center) {
                if let activeToast {
                    NekoToastView(payload: activeToast)
                        .padding(.horizontal, 30)
                        .transition(.opacity.combined(with: .scale(scale: 0.94)))
                        .onTapGesture {
                            dismiss(activeToast)
                        }
                        .zIndex(200)
                }
            }
            .animation(.spring(response: 0.28, dampingFraction: 0.86), value: activeToast)
            .onChange(of: errorMessage) { _, _ in
                scheduleDismiss()
            }
            .onChange(of: noticeMessage) { _, _ in
                scheduleDismiss()
            }
            .onDisappear {
                dismissTask?.cancel()
            }
    }

    private func scheduleDismiss() {
        dismissTask?.cancel()
        guard let toast = activeToast else { return }
        let seconds: Double = toast.message.count > 28 ? 4.2 : 2.6

        dismissTask = Task {
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                switch toast.kind {
                case .error:
                    if errorMessage == toast.message {
                        errorMessage = nil
                    }
                case .notice:
                    if noticeMessage == toast.message {
                        noticeMessage = nil
                    }
                }
            }
        }
    }

    private func dismiss(_ toast: NekoToastPayload) {
        dismissTask?.cancel()
        switch toast.kind {
        case .error:
            errorMessage = nil
        case .notice:
            noticeMessage = nil
        }
    }
}

private struct NekoToastView: View {
    let payload: NekoToastPayload

    var body: some View {
        HStack(spacing: 10) {
            icon

            Text(payload.message)
                .font(.system(size: NekoTypography.web(12.5), weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(3)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .frame(maxWidth: 330)
        .background(
            RoundedRectangle(cornerRadius: 23, style: .continuous)
                .fill(Color.black.opacity(0.46))
        )
        .overlay {
            RoundedRectangle(cornerRadius: 23, style: .continuous)
                .stroke(Color.white.opacity(0.20), lineWidth: 1)
        }
        .shadow(color: NekoTheme.ink.opacity(0.22), radius: 18, x: 0, y: 10)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var icon: some View {
        switch payload.kind {
        case .error:
            Image(systemName: "exclamationmark.circle.fill")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color(red: 1.0, green: 0.78, blue: 0.72))
        case .notice:
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.92))
        }
    }
}

struct NekoEdgeSwipeBackModifier: ViewModifier {
    let isEnabled: Bool
    let edgeWidth: CGFloat
    let minimumDistance: CGFloat
    let action: () -> Void

    func body(content: Content) -> some View {
        content
            .contentShape(Rectangle())
            .simultaneousGesture(
                DragGesture(minimumDistance: 18, coordinateSpace: .local)
                    .onEnded { value in
                        guard isEnabled else { return }
                        guard value.startLocation.x <= edgeWidth else { return }
                        guard value.translation.width >= minimumDistance else { return }
                        guard abs(value.translation.height) <= value.translation.width * 0.75 else { return }
                        action()
                    }
            )
    }
}

extension View {
    func nekoToastHost(
        errorMessage: Binding<String?>,
        noticeMessage: Binding<String?>
    ) -> some View {
        modifier(
            NekoToastHostModifier(
                errorMessage: errorMessage,
                noticeMessage: noticeMessage
            )
        )
    }

    func nekoEdgeSwipeBack(
        isEnabled: Bool = true,
        edgeWidth: CGFloat = 44,
        minimumDistance: CGFloat = 72,
        action: @escaping () -> Void
    ) -> some View {
        modifier(
            NekoEdgeSwipeBackModifier(
                isEnabled: isEnabled,
                edgeWidth: edgeWidth,
                minimumDistance: minimumDistance,
                action: action
            )
        )
    }
}

private struct LaunchingView: View {
    var body: some View {
        VStack(spacing: 16) {
            ProgressView()
                .tint(NekoTheme.soulViolet)

            Text("正在寻找你的猫咪档案…")
                .font(.system(size: NekoTypography.web(14), weight: .medium))
                .foregroundStyle(NekoTheme.muted)
        }
        .padding(24)
        .background(.white.opacity(0.78), in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(.white.opacity(0.72), lineWidth: 1)
        }
        .shadow(color: NekoTheme.soulViolet.opacity(0.15), radius: 28, x: 0, y: 14)
    }
}

private struct LoginView: View {
    @EnvironmentObject private var appModel: NekoAppModel
    let title: String
    let subtitle: String
    let allowDismiss: Bool
    let reloadCloudStateAfterLogin: Bool
    let onAuthenticated: () -> Void
    let onCancel: () -> Void

    @State private var phone = ""
    @State private var code = ""
    @State private var codeSent = false
    @State private var codeNotice = ""
    @State private var resendCooldown = 0
    @State private var lastSentPhone = ""
    @FocusState private var focusedField: LoginFocusField?

    init(
        title: String = "手机号验证码登录",
        subtitle: String = "输入手机号，我们会通过短信给你发送 6 位验证码。",
        allowDismiss: Bool = false,
        reloadCloudStateAfterLogin: Bool = true,
        onAuthenticated: @escaping () -> Void = {},
        onCancel: @escaping () -> Void = {}
    ) {
        self.title = title
        self.subtitle = subtitle
        self.allowDismiss = allowDismiss
        self.reloadCloudStateAfterLogin = reloadCloudStateAfterLogin
        self.onAuthenticated = onAuthenticated
        self.onCancel = onCancel
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                Spacer(minLength: 72)

                if allowDismiss {
                    HStack {
                        Spacer()
                        Button("暂不登录", action: onCancel)
                            .font(.system(size: NekoTypography.web(12), weight: .medium))
                            .foregroundStyle(NekoTheme.soulViolet)
                            .padding(.horizontal, 14)
                            .frame(height: 34)
                            .background(Color.white.opacity(0.72), in: Capsule())
                    }
                    .padding(.bottom, 18)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("NEKO ACCOUNT")
                        .font(.system(size: NekoTypography.web(10), weight: .semibold))
                        .tracking(4.6)
                        .foregroundStyle(NekoTheme.soulViolet)

                    Text(title)
                        .font(.system(size: 28, weight: .light))
                        .foregroundStyle(NekoTheme.ink)

                    Text(subtitle)
                        .font(.system(size: NekoTypography.web(12.5)))
                        .foregroundStyle(NekoTheme.muted)
                        .lineSpacing(4)
                        .padding(.top, 2)
                }

                NekoGlassCard(cornerRadius: 28) {
                    VStack(alignment: .leading, spacing: 14) {
                        FieldTitle("手机号")
                        HStack(spacing: 12) {
                            Text("+86")
                                .font(.system(size: NekoTypography.web(15), weight: .semibold))
                                .foregroundStyle(NekoTheme.ink)

                            Rectangle()
                                .fill(NekoTheme.softLilac.opacity(0.72))
                                .frame(width: 1, height: 22)

                            TextField("138 0013 8000", text: phoneBinding)
                                .textInputAutocapitalization(.never)
                                .keyboardType(.phonePad)
                                .textContentType(.telephoneNumber)
                                .autocorrectionDisabled()
                                .focused($focusedField, equals: .phone)
                                .font(.system(size: NekoTypography.web(15), weight: .regular))
                                .foregroundStyle(NekoTheme.ink)

                            if !phone.isEmpty {
                                Button {
                                    resetPhoneInput()
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.system(size: 16, weight: .semibold))
                                        .foregroundStyle(NekoTheme.muted.opacity(0.55))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 14)
                            .background(NekoTheme.field, in: RoundedRectangle(cornerRadius: 16, style: .continuous))

                        FieldTitle("验证码")
                            .padding(.top, 4)
                        HStack(spacing: 12) {
                            TextField("输入验证码", text: codeBinding)
                                .keyboardType(.numberPad)
                                .textContentType(.oneTimeCode)
                                .font(.system(size: NekoTypography.web(15), weight: .regular))
                                .foregroundStyle(NekoTheme.ink)
                                .focused($focusedField, equals: .code)
                                .disabled(!codeSent)

                            Button {
                                sendLoginCode()
                            } label: {
                                Text(sendCodeTitle)
                                    .font(.system(size: NekoTypography.web(12.5), weight: .semibold))
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.82)
                                    .foregroundStyle(canSendCode ? NekoTheme.soulViolet : NekoTheme.muted.opacity(0.70))
                                    .frame(minWidth: 96, alignment: .trailing)
                            }
                            .buttonStyle(.plain)
                            .disabled(!canSendCode)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)
                        .background(NekoTheme.field, in: RoundedRectangle(cornerRadius: 16, style: .continuous))

                        if !codeNotice.isEmpty {
                            Text(codeNotice)
                                .font(.system(size: NekoTypography.web(11.5), weight: .medium))
                                .foregroundStyle(NekoTheme.soulViolet)
                                .frame(maxWidth: .infinity, alignment: .center)
                                .transition(.opacity)
                        }

                        Button {
                            completeLogin()
                        } label: {
                            Label("完成登录", systemImage: "checkmark.circle")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(NekoPrimaryButtonStyle())
                        .disabled(!canCompleteLogin)
                        .padding(.top, 2)

                        Text(codeSent ? "如果收不到验证码，稍等一会儿再重新发送。" : "未注册手机号登录成功后会自动创建账号。")
                            .font(.system(size: NekoTypography.web(11)))
                            .foregroundStyle(NekoTheme.muted)
                            .frame(maxWidth: .infinity, alignment: .center)
                    }
                    .padding(16)
                }
                .padding(.top, 30)

                Text("手机号会作为账号唯一标识。登录后，猫咪档案、人格和心声会只绑定到当前用户。")
                    .font(.system(size: NekoTypography.web(11.5)))
                    .foregroundStyle(NekoTheme.muted)
                    .lineSpacing(4)
                    .padding(16)
                    .background(Color.white.opacity(0.58), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                    .padding(.top, 16)

                Spacer(minLength: 80)
            }
            .padding(.horizontal, 28)
            .frame(maxWidth: 480)
            .frame(maxWidth: .infinity)
        }
        .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { _ in
            guard resendCooldown > 0 else { return }
            resendCooldown -= 1
        }
        .overlay(alignment: .center) {
            if appModel.isBusy {
                ProgressView()
                    .tint(NekoTheme.soulViolet)
                    .padding(18)
                    .background(.white.opacity(0.82), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            }
        }
    }

    private var phoneBinding: Binding<String> {
        Binding(
            get: { formatPhone(phone) },
            set: { updatePhoneInput($0) }
        )
    }

    private var codeBinding: Binding<String> {
        Binding(
            get: { code },
            set: { code = String($0.filter(\.isNumber).prefix(6)) }
        )
    }

    private var isPhoneReady: Bool {
        phone.range(of: #"^1\d{10}$"#, options: .regularExpression) != nil
    }

    private var canSendCode: Bool {
        !appModel.isBusy && isPhoneReady && resendCooldown == 0
    }

    private var canCompleteLogin: Bool {
        !appModel.isBusy && isPhoneReady && codeSent && code.count == 6
    }

    private var sendCodeTitle: String {
        if resendCooldown > 0 {
            return "重新发送(\(resendCooldown)s)"
        }
        return codeSent ? "重新发送" : "发送验证码"
    }

    private func updatePhoneInput(_ value: String) {
        var digits = value.filter(\.isNumber)
        if digits.hasPrefix("86"), digits.count > 11 {
            digits = String(digits.dropFirst(2))
        }
        phone = String(digits.prefix(11))

        if phone != lastSentPhone {
            code = ""
            codeSent = false
            codeNotice = ""
            resendCooldown = 0
        }
    }

    private func resetPhoneInput() {
        phone = ""
        code = ""
        codeSent = false
        codeNotice = ""
        resendCooldown = 0
        lastSentPhone = ""
        focusedField = .phone
    }

    private func sendLoginCode() {
        guard canSendCode else { return }

        Task {
            let didSend = await appModel.requestLoginCode(phone: phone)
            if didSend {
                lastSentPhone = phone
                codeSent = true
                code = ""
                codeNotice = "验证码已发送，请查收短信。"
                resendCooldown = 60
                focusedField = .code
            }
        }
    }

    private func completeLogin() {
        guard canCompleteLogin else { return }

        Task {
            let didLogin = await appModel.verifyLoginCode(
                phone: phone,
                code: code,
                reloadCloudStateAfterLogin: reloadCloudStateAfterLogin
            )
            if didLogin {
                onAuthenticated()
            }
        }
    }

    private func formatPhone(_ value: String) -> String {
        let digits = String(value.filter(\.isNumber).prefix(11))
        guard digits.count > 3 else { return digits }

        let first = digits.prefix(3)
        let rest = digits.dropFirst(3)
        if rest.count <= 4 {
            return "\(first) \(rest)"
        }

        let middle = rest.prefix(4)
        let last = rest.dropFirst(4)
        return "\(first) \(middle) \(last)"
    }
}

private enum LoginFocusField: Hashable {
    case phone
    case code
}

private struct NativeOnboardingView: View {
    @EnvironmentObject private var appModel: NekoAppModel
    @State private var draft = CatProfileDraft()
    @State private var selectedAvatarItem: PhotosPickerItem?
    @State private var avatarImageData: Data?
    @State private var avatarPreviewImage: UIImage?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("CREATE PROFILE")
                        .font(.system(size: NekoTypography.web(11), weight: .semibold))
                        .tracking(4)
                        .foregroundStyle(NekoTheme.soulViolet)

                    Text("创建猫咪人格档案")
                        .font(.system(size: 30, weight: .light))
                        .foregroundStyle(NekoTheme.ink)

                    Text("先建立基础档案。照片、视频和 AI 人格生成会继续原生化接入。")
                        .font(.system(size: NekoTypography.web(14)))
                        .foregroundStyle(NekoTheme.muted)
                        .lineSpacing(4)
                }

                VStack(alignment: .leading, spacing: 16) {
                    PhotosPicker(selection: $selectedAvatarItem, matching: .images) {
                        HStack(spacing: 16) {
                            CatAvatarView(localImage: avatarPreviewImage, remoteURL: nil, size: 76)

                            VStack(alignment: .leading, spacing: 6) {
                                Text(avatarPreviewImage == nil ? "选择猫咪照片" : "更换猫咪照片")
                                    .font(.system(size: NekoTypography.web(15), weight: .semibold))
                                    .foregroundStyle(NekoTheme.ink)

                                Text("会作为头像上传到私有云端，单张不超过 10MB。")
                                    .font(.system(size: NekoTypography.web(12)))
                                    .foregroundStyle(NekoTheme.muted)
                                    .multilineTextAlignment(.leading)
                            }

                            Spacer()

                            Image(systemName: "photo.badge.plus")
                                .font(.system(size: 20, weight: .semibold))
                                .foregroundStyle(NekoTheme.soulViolet)
                        }
                        .padding(14)
                        .background(.white.opacity(0.74), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                    }

                    FieldTitle("猫咪名字")
                    TextField("例如：糯米团", text: $draft.name)
                        .textInputAutocapitalization(.never)
                        .padding()
                        .background(.white.opacity(0.74), in: RoundedRectangle(cornerRadius: 18, style: .continuous))

                    FieldTitle("性别")
                    Picker("性别", selection: $draft.gender) {
                        ForEach(CatGender.allCases) { gender in
                            Text(gender.rawValue).tag(gender)
                        }
                    }
                    .pickerStyle(.segmented)

                    FieldTitle("年龄阶段")
                    Picker("年龄阶段", selection: $draft.ageStage) {
                        ForEach(CatAgeStage.allCases) { stage in
                            Text(stage.rawValue).tag(stage)
                        }
                    }
                    .pickerStyle(.segmented)
                }
                .padding(18)
                .background(.white.opacity(0.52), in: RoundedRectangle(cornerRadius: 26, style: .continuous))

                Button {
                    Task { await appModel.createCatProfile(draft, avatarImageData: avatarImageData) }
                } label: {
                    Label("保存档案", systemImage: "pawprint.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(appModel.isBusy || !draft.isValid)

                Button("退出当前账号") {
                    appModel.signOut()
                }
                .font(.system(size: NekoTypography.web(13), weight: .medium))
                .foregroundStyle(NekoTheme.muted)
                .frame(maxWidth: .infinity)
            }
            .padding(28)
        }
        .onChange(of: selectedAvatarItem) { _, item in
            Task { await loadAvatarPreview(from: item) }
        }
        .overlay(alignment: .center) {
            if appModel.isBusy {
                ProgressView()
                    .tint(NekoTheme.soulViolet)
                    .padding(18)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            }
        }
    }

    @MainActor
    private func loadAvatarPreview(from item: PhotosPickerItem?) async {
        guard let item else { return }
        defer { selectedAvatarItem = nil }

        do {
            guard let data = try await item.loadTransferable(type: Data.self) else {
                throw NekoMediaError.unsupportedImage
            }
            avatarImageData = data
            avatarPreviewImage = UIImage(data: data)
        } catch {
            appModel.errorMessage = "读取照片失败，请重新选择一张图片。"
        }
    }
}

private struct HomeView: View {
    @EnvironmentObject private var appModel: NekoAppModel
    let onAccount: () -> Void
    @State private var isPublishSheetPresented = false
    @State private var isPersonaPresented = false
    @State private var latestPublishedVoice: CatVoiceResult?
    @State private var selectedVoice: CatVoiceResult?
    @State private var isVoiceDetailPresented = false
    @State private var actionVoice: CatVoiceResult?
    @State private var confirmDeleteVoice: CatVoiceResult?

    private var homeVoices: [CatVoiceResult] {
        var voices: [CatVoiceResult] = []
        var seen = Set<String>()
        for voice in ([latestPublishedVoice].compactMap { $0 } + appModel.voices) {
            let key = voiceKey(voice)
            if seen.insert(key).inserted {
                voices.append(voice)
            }
        }
        return voices
    }

    private var voiceGroups: [HomeVoiceGroup] {
        homeVoices.reduce(into: [HomeVoiceGroup]()) { groups, voice in
            let label = dayLabel(for: voice)
            if let last = groups.indices.last, groups[last].label == label {
                groups[last].voices.append(voice)
            } else {
                groups.append(HomeVoiceGroup(label: label, voices: [voice]))
            }
        }
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            NekoBackground()

            GeometryReader { proxy in
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 0) {
                        if let profile = appModel.catProfile {
                            HomeProfileCard(profile: profile, persona: appModel.persona) {
                                isPersonaPresented = true
                            }
                            .padding(.horizontal, 20)
                            .padding(.top, 34)

                            HStack(spacing: 8) {
                                Text("💭")
                                    .font(.system(size: 18))
                                Text("猫咪心声")
                                    .font(.system(size: NekoTypography.web(16), weight: .medium))
                                    .foregroundStyle(NekoTheme.ink)
                            }
                            .padding(.horizontal, 20)
                            .padding(.top, 26)

                            if !homeVoices.isEmpty {
                                VStack(spacing: 18) {
                                    ForEach(voiceGroups) { group in
                                        VStack(spacing: 10) {
                                            DayDivider(label: group.label)
                                            ForEach(group.voices, id: \.id) { voice in
                                                TimelineVoiceRow(
                                                    availableWidth: max(proxy.size.width - 40, 1),
                                                    voice: voice,
                                                    profile: profile,
                                                    onSelect: {
                                                        selectedVoice = voice
                                                        isVoiceDetailPresented = true
                                                    },
                                                    onMore: {
                                                        actionVoice = voice
                                                    }
                                                )
                                            }
                                        }
                                    }
                                }
                                .padding(.horizontal, 20)
                                .padding(.top, 12)
                            } else {
                                EmptyFeedCard(profile: profile) {
                                    isPublishSheetPresented = true
                                }
                                .padding(.horizontal, 20)
                                .padding(.top, 14)
                            }
                        } else {
                            MissingProfileCard {
                                appModel.startOnboarding()
                            }
                            .padding(.horizontal, 20)
                            .padding(.top, 88)
                        }
                    }
                    .padding(.bottom, 156)
                    .frame(width: proxy.size.width, alignment: .leading)
                }
            }

            HomeTabBar(
                active: .home,
                onHome: {},
                onPublish: { isPublishSheetPresented = true },
                onAccount: onAccount
            )
            .zIndex(110)

            if let actionVoice {
                VoiceActionSheet(
                    title: "猫咪心声",
                    saveText: "保存长图",
                    showDelete: true,
                    onClose: { self.actionVoice = nil },
                    onSave: {
                        self.actionVoice = nil
                        appModel.noticeMessage = "保存长图稍后继续接相册。"
                    },
                    onDelete: {
                        self.actionVoice = nil
                        confirmDeleteVoice = actionVoice
                    }
                )
                .zIndex(130)
            }

            if let confirmDeleteVoice {
                ConfirmSheetOverlay(
                    title: "确定删除这条心声吗？",
                    hint: "删除后无法恢复，\(appModel.catProfile?.name ?? "猫咪")的这一刻就会消失喵～",
                    confirmText: "删除",
                    danger: true,
                    onConfirm: { deleteVoice(confirmDeleteVoice) },
                    onCancel: { self.confirmDeleteVoice = nil }
                )
                .zIndex(140)
            }
        }
        .ignoresSafeArea(.container, edges: .bottom)
        .fullScreenCover(isPresented: $isPublishSheetPresented) {
            VoicePublishSheet(latestPublishedVoice: $latestPublishedVoice)
                .environmentObject(appModel)
        }
        .navigationDestination(isPresented: $isPersonaPresented) {
            if let profile = appModel.catProfile {
                PersonaDetailView(profile: profile, persona: appModel.persona)
            } else {
                MissingProfileCard {
                    appModel.startOnboarding()
                }
                .padding(24)
                .background { NekoBackground() }
            }
        }
        .navigationDestination(isPresented: $isVoiceDetailPresented) {
            if let selectedVoice {
                VoiceDetailView(
                    voice: selectedVoice,
                    profile: appModel.catProfile,
                    persona: appModel.persona
                )
                .environmentObject(appModel)
            } else {
                MissingProfileCard {
                    appModel.startOnboarding()
                }
                .padding(24)
                .background { NekoBackground() }
            }
        }
        .task(id: appModel.catProfile?.id) {
            guard appModel.catProfile != nil else { return }
            do {
                _ = try await appModel.reloadVoices()
            } catch {
                appModel.errorMessage = "猫咪心声加载失败"
            }
        }
    }

    private func voiceKey(_ voice: CatVoiceResult) -> String {
        if let cloudId = voice.cloudId, !cloudId.isEmpty {
            return cloudId
        }
        return "\(voice.createdAt ?? 0)-\(voice.text)-\(voice.mediaObjectKey ?? "")"
    }

    private func dayLabel(for voice: CatVoiceResult) -> String {
        guard let createdAt = voice.createdAt else { return "今天" }
        let date = Date(timeIntervalSince1970: Double(createdAt) / 1000)
        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            return "今天"
        }
        if calendar.isDateInYesterday(date) {
            return "昨天"
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "MM 月 dd 日"
        return formatter.string(from: date)
    }

    private func deleteVoice(_ voice: CatVoiceResult) {
        guard let cloudId = voice.cloudId, !cloudId.isEmpty else {
            confirmDeleteVoice = nil
            latestPublishedVoice = nil
            appModel.noticeMessage = "已移除本地心声"
            return
        }

        Task {
            do {
                try await appModel.deleteVoices(ids: [cloudId])
                if latestPublishedVoice?.cloudId == cloudId {
                    latestPublishedVoice = nil
                }
                confirmDeleteVoice = nil
                appModel.noticeMessage = "心声已删除"
            } catch {
                confirmDeleteVoice = nil
                appModel.errorMessage = NekoUserFacingError.message(
                    for: error,
                    fallback: "删除失败，请稍后再试。"
                )
            }
        }
    }
}

private struct HomeVoiceGroup: Identifiable {
    let label: String
    var voices: [CatVoiceResult]

    var id: String { label }
}

private struct HomeProfileCard: View {
    let profile: CatProfile
    let persona: CatPersonaResult?
    let onAccount: () -> Void

    var body: some View {
        NekoGlassCard(cornerRadius: 24, tint: true) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 12) {
                    CatAvatarView(localImage: nil, remoteURL: profile.avatarURL, objectKey: profile.avatarObjectKey, size: 46)

                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 7) {
                            Text(profile.name)
                                .font(.system(size: NekoTypography.web(14), weight: .medium))
                                .foregroundStyle(NekoTheme.ink)
                                .lineLimit(1)

                            Text(persona?.mbti ?? "INTJ-A")
                                .font(.system(size: NekoTypography.web(8.5), weight: .semibold))
                                .tracking(1.3)
                                .foregroundStyle(NekoTheme.soulViolet)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 1.5)
                                .background(Color.white.opacity(0.86), in: Capsule())
                        }

                        Text(persona?.type ?? "\(profile.gender.rawValue) · \(profile.ageStage.rawValue)")
                            .font(.system(size: NekoTypography.web(10.5), weight: .medium))
                            .foregroundStyle(NekoTheme.muted)
                            .lineLimit(1)
                    }

                    Spacer(minLength: 8)

                    Button {
                        onAccount()
                    } label: {
                        Text("查看人格 ›")
                            .font(.system(size: NekoTypography.web(10), weight: .semibold))
                            .tracking(1.6)
                            .foregroundStyle(NekoTheme.soulViolet)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(Color.white.opacity(0.86), in: Capsule())
                    }
                    .buttonStyle(.plain)
                }

                HStack(spacing: 9) {
                    Text("😺")
                        .font(.system(size: NekoTypography.web(14)))
                    Text(persona?.dailyMood ?? "今天好像有点想你")
                        .font(.system(size: NekoTypography.web(12), weight: .regular))
                        .foregroundStyle(NekoTheme.ink)
                        .lineLimit(2)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 11)
                .background(Color.white.opacity(0.66), in: RoundedRectangle(cornerRadius: 17, style: .continuous))
            }
            .padding(14)
        }
    }
}

private struct EmptyFeedCard: View {
    let profile: CatProfile
    let onPublish: () -> Void

    var body: some View {
        NekoGlassCard(cornerRadius: 24) {
            VStack(spacing: 0) {
                ZStack {
                    Circle()
                        .fill(NekoTheme.softLilac.opacity(0.58))
                        .frame(width: 76, height: 76)
                        .blur(radius: 2)

                    CatAvatarView(localImage: nil, remoteURL: profile.avatarURL, objectKey: profile.avatarObjectKey, size: 56)
                        .padding(10)
                        .background(NekoTheme.photoPlaceholderGradient, in: Circle())
                        .shadow(color: NekoTheme.soulViolet.opacity(0.18), radius: 24, x: 0, y: 10)
                }
                .frame(width: 76, height: 76)
                .overlay(alignment: .topTrailing) {
                    ZStack(alignment: .topTrailing) {
                        Circle()
                            .fill(NekoTheme.softPink.opacity(0.70))
                            .frame(width: 5.5, height: 5.5)
                            .offset(x: 12, y: -4)

                        Circle()
                            .fill(NekoTheme.softLilac.opacity(0.78))
                            .frame(width: 7.5, height: 7.5)
                            .offset(x: 24, y: -16)

                        ThoughtBubbleLabel()
                            .offset(x: 8, y: -24)
                    }
                }

                Text("还没有心声哦")
                    .font(.system(size: NekoTypography.web(15), weight: .medium))
                    .foregroundStyle(NekoTheme.ink)
                    .padding(.top, 20)

                Text("记录一个瞬间，听听它怎么说")
                    .font(.system(size: NekoTypography.web(12)))
                    .foregroundStyle(NekoTheme.muted)
                    .padding(.top, 6)

                Button {
                    onPublish()
                } label: {
                    HStack(spacing: 9) {
                        CatHeadphoneIcon()
                            .frame(width: 19, height: 19)
                        Text("识别猫咪心声")
                    }
                        .frame(maxWidth: .infinity)
                        .font(.system(size: NekoTypography.web(13), weight: .medium))
                        .foregroundStyle(.white)
                        .padding(.vertical, 10)
                        .padding(.horizontal, 24)
                        .background(NekoTheme.primaryGradient, in: Capsule())
                        .shadow(color: NekoTheme.soulViolet.opacity(0.24), radius: 18, x: 0, y: 10)
                }
                .buttonStyle(.plain)
                .padding(.top, 20)
                .frame(maxWidth: 224)
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 24)
            .padding(.vertical, 32)
            .frame(minHeight: 300)
        }
    }
}

private struct CatHeadphoneIcon: View {
    var body: some View {
        Canvas { context, size in
            let w = size.width
            let h = size.height
            let stroke = StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round)
            var path = Path()
            path.move(to: CGPoint(x: w * 0.22, y: h * 0.45))
            path.addLine(to: CGPoint(x: w * 0.16, y: h * 0.20))
            path.addLine(to: CGPoint(x: w * 0.34, y: h * 0.34))
            path.move(to: CGPoint(x: w * 0.78, y: h * 0.45))
            path.addLine(to: CGPoint(x: w * 0.84, y: h * 0.20))
            path.addLine(to: CGPoint(x: w * 0.66, y: h * 0.34))
            path.move(to: CGPoint(x: w * 0.20, y: h * 0.55))
            path.addCurve(
                to: CGPoint(x: w * 0.80, y: h * 0.55),
                control1: CGPoint(x: w * 0.22, y: h * 0.22),
                control2: CGPoint(x: w * 0.78, y: h * 0.22)
            )
            path.addRoundedRect(in: CGRect(x: w * 0.10, y: h * 0.52, width: w * 0.18, height: h * 0.28), cornerSize: CGSize(width: 3, height: 3))
            path.addRoundedRect(in: CGRect(x: w * 0.72, y: h * 0.52, width: w * 0.18, height: h * 0.28), cornerSize: CGSize(width: 3, height: 3))
            context.stroke(path, with: .color(.white.opacity(0.95)), style: stroke)
        }
    }
}

private struct ThoughtBubbleLabel: View {
    var body: some View {
        Text("喵～？")
            .font(.system(size: NekoTypography.web(11), weight: .medium))
            .foregroundStyle(NekoTheme.soulViolet)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                Color.white.opacity(0.95),
                in: UnevenRoundedRectangle(
                    topLeadingRadius: 16,
                    bottomLeadingRadius: 4,
                    bottomTrailingRadius: 16,
                    topTrailingRadius: 16,
                    style: .continuous
                )
            )
            .overlay {
                UnevenRoundedRectangle(
                    topLeadingRadius: 16,
                    bottomLeadingRadius: 4,
                    bottomTrailingRadius: 16,
                    topTrailingRadius: 16,
                    style: .continuous
                )
                .stroke(NekoTheme.softPink.opacity(0.45), lineWidth: 1)
            }
            .shadow(color: NekoTheme.soulViolet.opacity(0.14), radius: 10, x: 0, y: 5)
    }
}

private struct TimelineVoiceRow: View {
    let availableWidth: CGFloat
    let voice: CatVoiceResult
    let profile: CatProfile
    let onSelect: () -> Void
    let onMore: () -> Void

    private var cardWidth: CGFloat {
        min(max(availableWidth - 42 - 12, 1), 296)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(spacing: 6) {
                Text(voice.time)
                    .font(.system(size: NekoTypography.web(11), weight: .medium, design: .rounded))
                    .foregroundStyle(NekoTheme.soulViolet)
                    .lineLimit(1)
                Circle()
                    .fill(NekoTheme.primaryGradient)
                    .frame(width: 7, height: 7)
                    .overlay {
                        Circle().stroke(Color.white.opacity(0.9), lineWidth: 4)
                    }
                Rectangle()
                    .fill(LinearGradient(colors: [NekoTheme.softLilac.opacity(0.8), .clear], startPoint: .top, endPoint: .bottom))
                    .frame(width: 1)
                    .frame(maxHeight: .infinity)
            }
            .frame(width: 42)

            VoiceFeedCard(voice: voice, profile: profile, onSelect: onSelect, onMore: onMore)
                .frame(width: cardWidth)
        }
        .frame(width: availableWidth, alignment: .leading)
    }
}

private struct NekoFlowLayout: Layout {
    var spacing: CGFloat = 8
    var lineSpacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let proposedWidth = proposal.width ?? .infinity
        let maxWidth = proposedWidth.isFinite ? proposedWidth : CGFloat.greatestFiniteMagnitude
        var cursorX: CGFloat = 0
        var cursorY: CGFloat = 0
        var lineHeight: CGFloat = 0
        var measuredWidth: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if cursorX > 0, cursorX + size.width > maxWidth {
                cursorY += lineHeight + lineSpacing
                cursorX = 0
                lineHeight = 0
            }

            measuredWidth = max(measuredWidth, cursorX + size.width)
            cursorX += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }

        let finalWidth = proposedWidth.isFinite ? proposedWidth : measuredWidth
        return CGSize(width: finalWidth, height: cursorY + lineHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var cursorX = bounds.minX
        var cursorY = bounds.minY
        var lineHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if cursorX > bounds.minX, cursorX + size.width > bounds.maxX {
                cursorY += lineHeight + lineSpacing
                cursorX = bounds.minX
                lineHeight = 0
            }

            subview.place(
                at: CGPoint(x: cursorX, y: cursorY),
                proposal: ProposedViewSize(width: size.width, height: size.height)
            )
            cursorX += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
    }
}

private struct VoiceTagChip: View {
    let tag: String
    var compact = false

    var body: some View {
        Text(tag)
            .font(.system(size: compact ? 10.5 : 10.5, weight: .semibold))
            .foregroundStyle(NekoTheme.soulViolet)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .padding(.horizontal, compact ? 10 : 8)
            .padding(.vertical, compact ? 5 : 4)
            .background(
                LinearGradient(
                    colors: [NekoTheme.softPink.opacity(0.86), NekoTheme.softLilac.opacity(0.76)],
                    startPoint: .leading,
                    endPoint: .trailing
                ),
                in: Capsule()
            )
    }
}

private struct VoiceFeedCard: View {
    let voice: CatVoiceResult
    let profile: CatProfile
    let onSelect: () -> Void
    let onMore: () -> Void

    var body: some View {
        NekoGlassCard(cornerRadius: 24) {
            VStack(alignment: .leading, spacing: 0) {
                Button(action: onSelect) {
                    ZStack(alignment: .topLeading) {
                        VoiceMediaImageView(
                            url: voice.mediaURL,
                            objectKey: voice.mediaObjectKey,
                            mediaType: voice.mediaType,
                            aspect: voice.aspect,
                            contentMode: .fill,
                            fallbackAvatarURL: profile.avatarURL,
                            fallbackAvatarObjectKey: profile.avatarObjectKey,
                            preferNaturalAspect: true
                        )

                        LinearGradient(
                            colors: [Color.black.opacity(0.18), .clear],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                        .frame(maxHeight: 160)

                        VStack(alignment: .leading, spacing: 5) {
                            Text(profile.name)
                                .font(.system(size: NekoTypography.web(8), weight: .semibold))
                                .tracking(3)
                                .foregroundStyle(NekoTheme.muted)
                            Text("💭 \(voice.text)")
                                .font(.system(size: NekoTypography.web(12.5), weight: .regular))
                                .lineSpacing(4)
                                .foregroundStyle(NekoTheme.ink)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 11)
                        .background(Color.white.opacity(0.95), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                        .padding(14)
                        .shadow(color: NekoTheme.ink.opacity(0.10), radius: 20, x: 0, y: 10)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                }
                .buttonStyle(.plain)

                HStack(alignment: .bottom, spacing: 8) {
                    Button(action: onSelect) {
                        NekoFlowLayout(spacing: 8, lineSpacing: 7) {
                            ForEach(Array(voice.tags.prefix(3)), id: \.self) { tag in
                                VoiceTagChip(tag: tag, compact: true)
                            }

                            if let location = voice.location, !location.isEmpty {
                                Text("· \(location)")
                                    .font(.system(size: NekoTypography.web(10.5)))
                                    .foregroundStyle(NekoTheme.muted)
                                    .lineLimit(1)
                                    .fixedSize(horizontal: true, vertical: false)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                    .frame(maxWidth: .infinity, alignment: .leading)

                    Button(action: onMore) {
                        Text("⋯")
                            .font(.system(size: 18, weight: .medium))
                            .foregroundStyle(NekoTheme.muted)
                            .frame(width: 28, height: 28)
                            .background(Color.clear, in: Circle())
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 14)
                .padding(.top, 10)
                .padding(.bottom, 12)
            }
        }
    }
}

private enum VoiceMediaOrientation {
    case portrait
    case landscape
    case square
}

private enum VoiceMediaMetrics {
    static func aspectRatio(for value: String?, image: UIImage? = nil) -> CGFloat {
        switch orientation(for: value, image: image) {
        case .portrait:
            return 3.0 / 4.0
        case .landscape:
            return 4.0 / 3.0
        case .square:
            return 1.0
        }
    }

    static func feedHeight(for value: String?, image: UIImage? = nil) -> CGFloat {
        switch orientation(for: value, image: image) {
        case .portrait:
            return 330
        case .landscape:
            return 224
        case .square:
            return 299
        }
    }

    static func detailHeight(for value: String?, image: UIImage? = nil) -> CGFloat {
        switch orientation(for: value, image: image) {
        case .portrait:
            return 442
        case .landscape:
            return 265
        case .square:
            return 354
        }
    }

    static func manageHeight(for value: String?) -> CGFloat {
        switch orientation(for: value) {
        case .portrait:
            return 206
        case .landscape:
            return 124
        case .square:
            return 164
        }
    }

    private static func orientation(for value: String?, image: UIImage? = nil) -> VoiceMediaOrientation {
        let ratio = NekoMediaAspect.displayRatio(for: value, image: image)

        if abs(ratio - 1) <= 0.04 {
            return .square
        }

        return ratio > 1 ? .landscape : .portrait
    }
}

struct NekoRemoteImageView<Placeholder: View>: View {
    @EnvironmentObject private var appModel: NekoAppModel

    let remoteURL: URL?
    let objectKey: String?
    let contentMode: ContentMode
    let onImageLoaded: (UIImage?) -> Void
    private let placeholder: () -> Placeholder
    @State private var loadedImage: UIImage?
    @State private var currentURL: URL?

    init(
        remoteURL: URL?,
        objectKey: String? = nil,
        contentMode: ContentMode = .fill,
        onImageLoaded: @escaping (UIImage?) -> Void = { _ in },
        @ViewBuilder placeholder: @escaping () -> Placeholder
    ) {
        self.remoteURL = remoteURL
        self.objectKey = objectKey
        self.contentMode = contentMode
        self.onImageLoaded = onImageLoaded
        self.placeholder = placeholder
    }

    private var imageSourceID: String {
        "\(remoteURL?.absoluteString ?? "nil")|\(objectKey ?? "nil")|\(contentMode)"
    }

    var body: some View {
        ZStack {
            if let loadedImage {
                Image(uiImage: loadedImage)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipped()
            } else {
                placeholder()
                    .opacity(currentURL == nil ? 1 : 0.72)
            }
        }
        .task(id: imageSourceID) {
            await loadImage()
        }
    }

    @MainActor
    private func loadImage() async {
        loadedImage = nil
        currentURL = remoteURL
        onImageLoaded(nil)

        if let remoteURL, await load(from: remoteURL) {
            return
        }

        guard let refreshedURL = await appModel.signedMediaURL(
            for: objectKey,
            forceRefresh: remoteURL != nil
        ) else {
            loadedImage = nil
            onImageLoaded(nil)
            return
        }

        _ = await load(from: refreshedURL)
    }

    @MainActor
    private func load(from url: URL) async -> Bool {
        currentURL = url
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            if let httpResponse = response as? HTTPURLResponse, !(200..<300).contains(httpResponse.statusCode) {
                throw URLError(.badServerResponse)
            }
            guard let image = UIImage(data: data) else {
                throw URLError(.cannotDecodeContentData)
            }
            loadedImage = image
            onImageLoaded(image)
            return true
        } catch {
            loadedImage = nil
            onImageLoaded(nil)
            return false
        }
    }
}

private struct VoiceMediaSkeletonView: View {
    var body: some View {
        ZStack {
            NekoTheme.photoPlaceholderGradient

            Circle()
                .fill(Color.white.opacity(0.48))
                .frame(width: 128, height: 128)
                .blur(radius: 18)

            VStack(spacing: 13) {
                ZStack {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(Color.white.opacity(0.48))
                        .frame(width: 76, height: 60)

                    Image(systemName: "photo")
                        .font(.system(size: 26, weight: .regular))
                        .foregroundStyle(NekoTheme.soulViolet.opacity(0.48))
                }

                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(Color.white.opacity(0.58))
                    .frame(width: 112, height: 8)

                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(Color.white.opacity(0.38))
                    .frame(width: 78, height: 7)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct VoiceMediaImageView: View {
    @EnvironmentObject private var appModel: NekoAppModel

    let url: URL?
    let objectKey: String?
    let mediaType: String?
    let aspect: String?
    let contentMode: ContentMode
    let fallbackAvatarURL: URL?
    let fallbackAvatarObjectKey: String?
    var maxHeight: CGFloat = 420
    var preferNaturalAspect: Bool = true
    @State private var loadedImage: UIImage?

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                NekoTheme.photoPlaceholderGradient

                if mediaType == "video" {
                    fallbackContent
                } else {
                    NekoRemoteImageView(
                        remoteURL: url,
                        objectKey: objectKey,
                        contentMode: contentMode,
                        onImageLoaded: { loadedImage = $0 }
                    ) {
                        VoiceMediaSkeletonView()
                    }
                    .frame(width: proxy.size.width, height: mediaHeight)
                    .clipped()
                }
            }
            .frame(width: proxy.size.width, height: mediaHeight)
            .clipped()
        }
        .frame(height: mediaHeight)
        .clipped()
    }

    private var mediaHeight: CGFloat {
        return VoiceMediaMetrics.feedHeight(for: aspect, image: loadedImage)
    }

    @ViewBuilder
    private var fallbackContent: some View {
        if mediaType == "video" {
            Image(systemName: "play.circle.fill")
                .font(.system(size: 42, weight: .regular))
                .foregroundStyle(Color.white.opacity(0.92), NekoTheme.soulViolet.opacity(0.65))
        } else {
            VoiceMediaSkeletonView()
        }
    }
}

private struct VoiceDetailMediaFillView: View {
    let url: URL?
    let objectKey: String?
    let mediaType: String?
    let fallbackAvatarURL: URL?
    let fallbackAvatarObjectKey: String?
    var onImageLoaded: (UIImage?) -> Void = { _ in }

    var body: some View {
        ZStack {
            NekoTheme.photoPlaceholderGradient

            if mediaType == "video" {
                Image(systemName: "play.circle.fill")
                    .font(.system(size: 42, weight: .regular))
                    .foregroundStyle(Color.white.opacity(0.92), NekoTheme.soulViolet.opacity(0.65))
            } else {
                NekoRemoteImageView(
                    remoteURL: url,
                    objectKey: objectKey,
                    contentMode: .fill,
                    onImageLoaded: onImageLoaded
                ) {
                    VoiceMediaSkeletonView()
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct VoiceActionSheet: View {
    let title: String
    let saveText: String
    let showDelete: Bool
    let onClose: () -> Void
    let onSave: () -> Void
    let onDelete: () -> Void

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.black.opacity(0.10)
                .ignoresSafeArea()
                .background(.ultraThinMaterial.opacity(0.45))
                .onTapGesture(perform: onClose)

            VStack(spacing: 0) {
                Capsule()
                    .fill(Color(red: 0.847, green: 0.824, blue: 0.886))
                    .frame(width: 72, height: 3)
                    .padding(.top, 14)
                    .padding(.bottom, 20)

                Text(title)
                    .font(.system(size: NekoTypography.web(13), weight: .medium))
                    .foregroundStyle(NekoTheme.ink)
                    .padding(.bottom, 18)

                HStack(alignment: .top, spacing: 48) {
                    Button(action: onSave) {
                        VStack(spacing: 10) {
                            ZStack {
                                Circle()
                                    .fill(NekoTheme.primaryGradient)
                                    .frame(width: 56, height: 56)
                                    .shadow(color: NekoTheme.soulViolet.opacity(0.28), radius: 22, x: 0, y: 10)
                                SavePosterIcon()
                                    .frame(width: 25, height: 25)
                            }
                            Text(saveText)
                                .font(.system(size: NekoTypography.web(12.5), weight: .regular))
                                .foregroundStyle(NekoTheme.ink)
                        }
                    }
                    .buttonStyle(.plain)

                    if showDelete {
                        Button(action: onDelete) {
                            VStack(spacing: 10) {
                                ZStack {
                                    Circle()
                                        .fill(Color(red: 0.988, green: 0.910, blue: 0.929))
                                        .frame(width: 56, height: 56)
                                    Image(systemName: "trash")
                                        .font(.system(size: 22, weight: .regular))
                                        .foregroundStyle(Color(red: 0.941, green: 0.541, blue: 0.639))
                                }
                                Text("删除")
                                    .font(.system(size: NekoTypography.web(12.5), weight: .regular))
                                    .foregroundStyle(NekoTheme.muted)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.bottom, 8)
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 24)
            .padding(.bottom, 28)
            .background(
                Color(red: 0.992, green: 0.984, blue: 1.0).opacity(0.96),
                in: UnevenRoundedRectangle(topLeadingRadius: 32, topTrailingRadius: 32, style: .continuous)
            )
            .shadow(color: NekoTheme.ink.opacity(0.20), radius: 34, x: 0, y: -14)
        }
        .transition(.opacity.combined(with: .move(edge: .bottom)))
    }
}

private struct SavePosterIcon: View {
    var body: some View {
        Canvas { context, size in
            let stroke = StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round)
            let w = size.width
            let h = size.height
            var path = Path()

            path.addRoundedRect(
                in: CGRect(x: w * 0.10, y: h * 0.10, width: w * 0.58, height: h * 0.58),
                cornerSize: CGSize(width: 4, height: 4)
            )
            path.move(to: CGPoint(x: w * 0.10, y: h * 0.52))
            path.addLine(to: CGPoint(x: w * 0.24, y: h * 0.38))
            path.addCurve(
                to: CGPoint(x: w * 0.50, y: h * 0.40),
                control1: CGPoint(x: w * 0.32, y: h * 0.30),
                control2: CGPoint(x: w * 0.42, y: h * 0.31)
            )
            path.addLine(to: CGPoint(x: w * 0.68, y: h * 0.66))
            path.addEllipse(in: CGRect(x: w * 0.48, y: h * 0.25, width: w * 0.10, height: h * 0.10))
            path.move(to: CGPoint(x: w * 0.78, y: h * 0.56))
            path.addLine(to: CGPoint(x: w * 0.78, y: h * 0.88))
            path.move(to: CGPoint(x: w * 0.64, y: h * 0.74))
            path.addLine(to: CGPoint(x: w * 0.78, y: h * 0.88))
            path.addLine(to: CGPoint(x: w * 0.92, y: h * 0.74))

            context.stroke(path, with: .color(.white), style: stroke)
        }
    }
}

private struct VoiceBottomActionBar: View {
    let onShare: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onShare) {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: NekoTypography.web(14), weight: .semibold))
                    Text("分享")
                }
                .font(.system(size: NekoTypography.web(13), weight: .medium))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(NekoTheme.primaryGradient, in: Capsule())
                .shadow(color: NekoTheme.soulViolet.opacity(0.28), radius: 20, x: 0, y: 10)
            }
            .buttonStyle(.plain)

            Button(action: onDelete) {
                HStack(spacing: 8) {
                    Image(systemName: "trash")
                        .font(.system(size: NekoTypography.web(14), weight: .semibold))
                    Text("删除")
                }
                .font(.system(size: NekoTypography.web(13), weight: .medium))
                .foregroundStyle(.white)
                .padding(.horizontal, 22)
                .padding(.vertical, 14)
                .background(
                    LinearGradient(
                        colors: [Color(red: 0.862, green: 0.474, blue: 0.356), Color(red: 0.842, green: 0.306, blue: 0.304)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    in: Capsule()
                )
                .shadow(color: Color(red: 0.862, green: 0.474, blue: 0.356).opacity(0.24), radius: 20, x: 0, y: 10)
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 20)
        .padding(.top, 20)
        .padding(.bottom, 10)
        .background(
            LinearGradient(
                colors: [Color.white.opacity(0.0), Color(red: 0.992, green: 0.969, blue: 1.0).opacity(0.96)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea(edges: .bottom)
        )
    }
}

private struct VoiceDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appModel: NekoAppModel

    let voice: CatVoiceResult
    let profile: CatProfile?
    let persona: CatPersonaResult?
    @State private var isShareOpen = false
    @State private var confirmDelete = false

    private var catName: String {
        profile?.name ?? "猫咪"
    }

    private var analysisText: String {
        voice.analysis ?? "它似乎在表达：这个瞬间里，它正在用自己的方式向你靠近。"
    }

    private var detailAspect: String {
        voice.aspect ?? "4:5"
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            detailBackground

            ScrollView(showsIndicators: false) {
                VStack(spacing: 20) {
                    photoDetailCard
                        .padding(.horizontal, 20)

                    aiAnalysisCard
                        .padding(.horizontal, 20)
                }
                .padding(.top, 92)
                .padding(.bottom, 110)
                .frame(maxWidth: .infinity)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            VStack {
                header
                    .padding(.horizontal, 20)
                    .padding(.top, 48)
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .allowsHitTesting(true)

            VoiceBottomActionBar(
                onShare: { isShareOpen = true },
                onDelete: { confirmDelete = true }
            )
            .frame(maxWidth: .infinity)
            .zIndex(20)

            if isShareOpen {
                VoiceActionSheet(
                    title: "分享猫咪心声",
                    saveText: "保存长图",
                    showDelete: false,
                    onClose: { isShareOpen = false },
                    onSave: {
                        isShareOpen = false
                        appModel.noticeMessage = "保存长图稍后继续接相册。"
                    },
                    onDelete: {}
                )
                .zIndex(30)
            }

            if confirmDelete {
                ConfirmSheetOverlay(
                    title: "确定删除这条心声吗？",
                    hint: "删除后无法恢复，\(catName)的这一刻就会消失喵～",
                    confirmText: "删除",
                    danger: true,
                    onConfirm: deleteCurrentVoice,
                    onCancel: { confirmDelete = false }
                )
                .zIndex(40)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationBarBackButtonHidden(true)
        .nekoEdgeSwipeBack {
            if confirmDelete {
                confirmDelete = false
            } else if isShareOpen {
                isShareOpen = false
            } else {
                dismiss()
            }
        }
    }

    private var detailBackground: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.996, green: 0.982, blue: 0.946),
                    Color(red: 0.993, green: 0.954, blue: 0.982),
                    Color(red: 0.967, green: 0.942, blue: 0.998)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            Circle()
                .fill(Color(red: 0.96, green: 0.72, blue: 0.88).opacity(0.28))
                .frame(width: 220, height: 220)
                .blur(radius: 46)
                .offset(x: -150, y: -240)

            Circle()
                .fill(Color(red: 0.98, green: 0.88, blue: 0.58).opacity(0.22))
                .frame(width: 190, height: 190)
                .blur(radius: 48)
                .offset(x: 150, y: -70)

            NekoSparkles(count: 18)
                .opacity(0.56)
        }
    }

    private var header: some View {
        HStack {
            AppBackCircleButton {
                dismiss()
            }

            Spacer()

            Text("心声 · \(voice.time)")
                .font(.system(size: NekoTypography.web(11), weight: .medium))
                .tracking(3.6)
                .foregroundStyle(Color(red: 0.43, green: 0.38, blue: 0.52))
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(Color.white.opacity(0.80), in: Capsule())
                .shadow(color: NekoTheme.soulViolet.opacity(0.10), radius: 16, x: 0, y: 8)

            Spacer()

            Color.clear.frame(width: 36, height: 36)
        }
        .frame(maxWidth: .infinity)
    }

    private var photoDetailCard: some View {
        let cardHeight = VoiceMediaMetrics.detailHeight(for: detailAspect)

        return GeometryReader { proxy in
            let cardWidth = max(proxy.size.width, 1)

            ZStack(alignment: .topLeading) {
                VoiceDetailMediaFillView(
                    url: voice.mediaURL,
                    objectKey: voice.mediaObjectKey,
                    mediaType: voice.mediaType,
                    fallbackAvatarURL: profile?.avatarURL,
                    fallbackAvatarObjectKey: profile?.avatarObjectKey
                )
                .frame(width: cardWidth, height: cardHeight)
                .clipped()

                VStack(alignment: .leading, spacing: 6) {
                    Text(catName)
                        .font(.system(size: NekoTypography.web(10), weight: .medium))
                        .tracking(3.2)
                        .foregroundStyle(Color(red: 0.482, green: 0.447, blue: 0.565))

                    Text(voice.text)
                        .font(.system(size: NekoTypography.web(12.5), weight: .regular))
                        .foregroundStyle(NekoTheme.ink.opacity(0.90))
                        .lineSpacing(6)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 14)
                .frame(maxWidth: cardWidth - 56, alignment: .leading)
                .background(Color.white, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                .overlay(alignment: .bottomLeading) {
                    Rectangle()
                        .fill(Color.white)
                        .frame(width: 12, height: 12)
                        .rotationEffect(.degrees(45))
                        .offset(x: 38, y: 6)
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(Color.white.opacity(0.90), lineWidth: 1)
                }
                .shadow(color: NekoTheme.ink.opacity(0.11), radius: 24, x: 0, y: 12)
                .padding(.leading, 16)
                .padding(.top, 16)
            }
            .frame(width: cardWidth, height: cardHeight)
            .background(Color.white, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
            .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .stroke(Color.white.opacity(0.85), lineWidth: 1)
            }
            .shadow(color: NekoTheme.ink.opacity(0.16), radius: 28, x: 0, y: 16)
        }
        .frame(height: cardHeight)
    }

    private var aiAnalysisCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Text("✨")
                    .font(.system(size: NekoTypography.web(11)))
                Text("AI 心 声 解 析")
                    .font(.system(size: NekoTypography.web(10), weight: .medium))
                    .tracking(3.6)
                    .foregroundStyle(Color(red: 0.482, green: 0.447, blue: 0.565))
            }

            Text(analysisText)
                .font(.system(size: NekoTypography.web(12.5), weight: .regular))
                .foregroundStyle(NekoTheme.ink.opacity(0.85))
                .lineSpacing(6)
                .padding(.top, 10)

            if !voice.tags.isEmpty {
                NekoFlowLayout(spacing: 6, lineSpacing: 6) {
                    ForEach(voice.tags, id: \.self) { tag in
                        VoiceTagChip(tag: "#\(tag)")
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 12)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        .padding(.vertical, 18)
        .background(Color.white.opacity(0.95), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color.white.opacity(0.90), lineWidth: 1)
        }
        .shadow(color: NekoTheme.ink.opacity(0.12), radius: 24, x: 0, y: 12)
    }

    private func deleteCurrentVoice() {
        guard let cloudId = voice.cloudId, !cloudId.isEmpty else {
            confirmDelete = false
            dismiss()
            return
        }

        Task {
            do {
                try await appModel.deleteVoices(ids: [cloudId])
                confirmDelete = false
                appModel.noticeMessage = "心声已删除"
                dismiss()
            } catch {
                confirmDelete = false
                appModel.errorMessage = NekoUserFacingError.message(
                    for: error,
                    fallback: "删除失败，请稍后再试。"
                )
            }
        }
    }
}

private struct DayDivider: View {
    let label: String

    var body: some View {
        HStack(spacing: 12) {
            LinearGradient(colors: [.clear, NekoTheme.softLilac.opacity(0.72)], startPoint: .leading, endPoint: .trailing)
                .frame(height: 1)
            Text(label)
                .font(.system(size: NekoTypography.web(10), weight: .semibold))
                .tracking(3)
                .foregroundStyle(NekoTheme.soulViolet)
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
                .background(Color.white.opacity(0.82), in: Capsule())
            LinearGradient(colors: [NekoTheme.softLilac.opacity(0.72), .clear], startPoint: .leading, endPoint: .trailing)
                .frame(height: 1)
        }
    }
}

private struct MissingProfileCard: View {
    let onCreate: () -> Void

    var body: some View {
        NekoGlassCard(cornerRadius: 28) {
            VStack(spacing: 16) {
                Text("N E K O . I D")
                    .font(.system(size: NekoTypography.web(10), weight: .semibold))
                    .tracking(5)
                    .foregroundStyle(NekoTheme.soulViolet)
                Text("还没有猫咪档案")
                    .font(.system(size: 28, weight: .light))
                    .foregroundStyle(NekoTheme.ink)
                Button("开始创建") {
                    onCreate()
                }
                .buttonStyle(NekoPrimaryButtonStyle())
            }
            .frame(maxWidth: .infinity)
            .padding(24)
        }
    }
}

private struct HomeTabBar: View {
    enum Selection {
        case home
        case me
    }

    let active: Selection
    let onHome: () -> Void
    let onPublish: () -> Void
    let onAccount: () -> Void

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.white
                .frame(maxWidth: .infinity)
                .frame(height: 102)
                .ignoresSafeArea(.container, edges: .bottom)

            HStack {
                Button(action: onHome) {
                    HomeTabIcon(kind: .voice, label: "首页", active: active == .home)
                }
                .buttonStyle(.plain)

                Spacer()

                Button(action: onPublish) {
                    ZStack {
                        Circle()
                            .fill(NekoTheme.primaryGradient)
                            .frame(width: 60, height: 60)
                            .blur(radius: 7)
                            .opacity(0.66)

                        Circle()
                            .fill(NekoTheme.primaryGradient)
                            .frame(width: 56, height: 56)
                            .shadow(color: NekoTheme.soulViolet.opacity(0.36), radius: 22, x: 0, y: 12)
                            .overlay {
                                Circle().stroke(Color.white.opacity(0.65), lineWidth: 2)
                            }
                        Text("＋")
                            .font(.system(size: 25, weight: .medium))
                            .foregroundStyle(.white)
                            .offset(y: -1)
                    }
                    .offset(y: -22)
                    .zIndex(1)
                }
                .buttonStyle(.plain)

                Spacer()

                Button(action: onAccount) {
                    HomeTabIcon(kind: .cat, label: "我的", active: active == .me)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 36)
            .padding(.top, 4)
            .padding(.bottom, 4)
            .background {
                RoundedRectangle(cornerRadius: 32, style: .continuous)
                    .fill(Color.white)
                RoundedRectangle(cornerRadius: 32, style: .continuous)
                    .stroke(Color.white.opacity(0.78), lineWidth: 1)
            }
            .shadow(color: NekoTheme.soulViolet.opacity(0.18), radius: 22, x: 0, y: 10)
            .padding(.horizontal, 16)
            .padding(.bottom, 4)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 102, alignment: .bottom)
        .ignoresSafeArea(.container, edges: .bottom)
    }
}

private struct HomeTabIcon: View {
    let kind: NekoTabSymbol.Kind
    let label: String
    let active: Bool

    var body: some View {
        VStack(spacing: 3) {
            NekoTabSymbol(kind: kind, active: active)
                .frame(width: 22, height: 22)
            Text(label)
                .font(.system(size: NekoTypography.web(9.5), weight: .medium))
                .tracking(1.6)
        }
        .foregroundStyle(active ? NekoTheme.tabActive : NekoTheme.tabInactive)
        .frame(width: 46)
    }
}

private struct MeView: View {
    @EnvironmentObject private var appModel: NekoAppModel
    let onHome: () -> Void
    @State private var isPublishSheetPresented = false
    @State private var isAccountPresented = false
    @State private var isEditProfilePresented = false
    @State private var isManageVoicesPresented = false
    @State private var latestPublishedVoice: CatVoiceResult?

    var body: some View {
        ZStack(alignment: .bottom) {
            NekoBackground()

            GeometryReader { proxy in
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 0) {
                        HStack {
                            Text("我的")
                                .font(.system(size: NekoTypography.web(17), weight: .light))
                                .tracking(1)
                                .foregroundStyle(NekoTheme.ink)

                            Spacer()
                        }
                        .padding(.horizontal, 24)
                        .padding(.top, 52)

                        if let profile = appModel.catProfile {
                            MeSummaryCard(profile: profile, persona: appModel.persona)
                                .padding(.horizontal, 20)
                                .padding(.top, 16)
                        }

                        AccountQuickPanel {
                            isAccountPresented = true
                        }
                            .padding(.horizontal, 20)
                            .padding(.top, 16)

                        VStack(spacing: 10) {
                            MeRowButton(icon: "☁︎", title: "账号与数据", sub: "手机号登录、昵称和账号管理") {
                                isAccountPresented = true
                            }
                            MeRowButton(icon: "✎", title: "修改人格档案", sub: "编辑猫咪基本信息") {
                                isEditProfilePresented = true
                            }
                            MeRowButton(icon: "♡", title: "管理猫咪心声", sub: "查看和管理所有心声") {
                                isManageVoicesPresented = true
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 20)
                        .padding(.bottom, 112)
                    }
                }
            }

            HomeTabBar(
                active: .me,
                onHome: onHome,
                onPublish: { isPublishSheetPresented = true },
                onAccount: {}
            )
            .zIndex(110)
        }
        .ignoresSafeArea(.container, edges: .bottom)
        .fullScreenCover(isPresented: $isPublishSheetPresented) {
            VoicePublishSheet(latestPublishedVoice: $latestPublishedVoice)
                .environmentObject(appModel)
        }
        .navigationDestination(isPresented: $isAccountPresented) {
            AccountCenterView()
                .environmentObject(appModel)
        }
        .navigationDestination(isPresented: $isEditProfilePresented) {
            EditProfileView()
                .environmentObject(appModel)
        }
        .navigationDestination(isPresented: $isManageVoicesPresented) {
            ManageVoicesView(isPublishSheetPresented: $isPublishSheetPresented)
                .environmentObject(appModel)
        }
    }
}

private struct MeSummaryCard: View {
    let profile: CatProfile
    let persona: CatPersonaResult?

    var body: some View {
        NekoGlassCard(cornerRadius: 26, tint: true) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 16) {
                    ZStack {
                        Circle()
                            .fill(Color.white.opacity(0.60))
                            .frame(width: 80, height: 80)
                            .blur(radius: 4)
                        CatAvatarView(localImage: nil, remoteURL: profile.avatarURL, objectKey: profile.avatarObjectKey, size: 72)
                    }

                    VStack(alignment: .leading, spacing: 7) {
                        Text(profile.name)
                            .font(.system(size: 18, weight: .medium))
                            .foregroundStyle(NekoTheme.ink)

                        HStack(spacing: 6) {
                            Text("✦")
                                .foregroundStyle(NekoTheme.soulViolet)
                            Text("\(persona?.type ?? "\(profile.gender.rawValue) · \(profile.ageStage.rawValue)") · \(persona?.mbti ?? "INTJ-A")")
                                .lineLimit(1)
                        }
                        .font(.system(size: NekoTypography.web(10), weight: .medium))
                        .tracking(1.4)
                        .foregroundStyle(NekoTheme.soulViolet)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.white.opacity(0.80), in: Capsule())
                    }

                    Spacer(minLength: 0)
                }

                Text("\"\(persona?.monologue ?? "它喜欢在窗边看世界，但只要你叫它的名字，它就会立刻回头。")\"")
                    .font(.system(size: NekoTypography.web(11.5)))
                    .foregroundStyle(NekoTheme.ink.opacity(0.78))
                    .lineSpacing(4)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 11)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.white.opacity(0.65), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .padding(20)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct AccountQuickPanel: View {
    @EnvironmentObject private var appModel: NekoAppModel
    let onAccountCenter: () -> Void

    var body: some View {
        NekoGlassCard(cornerRadius: 22) {
            VStack(alignment: .leading, spacing: 0) {
                if let account = appModel.session?.user.loginIdentifier {
                    HStack(alignment: .top, spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            CloudMemoryTitle()

                            Text(account)
                                .font(.system(size: NekoTypography.web(12), weight: .regular))
                                .foregroundStyle(NekoTheme.ink.opacity(0.80))
                                .lineLimit(1)
                        }

                        Spacer(minLength: 10)

                        Button("退出") {
                            appModel.signOut()
                        }
                        .font(.system(size: NekoTypography.web(11), weight: .regular))
                        .foregroundStyle(NekoTheme.muted)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(Color.white.opacity(0.90), in: Capsule())
                        .buttonStyle(.plain)
                    }

                    Button("账号中心", action: onAccountCenter)
                        .font(.system(size: NekoTypography.web(12), weight: .regular))
                        .foregroundStyle(NekoTheme.ink)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Color.white.opacity(0.90), in: Capsule())
                        .padding(.top, 12)
                        .buttonStyle(.plain)
                } else {
                    CloudMemoryTitle()

                    Text("登录后，猫咪档案、人格和心声会自动绑定到你的账号。现在支持手机号验证码登录。")
                        .font(.system(size: NekoTypography.web(11.5)))
                        .foregroundStyle(NekoTheme.ink.opacity(0.75))
                        .lineSpacing(4)
                        .padding(.top, 10)

                    Button {
                        appModel.noticeMessage = "你已经在 App 内使用手机号验证码登录。"
                    } label: {
                        Text("手机号验证码登录")
                            .frame(maxWidth: .infinity)
                    }
                    .font(.system(size: NekoTypography.web(12), weight: .medium))
                    .foregroundStyle(.white)
                    .padding(.vertical, 11)
                    .background(NekoTheme.primaryGradient, in: Capsule())
                    .padding(.top, 14)
                    .buttonStyle(.plain)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct CloudMemoryTitle: View {
    var body: some View {
        HStack(spacing: 8) {
            Text("✦")
                .font(.system(size: NekoTypography.web(13)))
                .foregroundStyle(NekoTheme.soulViolet)
            Text("账 号 同 步")
                .font(.system(size: NekoTypography.web(10), weight: .medium))
                .tracking(3.5)
                .foregroundStyle(NekoTheme.muted)
        }
    }
}

private struct MeRowButton: View {
    let icon: String
    let title: String
    let sub: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Text(icon)
                    .font(.system(size: NekoTypography.web(16), weight: .medium))
                    .foregroundStyle(NekoTheme.menuIcon)
                    .frame(width: 40, height: 40)
                    .background(NekoTheme.menuIconGradient, in: RoundedRectangle(cornerRadius: 16, style: .continuous))

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.system(size: NekoTypography.web(13.5), weight: .medium))
                        .foregroundStyle(NekoTheme.ink)
                    Text(sub)
                        .font(.system(size: NekoTypography.web(10.5)))
                        .foregroundStyle(NekoTheme.muted)
                }

                Spacer()

                Text("›")
                    .font(.system(size: NekoTypography.web(16), weight: .medium))
                    .foregroundStyle(NekoTheme.muted)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(Color.white.opacity(0.80), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(Color.white.opacity(0.70), lineWidth: 1)
            }
            .shadow(color: NekoTheme.soulViolet.opacity(0.13), radius: 18, x: 0, y: 8)
        }
        .buttonStyle(.plain)
    }
}

private struct AppBackCircleButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "chevron.left")
                .font(.system(size: NekoTypography.web(16), weight: .semibold))
                .foregroundStyle(NekoTheme.soulViolet)
                .frame(width: 36, height: 36)
                .background(Color.white.opacity(0.82), in: Circle())
                .shadow(color: NekoTheme.soulViolet.opacity(0.14), radius: 14, x: 0, y: 6)
        }
        .buttonStyle(.plain)
    }
}

private struct AccountCenterView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appModel: NekoAppModel
    @State private var summary: NekoAccountSummary?
    @State private var displayName = ""
    @State private var busyAction: String? = "load"

    var body: some View {
        ZStack {
            NekoBackground()

            if busyAction == "load" && summary == nil {
                Text("正在读取账号信息…")
                    .font(.system(size: NekoTypography.web(13), weight: .regular))
                    .foregroundStyle(NekoTheme.muted)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if appModel.session == nil {
                AccountNeedLoginView()
            } else {
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 0) {
                        AccountTopBar(title: "账号中心") {
                            dismiss()
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 52)

                        accountHero
                            .padding(.horizontal, 20)
                            .padding(.top, 20)

                        nicknameCard
                            .padding(.horizontal, 20)
                            .padding(.top, 16)

                        autoSyncCard
                            .padding(.horizontal, 20)
                            .padding(.top, 16)

                        Button {
                            runAccountAction("signout") {
                                appModel.signOut()
                                dismiss()
                            }
                        } label: {
                            Text(busyAction == "signout" ? "退出中…" : "退出登录")
                                .font(.system(size: NekoTypography.web(13), weight: .regular))
                                .foregroundStyle(NekoTheme.muted)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(Color.white.opacity(0.85), in: Capsule())
                                .shadow(color: NekoTheme.soulViolet.opacity(0.12), radius: 18, x: 0, y: 8)
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal, 20)
                        .padding(.top, 20)

                        Spacer(minLength: 40)
                    }
                    .padding(.bottom, 34)
                }
            }
        }
        .navigationBarBackButtonHidden(true)
        .nekoEdgeSwipeBack(isEnabled: busyAction != "signout") {
            dismiss()
        }
        .task {
            await reload()
        }
    }

    private var accountHero: some View {
        NekoGlassCard(cornerRadius: 26, tint: true) {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 16) {
                    CatAvatarView(localImage: nil, remoteURL: appModel.catProfile?.avatarURL, objectKey: appModel.catProfile?.avatarObjectKey, size: 68)

                    VStack(alignment: .leading, spacing: 5) {
                        Text(summary?.profile.displayName?.nonEmpty ?? "NEKO 用户")
                            .font(.system(size: NekoTypography.web(17), weight: .medium))
                            .foregroundStyle(NekoTheme.ink)
                            .lineLimit(1)
                        Text(appModel.session?.user.loginIdentifier ?? summary?.profile.email ?? "未登录")
                            .font(.system(size: NekoTypography.web(11), weight: .regular))
                            .foregroundStyle(NekoTheme.muted)
                            .lineLimit(1)
                    }

                    Spacer(minLength: 0)
                }

                HStack(spacing: 8) {
                    AccountStatCard(label: "猫咪档案", value: summary?.catCount ?? 0)
                    AccountStatCard(label: "猫咪心声", value: summary?.voiceCount ?? appModel.voices.count)
                }
            }
            .padding(20)
        }
        .frame(maxWidth: .infinity)
    }

    private var nicknameCard: some View {
        AccountSectionCard {
            VStack(alignment: .leading, spacing: 0) {
                Text("昵称")
                    .font(.system(size: NekoTypography.web(10), weight: .medium))
                    .tracking(3.2)
                    .foregroundStyle(NekoTheme.muted)

                TextField("NEKO 用户", text: clippedDisplayName)
                    .font(.system(size: NekoTypography.web(13), weight: .regular))
                    .foregroundStyle(NekoTheme.ink)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 13)
                    .background(NekoTheme.field, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .padding(.top, 9)

                Button {
                    runAccountAction("saveName") {
                        let profile = try await appModel.updateDisplayName(displayName)
                        summary = NekoAccountSummary(
                            profile: profile,
                            catCount: summary?.catCount ?? 0,
                            voiceCount: summary?.voiceCount ?? appModel.voices.count
                        )
                        displayName = profile.displayName ?? ""
                        appModel.noticeMessage = "昵称已更新"
                    }
                } label: {
                    Text(busyAction == "saveName" ? "保存中…" : "保存昵称")
                        .font(.system(size: NekoTypography.web(12.5), weight: .medium))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(NekoTheme.primaryGradient, in: Capsule())
                }
                .buttonStyle(.plain)
                .disabled(busyAction != nil)
                .padding(.top, 12)
            }
        }
    }

    private var autoSyncCard: some View {
        AccountSectionCard {
            VStack(alignment: .leading, spacing: 0) {
                Text("自动同步")
                    .font(.system(size: NekoTypography.web(10), weight: .medium))
                    .tracking(3.2)
                    .foregroundStyle(NekoTheme.muted)
                Text("登录后，猫咪档案、人格和心声会自动绑定到当前账号。换设备登录时，会优先读取账号里的历史档案。")
                    .font(.system(size: NekoTypography.web(11.5), weight: .regular))
                    .foregroundStyle(NekoTheme.ink.opacity(0.75))
                    .lineSpacing(4)
                    .padding(.top, 9)
            }
        }
    }

    private var clippedDisplayName: Binding<String> {
        Binding(
            get: { displayName },
            set: { displayName = String($0.prefix(40)) }
        )
    }

    @MainActor
    private func reload() async {
        guard appModel.session != nil else {
            busyAction = nil
            return
        }
        busyAction = "load"
        do {
            let next = try await appModel.loadAccountSummary()
            summary = next
            displayName = next.profile.displayName ?? ""
        } catch {
            appModel.errorMessage = "账号信息加载失败"
        }
        busyAction = nil
    }

    private func runAccountAction(_ action: String, task: @escaping () async throws -> Void) {
        guard busyAction == nil else { return }
        busyAction = action
        Task {
            do {
                try await task()
            } catch {
                appModel.errorMessage = NekoUserFacingError.message(
                    for: error,
                    fallback: "账号操作失败，请稍后再试。"
                )
            }
            busyAction = nil
        }
    }
}

private struct AccountTopBar: View {
    let title: String
    let back: () -> Void

    var body: some View {
        HStack {
            AppBackCircleButton(action: back)
            Spacer()
            Text(title)
                .font(.system(size: NekoTypography.web(13), weight: .medium))
                .foregroundStyle(NekoTheme.ink)
            Spacer()
            Color.clear.frame(width: 36, height: 36)
        }
    }
}

private struct AccountNeedLoginView: View {
    var body: some View {
        VStack(spacing: 10) {
            Text("需要先登录")
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(NekoTheme.ink)
            Text("登录后才能管理账号数据。")
                .font(.system(size: NekoTypography.web(12), weight: .regular))
                .foregroundStyle(NekoTheme.muted)
        }
        .frame(maxWidth: .infinity)
        .padding(22)
        .background(Color.white.opacity(0.85), in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .shadow(color: NekoTheme.soulViolet.opacity(0.15), radius: 24, x: 0, y: 10)
        .padding(28)
    }
}

private struct AccountStatCard: View {
    let label: String
    let value: Int

    var body: some View {
        VStack(spacing: 2) {
            Text("\(value)")
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(NekoTheme.ink)
            Text(label)
                .font(.system(size: NekoTypography.web(10), weight: .medium))
                .tracking(2)
                .foregroundStyle(NekoTheme.muted)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(Color.white.opacity(0.70), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

private struct AccountSectionCard<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        content
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.white.opacity(0.80), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(Color.white.opacity(0.70), lineWidth: 1)
            }
            .shadow(color: NekoTheme.soulViolet.opacity(0.13), radius: 22, x: 0, y: 10)
    }
}

private struct EditProfileView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appModel: NekoAppModel
    @State private var name = ""
    @State private var gender: CatGender = .male
    @State private var ageStage: CatAgeStage = .young
    @State private var avatarImageData: Data?
    @State private var selectedAvatarItem: PhotosPickerItem?
    @State private var didHydrate = false
    @State private var busyAction: String?

    private var avatarPreview: UIImage? {
        avatarImageData.flatMap(UIImage.init(data:))
    }

    var body: some View {
        ZStack {
            NekoBackground()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    AccountTopBar(title: "修改人格档案") {
                        dismiss()
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 52)

                    avatarEditor
                        .padding(.top, 22)

                    VStack(spacing: 10) {
                        EditFieldRow(label: "猫咪昵称", text: clippedName)
                        EditChoiceRow(label: "性别", options: CatGender.allCases.map(\.rawValue), value: gender.rawValue) { value in
                            if let next = CatGender(rawValue: value) { gender = next }
                        }
                        EditChoiceRow(label: "年龄阶段", options: CatAgeStage.allCases.map(\.rawValue), value: ageStage.rawValue, compact: true) { value in
                            if let next = CatAgeStage(rawValue: value) { ageStage = next }
                        }
                        personaLockCard
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 20)

                    HStack(spacing: 10) {
                        Button {
                            saveProfile(restart: false)
                        } label: {
                            Text(busyAction == "save" ? "保存中" : "保存修改")
                                .font(.system(size: NekoTypography.web(12.5), weight: .regular))
                                .foregroundStyle(NekoTheme.ink)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(Color.white.opacity(0.85), in: Capsule())
                                .shadow(color: NekoTheme.soulViolet.opacity(0.12), radius: 18, x: 0, y: 8)
                        }
                        .buttonStyle(.plain)
                        .disabled(busyAction != nil)

                        Button {
                            saveProfile(restart: true)
                        } label: {
                            Text(busyAction == "restart" ? "保存中" : "保存并重新测试")
                                .font(.system(size: NekoTypography.web(12.5), weight: .medium))
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(NekoTheme.primaryGradient, in: Capsule())
                                .shadow(color: NekoTheme.soulViolet.opacity(0.20), radius: 18, x: 0, y: 9)
                        }
                        .buttonStyle(.plain)
                        .disabled(busyAction != nil)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 24)
                    .padding(.bottom, 34)
                }
            }
        }
        .navigationBarBackButtonHidden(true)
        .nekoEdgeSwipeBack(isEnabled: busyAction == nil) {
            dismiss()
        }
        .onAppear {
            hydrateFromProfile()
        }
        .onChange(of: appModel.catProfile) { _, _ in hydrateFromProfile(force: true) }
        .onChange(of: selectedAvatarItem) { _, item in
            Task { await loadAvatar(from: item) }
        }
    }

    @MainActor
    private var avatarEditor: some View {
        VStack(spacing: 12) {
            PhotosPicker(selection: $selectedAvatarItem, matching: .images) {
                ZStack(alignment: .bottomTrailing) {
                    CatAvatarView(localImage: avatarPreview, remoteURL: appModel.catProfile?.avatarURL, objectKey: appModel.catProfile?.avatarObjectKey, size: 92)

                    Image(systemName: "pencil")
                        .font(.system(size: NekoTypography.web(11), weight: .semibold))
                        .foregroundStyle(NekoTheme.menuIcon)
                        .frame(width: 28, height: 28)
                        .background(Color.white.opacity(0.94), in: Circle())
                        .shadow(color: NekoTheme.soulViolet.opacity(0.16), radius: 12, x: 0, y: 5)
                        .offset(x: 1, y: 1)
                }
            }
            .buttonStyle(.plain)

            PhotosPicker(selection: $selectedAvatarItem, matching: .images) {
                Text("更换照片 · ≤ 10MB")
                    .font(.system(size: NekoTypography.web(11.5), weight: .medium))
                    .tracking(2.3)
                    .foregroundStyle(NekoTheme.menuIcon)
            }
            .buttonStyle(.plain)
        }
    }

    private var personaLockCard: some View {
        EditCard {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("人格类型")
                        .font(.system(size: NekoTypography.web(11), weight: .medium))
                        .tracking(2)
                        .foregroundStyle(NekoTheme.muted)
                    Spacer()
                    Text("不可编辑")
                        .font(.system(size: NekoTypography.web(10), weight: .medium))
                        .tracking(1.5)
                        .foregroundStyle(NekoTheme.muted)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color(red: 0.978, green: 0.946, blue: 0.986), in: Capsule())
                }

                HStack(spacing: 10) {
                    Text(appModel.persona?.type ?? "高冷观察者")
                        .font(.system(size: NekoTypography.web(15), weight: .medium))
                        .foregroundStyle(NekoTheme.ink)
                    Text(appModel.persona?.mbti ?? "INTJ-A")
                        .font(.system(size: NekoTypography.web(10), weight: .medium))
                        .tracking(1.5)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(NekoTheme.primaryGradient, in: Capsule())
                }
                .padding(.top, 9)

                Text("基于上传的资料生成 · 重新测试可更新")
                    .font(.system(size: NekoTypography.web(11), weight: .regular))
                    .foregroundStyle(NekoTheme.muted)
                    .lineSpacing(3)
                    .padding(.top, 7)
            }
        }
    }

    private var clippedName: Binding<String> {
        Binding(
            get: { name },
            set: { name = String($0.prefix(12)) }
        )
    }

    private func hydrateFromProfile(force: Bool = false) {
        guard force || !didHydrate else { return }
        guard let profile = appModel.catProfile else { return }
        name = profile.name
        gender = profile.gender
        ageStage = profile.ageStage
        didHydrate = true
    }

    @MainActor
    private func loadAvatar(from item: PhotosPickerItem?) async {
        guard let item else { return }
        defer { selectedAvatarItem = nil }

        do {
            guard let data = try await item.loadTransferable(type: Data.self) else {
                throw NekoMediaError.unsupportedImage
            }
            guard data.count <= AppConfig.maxAvatarImageBytes else {
                throw NekoMediaError.imageTooLarge
            }
            avatarImageData = data
            appModel.noticeMessage = "照片已更新"
        } catch {
            appModel.errorMessage = NekoUserFacingError.message(
                for: error,
                fallback: "照片读取失败，请换一张照片再试。"
            )
        }
    }

    private func saveProfile(restart: Bool) {
        guard busyAction == nil else { return }
        busyAction = restart ? "restart" : "save"
        Task {
            do {
                if restart {
                    try await appModel.saveProfileAndRestartOnboarding(
                        name: name,
                        gender: gender,
                        ageStage: ageStage,
                        avatarImageData: avatarImageData
                    )
                } else {
                    try await appModel.updateCatProfileDetails(
                        name: name,
                        gender: gender,
                        ageStage: ageStage,
                        avatarImageData: avatarImageData
                    )
                    appModel.noticeMessage = "已保存修改"
                    dismiss()
                }
            } catch {
                appModel.errorMessage = NekoUserFacingError.message(
                    for: error,
                    fallback: "保存失败，请稍后再试。"
                )
            }
            busyAction = nil
        }
    }
}

private struct EditCard<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        content
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.white.opacity(0.75), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(Color.white.opacity(0.70), lineWidth: 1)
            }
            .shadow(color: NekoTheme.soulViolet.opacity(0.13), radius: 22, x: 0, y: 10)
    }
}

private struct EditFieldRow: View {
    let label: String
    @Binding var text: String

    var body: some View {
        EditCard {
            VStack(alignment: .leading, spacing: 7) {
                Text(label)
                    .font(.system(size: NekoTypography.web(11), weight: .medium))
                    .tracking(2)
                    .foregroundStyle(NekoTheme.muted)
                HStack {
                    TextField("", text: $text)
                        .font(.system(size: NekoTypography.web(13), weight: .regular))
                        .foregroundStyle(NekoTheme.ink)
                    Image(systemName: "pencil")
                        .font(.system(size: NekoTypography.web(12), weight: .regular))
                        .foregroundStyle(NekoTheme.muted)
                }
            }
        }
    }
}

private struct EditChoiceRow: View {
    let label: String
    let options: [String]
    let value: String
    var compact = false
    let onChange: (String) -> Void

    var body: some View {
        EditCard {
            VStack(alignment: .leading, spacing: 10) {
                Text(label)
                    .font(.system(size: NekoTypography.web(11), weight: .medium))
                    .tracking(2)
                    .foregroundStyle(NekoTheme.muted)

                HStack(spacing: 6) {
                    ForEach(options, id: \.self) { option in
                        Button {
                            onChange(option)
                        } label: {
                            Text(option)
                                .font(.system(size: compact ? 11.2 : 12, weight: .regular))
                                .lineLimit(1)
                                .minimumScaleFactor(0.80)
                                .foregroundStyle(option == value ? Color.white : NekoTheme.menuIcon)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                                .background(
                                    option == value
                                        ? AnyShapeStyle(NekoTheme.primaryGradient)
                                        : AnyShapeStyle(Color(red: 0.978, green: 0.946, blue: 0.986)),
                                    in: Capsule()
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }
}

private struct ManageVoicesView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appModel: NekoAppModel
    @Binding var isPublishSheetPresented: Bool
    @State private var isLoading = false
    @State private var editMode = false
    @State private var selectedIDs: Set<String> = []
    @State private var confirmDelete = false
    @State private var selectedVoice: CatVoiceResult?
    @State private var isVoiceDetailPresented = false

    private var voices: [CatVoiceResult] {
        appModel.voices
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            NekoBackground()

            VStack(spacing: 0) {
                manageHeader
                    .padding(.horizontal, 24)
                    .padding(.top, 52)

                if isLoading && voices.isEmpty {
                    Spacer()
                    ProgressView()
                        .tint(NekoTheme.soulViolet)
                    Text("正在读取猫咪心声…")
                        .font(.system(size: NekoTypography.web(12), weight: .regular))
                        .foregroundStyle(NekoTheme.muted)
                        .padding(.top, 10)
                    Spacer()
                } else if voices.isEmpty {
                    ManageVoicesEmptyState {
                        isPublishSheetPresented = true
                    }
                    .padding(.horizontal, 32)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView(showsIndicators: false) {
                        HStack(alignment: .top, spacing: 12) {
                            ForEach(0..<2, id: \.self) { column in
                                VStack(spacing: 12) {
                                    ForEach(columnVoices(column), id: \.id) { voice in
                                        ManageVoiceCard(
                                            voice: voice,
                                            profile: appModel.catProfile,
                                            editMode: editMode,
                                            selected: selectedIDs.contains(selectionID(for: voice))
                                        ) {
                                            if editMode {
                                                toggle(voice)
                                            } else {
                                                selectedVoice = voice
                                                isVoiceDetailPresented = true
                                            }
                                        }
                                    }
                                }
                                .frame(maxWidth: .infinity)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 16)
                        .padding(.bottom, editMode ? 110 : 28)
                    }
                }
            }
            .padding(.bottom, editMode ? 0 : 16)

            if editMode {
                deleteActionBar
            }

            if confirmDelete {
                ConfirmSheetOverlay(
                    title: "确定删除 \(selectedIDs.count) 条心声吗？",
                    hint: "删除后无法恢复",
                    confirmText: "删除",
                    danger: true,
                    onConfirm: deleteSelected,
                    onCancel: { confirmDelete = false }
                )
            }
        }
        .navigationBarBackButtonHidden(true)
        .nekoEdgeSwipeBack {
            if confirmDelete {
                confirmDelete = false
            } else if editMode {
                exitEditMode()
            } else {
                dismiss()
            }
        }
        .task {
            await refreshVoices()
        }
        .navigationDestination(isPresented: $isVoiceDetailPresented) {
            if let selectedVoice {
                VoiceDetailView(
                    voice: selectedVoice,
                    profile: appModel.catProfile,
                    persona: appModel.persona
                )
                .environmentObject(appModel)
            } else {
                ManageVoicesEmptyState {
                    isPublishSheetPresented = true
                }
                .padding(24)
                .background { NekoBackground() }
            }
        }
    }

    private var manageHeader: some View {
        HStack {
            if editMode {
                Button("取消") {
                    exitEditMode()
                }
                .font(.system(size: NekoTypography.web(11.5), weight: .regular))
                .foregroundStyle(NekoTheme.menuIcon)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(Color.white.opacity(0.80), in: Capsule())
                .shadow(color: NekoTheme.soulViolet.opacity(0.13), radius: 14, x: 0, y: 6)
                .buttonStyle(.plain)
            } else {
                AppBackCircleButton {
                    dismiss()
                }
            }

            Spacer()

            Text(editMode ? "已选 \(selectedIDs.count) 条" : "猫咪心声")
                .font(.system(size: NekoTypography.web(13), weight: .medium))
                .foregroundStyle(NekoTheme.ink)

            Spacer()

            if !voices.isEmpty && !editMode {
                Button("编辑") {
                    editMode = true
                }
                .font(.system(size: NekoTypography.web(11.5), weight: .regular))
                .foregroundStyle(NekoTheme.menuIcon)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(Color.white.opacity(0.80), in: Capsule())
                .shadow(color: NekoTheme.soulViolet.opacity(0.13), radius: 14, x: 0, y: 6)
                .buttonStyle(.plain)
            } else {
                Color.clear.frame(width: 52, height: 36)
            }
        }
    }

    private var deleteActionBar: some View {
        VStack {
            Spacer()
            Button {
                if selectedIDs.isEmpty {
                    appModel.noticeMessage = "先选择要删除的心声哦"
                } else {
                    confirmDelete = true
                }
            } label: {
                Text("删除所选 (\(selectedIDs.count))")
                    .font(.system(size: NekoTypography.web(13), weight: .medium))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .background(
                        LinearGradient(
                            colors: [Color(red: 0.92, green: 0.43, blue: 0.36), Color(red: 0.91, green: 0.50, blue: 0.62)],
                            startPoint: .leading,
                            endPoint: .trailing
                        ),
                        in: Capsule()
                    )
            }
            .opacity(selectedIDs.isEmpty ? 0.50 : 1)
            .buttonStyle(.plain)
            .padding(8)
            .background(Color.white.opacity(0.90), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(Color.white.opacity(0.72), lineWidth: 1)
            }
            .shadow(color: NekoTheme.soulViolet.opacity(0.16), radius: 24, x: 0, y: 10)
            .padding(.horizontal, 16)
            .padding(.bottom, 20)
        }
        .allowsHitTesting(true)
    }

    private func columnVoices(_ column: Int) -> [CatVoiceResult] {
        voices.enumerated()
            .filter { $0.offset % 2 == column }
            .map(\.element)
    }

    private func selectionID(for voice: CatVoiceResult) -> String {
        voice.cloudId ?? voice.id
    }

    private func toggle(_ voice: CatVoiceResult) {
        let id = selectionID(for: voice)
        if selectedIDs.contains(id) {
            selectedIDs.remove(id)
        } else {
            selectedIDs.insert(id)
        }
    }

    private func exitEditMode() {
        editMode = false
        selectedIDs.removeAll()
    }

    @MainActor
    private func refreshVoices() async {
        guard !isLoading else { return }
        isLoading = true
        do {
            _ = try await appModel.reloadVoices()
        } catch {
            appModel.errorMessage = "猫咪心声加载失败"
        }
        isLoading = false
    }

    private func deleteSelected() {
        let ids = Array(selectedIDs)
        confirmDelete = false
        Task {
            do {
                try await appModel.deleteVoices(ids: ids)
                appModel.noticeMessage = "已删除 \(ids.count) 条心声"
                exitEditMode()
            } catch {
                appModel.errorMessage = NekoUserFacingError.message(
                    for: error,
                    fallback: "删除失败，请稍后再试。"
                )
            }
        }
    }
}

private struct ManageVoicesEmptyState: View {
    let publish: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            ZStack(alignment: .topTrailing) {
                Circle()
                    .fill(NekoTheme.tintGradient)
                    .frame(width: 120, height: 120)
                    .shadow(color: NekoTheme.soulViolet.opacity(0.14), radius: 22, x: 0, y: 10)

                CatAvatarView(localImage: nil, remoteURL: nil, size: 72)
                    .frame(width: 120, height: 120)

                Text("zzz")
                    .font(.system(size: NekoTypography.web(10), weight: .regular))
                    .foregroundStyle(NekoTheme.muted)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.white.opacity(0.90), in: Capsule())
                    .offset(x: 0, y: -3)
            }

            Text("还没有猫咪心声哦")
                .font(.system(size: NekoTypography.web(15), weight: .medium))
                .foregroundStyle(NekoTheme.ink)
                .padding(.top, 24)

            Text("记录一个瞬间，\n让 AI 听懂它的小心思 ✦")
                .font(.system(size: NekoTypography.web(12), weight: .regular))
                .foregroundStyle(NekoTheme.muted)
                .lineSpacing(5)
                .multilineTextAlignment(.center)
                .padding(.top, 8)

            Button {
                publish()
            } label: {
                Text("发布第一条心声")
                    .font(.system(size: NekoTypography.web(12.5), weight: .medium))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 26)
                    .padding(.vertical, 12)
                    .background(NekoTheme.primaryGradient, in: Capsule())
                    .shadow(color: NekoTheme.soulViolet.opacity(0.22), radius: 18, x: 0, y: 9)
            }
            .buttonStyle(.plain)
            .padding(.top, 24)

            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}

private struct ManageVoiceCard: View {
    let voice: CatVoiceResult
    let profile: CatProfile?
    let editMode: Bool
    let selected: Bool
    let action: () -> Void

    private var mediaHeight: CGFloat {
        VoiceMediaMetrics.manageHeight(for: voice.aspect)
    }

    var body: some View {
        Button(action: action) {
            VStack(spacing: 0) {
                GeometryReader { proxy in
                    ZStack(alignment: .bottomLeading) {
                        NekoTheme.photoPlaceholderGradient

                        if voice.mediaType == "video" {
                            avatarFallback
                                .frame(width: proxy.size.width, height: proxy.size.height)
                                .overlay {
                                    Image(systemName: "play.circle.fill")
                                        .font(.system(size: 30, weight: .regular))
                                        .foregroundStyle(.white.opacity(0.94), NekoTheme.soulViolet.opacity(0.68))
                                }
                        } else {
                            NekoRemoteImageView(
                                remoteURL: voice.mediaURL,
                                objectKey: voice.mediaObjectKey,
                                contentMode: .fill
                            ) {
                                VoiceMediaSkeletonView()
                                    .frame(width: proxy.size.width, height: proxy.size.height)
                            }
                            .frame(width: proxy.size.width, height: proxy.size.height)
                            .clipped()
                        }

                        LinearGradient(
                            colors: [.clear, .black.opacity(0.15), .black.opacity(0.42)],
                            startPoint: .top,
                            endPoint: .bottom
                        )

                        Text("💭 \(voice.text)")
                            .font(.system(size: NekoTypography.web(12), weight: .regular))
                            .foregroundStyle(.white)
                            .lineLimit(2)
                            .lineSpacing(3)
                            .shadow(color: .black.opacity(0.35), radius: 6, x: 0, y: 1)
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        if editMode {
                            selectionBadge
                                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                                .padding(10)
                        }
                    }
                }
                .frame(height: mediaHeight)
                .frame(maxWidth: .infinity)
                .clipped()

                Text(voice.time)
                    .font(.system(size: NekoTypography.web(10.5), weight: .regular))
                    .foregroundStyle(Color(red: 0.604, green: 0.569, blue: 0.682))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
            }
            .background(Color.white.opacity(0.85), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(selected ? NekoTheme.soulViolet.opacity(0.78) : Color.white.opacity(0.70), lineWidth: selected ? 1.5 : 1)
            }
            .shadow(color: NekoTheme.soulViolet.opacity(selected ? 0.20 : 0.11), radius: 18, x: 0, y: 8)
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
    }

    private var avatarFallback: some View {
        ZStack {
            NekoTheme.photoPlaceholderGradient
            CatAvatarView(localImage: nil, remoteURL: profile?.avatarURL, objectKey: profile?.avatarObjectKey, size: 64)
        }
    }

    private var selectionBadge: some View {
        ZStack {
            Circle()
                .fill(selected ? AnyShapeStyle(NekoTheme.primaryGradient) : AnyShapeStyle(Color.black.opacity(0.15)))
                .overlay {
                    Circle()
                        .stroke(Color.white.opacity(0.70), lineWidth: selected ? 0 : 1)
                }
            Text("✓")
                .font(.system(size: NekoTypography.web(11), weight: .bold))
                .foregroundStyle(selected ? Color.white : Color.clear)
        }
        .frame(width: 24, height: 24)
        .shadow(color: NekoTheme.soulViolet.opacity(selected ? 0.20 : 0), radius: 8, x: 0, y: 4)
    }
}

private struct ConfirmSheetOverlay: View {
    let title: String
    let hint: String
    let confirmText: String
    let danger: Bool
    let onConfirm: () -> Void
    let onCancel: () -> Void

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.black.opacity(0.35)
                .ignoresSafeArea()
                .onTapGesture(perform: onCancel)

            VStack(spacing: 0) {
                Capsule()
                    .fill(NekoTheme.muted.opacity(0.35))
                    .frame(width: 40, height: 4)
                    .padding(.top, 10)

                Text(title)
                    .font(.system(size: NekoTypography.web(15), weight: .medium))
                    .foregroundStyle(NekoTheme.ink)
                    .padding(.top, 18)

                if !hint.isEmpty {
                    Text(hint)
                        .font(.system(size: NekoTypography.web(12), weight: .regular))
                        .foregroundStyle(NekoTheme.muted)
                        .padding(.top, 6)
                }

                HStack(spacing: 10) {
                    Button("取消", action: onCancel)
                        .font(.system(size: NekoTypography.web(13), weight: .medium))
                        .foregroundStyle(NekoTheme.ink)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Color(red: 0.968, green: 0.944, blue: 0.982), in: Capsule())

                    Button(confirmText, action: onConfirm)
                        .font(.system(size: NekoTypography.web(13), weight: .medium))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(
                            danger
                                ? AnyShapeStyle(LinearGradient(colors: [Color(red: 0.92, green: 0.43, blue: 0.36), Color(red: 0.91, green: 0.50, blue: 0.62)], startPoint: .leading, endPoint: .trailing))
                                : AnyShapeStyle(NekoTheme.primaryGradient),
                            in: Capsule()
                        )
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 24)
                .padding(.top, 18)
                .padding(.bottom, 24)
            }
            .frame(maxWidth: .infinity)
            .background(Color.white.opacity(0.95), in: UnevenRoundedRectangle(topLeadingRadius: 28, topTrailingRadius: 28, style: .continuous))
            .shadow(color: NekoTheme.ink.opacity(0.12), radius: 24, x: 0, y: -6)
        }
        .transition(.opacity.combined(with: .move(edge: .bottom)))
    }
}

private extension String {
    var nonEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

private struct PersonaDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appModel: NekoAppModel

    let profile: CatProfile
    let persona: CatPersonaResult?

    private var safePersona: CatPersonaResult {
        if let persona {
            return persona
        }
        return PersonaGenerator.generate(
            profile: CatProfileDraft(name: profile.name, gender: profile.gender, ageStage: profile.ageStage),
            quizAnswers: [:],
            videoCount: 0,
            hasAvatar: profile.avatarURL != nil || profile.avatarObjectKey != nil
        )
    }

    private var displayTags: [String] {
        let fallback = ["高冷外表", "内心温柔", "观察大师", "独立自主", "慢热型选手", "安全第一"]
        return safePersona.tags.isEmpty ? fallback : safePersona.tags
    }

    private var displayTraits: [PersonaTraitDisplay] {
        let fallback = [
            PersonaTrait(label: "粘人度", value: 68),
            PersonaTrait(label: "独立性", value: 90),
            PersonaTrait(label: "好奇心", value: 82),
        ]
        let icons = ["🐾", "🏠", "🔍"]
        var traits = Array((safePersona.traits.isEmpty ? fallback : safePersona.traits).prefix(3))
        while traits.count < 3 {
            traits.append(fallback[traits.count])
        }
        return traits.enumerated().map { index, trait in
            PersonaTraitDisplay(icon: icons[index], label: trait.label, value: trait.value)
        }
    }

    private var displayObservations: [PersonaObservation] {
        let fallback = [
            PersonaObservation(label: "主动观察陌生事物", value: "12 次"),
            PersonaObservation(label: "主动靠近主人", value: "8 次"),
            PersonaObservation(label: "独处行为", value: "23 次"),
            PersonaObservation(label: "守门行为", value: "5 次"),
        ]
        return Array((safePersona.observations.isEmpty ? fallback : safePersona.observations).prefix(4))
    }

    var body: some View {
        LovablePersonaResultPage(
            catName: profile.name,
            avatarImage: nil,
            avatarURL: profile.avatarURL,
            avatarObjectKey: profile.avatarObjectKey,
            persona: safePersona,
            onBack: { dismiss() },
            onRestart: {
                dismiss()
                appModel.startOnboarding()
            },
            onSave: { dismiss() }
        )
        .nekoEdgeSwipeBack {
            dismiss()
        }
    }
}

private struct PersonaTopBar: View {
    let onBack: () -> Void
    let onShare: () -> Void

    var body: some View {
        HStack {
            HStack(spacing: 12) {
                Button(action: onBack) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: NekoTypography.web(16), weight: .semibold))
                        .foregroundStyle(Color(red: 0.56, green: 0.32, blue: 0.62))
                        .frame(width: 36, height: 36)
                        .background(Color.white.opacity(0.80), in: Circle())
                        .shadow(color: NekoTheme.soulViolet.opacity(0.14), radius: 14, x: 0, y: 7)
                }
                .buttonStyle(.plain)

                Text("N E K O · I D")
                    .font(.system(size: NekoTypography.web(10), weight: .regular))
                    .tracking(5)
                    .foregroundStyle(Color(red: 0.56, green: 0.36, blue: 0.62))
            }

            Spacer()

            Button(action: onShare) {
                ShareNodesIcon()
                    .frame(width: 19, height: 19)
                    .frame(width: 40, height: 40)
                    .background(
                        LinearGradient(
                            colors: [
                                Color(red: 0.714, green: 0.604, blue: 0.937),
                                Color(red: 0.902, green: 0.722, blue: 0.812),
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        in: Circle()
                    )
                    .shadow(color: NekoTheme.soulViolet.opacity(0.30), radius: 18, x: 0, y: 10)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 24)
        .padding(.top, 50)
    }
}

private struct PersonaHeroCard: View {
    let profile: CatProfile
    let persona: CatPersonaResult

    private var heroTags: [String] {
        let fallback = ["高冷外表", "内心温柔", "观察大师", "独立自主"]
        return persona.tags.isEmpty ? fallback : persona.tags
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Circle()
                .fill(NekoTheme.soulPink.opacity(0.26))
                .frame(width: 180, height: 180)
                .blur(radius: 34)
                .offset(x: -160, y: -12)

            HStack(spacing: 16) {
                PersonaOrbitAvatar(profile: profile)

                VStack(alignment: .leading, spacing: 0) {
                    Text(profile.name)
                        .font(.system(size: NekoTypography.web(15), weight: .light))
                        .tracking(0.4)
                        .foregroundStyle(NekoTheme.muted)
                        .lineLimit(1)

                    Text(persona.type)
                        .font(.system(size: 22, weight: .medium))
                        .foregroundStyle(NekoTheme.primaryGradient)
                        .lineLimit(2)
                        .minimumScaleFactor(0.82)
                        .padding(.top, 6)

                    HStack(spacing: 6) {
                        Text("MBTI")
                            .font(.system(size: NekoTypography.web(9), weight: .regular))
                            .tracking(3)
                            .foregroundStyle(NekoTheme.muted)
                        Text(persona.mbti)
                            .font(.system(size: NekoTypography.web(11.5), weight: .medium))
                            .tracking(0.9)
                            .foregroundStyle(NekoTheme.ink)
                    }
                    .padding(.top, 6)

                    FlexibleChipRow(items: Array(heroTags.prefix(4)))
                        .padding(.top, 8)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.trailing, 4)

                Spacer(minLength: 0)
            }
            .padding(16)

            HStack(spacing: 4) {
                Text("人格匹配度")
                    .foregroundStyle(NekoTheme.muted)
                Text("\(persona.matchScore)%")
                    .fontWeight(.semibold)
            }
            .font(.system(size: NekoTypography.web(9.5), weight: .regular))
            .tracking(0.5)
            .foregroundStyle(NekoTheme.ink)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(Color.white.opacity(0.80), in: Capsule())
            .overlay {
                Capsule()
                    .stroke(NekoTheme.softPink.opacity(0.55), lineWidth: 1)
            }
            .shadow(color: NekoTheme.soulViolet.opacity(0.12), radius: 10, x: 0, y: 4)
            .padding(.top, 12)
            .padding(.trailing, 12)
        }
        .frame(maxWidth: .infinity, minHeight: 150)
        .background(
            LinearGradient(
                colors: [
                    Color.white.opacity(0.92),
                    Color(red: 0.975, green: 0.930, blue: 0.980).opacity(0.82),
                    Color(red: 0.950, green: 0.930, blue: 0.995).opacity(0.75),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 26, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .stroke(Color.white.opacity(0.70), lineWidth: 1)
        }
        .shadow(color: NekoTheme.soulViolet.opacity(0.14), radius: 24, x: 0, y: 12)
        .padding(.horizontal, 20)
        .padding(.top, 16)
    }
}

private struct PersonaSection<Content: View>: View {
    let title: String
    let hint: String
    let tone: Bool
    let actionTitle: String?
    let action: (() -> Void)?
    let content: Content

    init(
        title: String,
        hint: String,
        tone: Bool = false,
        actionTitle: String? = nil,
        action: (() -> Void)? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.hint = hint
        self.tone = tone
        self.actionTitle = actionTitle
        self.action = action
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Text(title)
                    .font(.system(size: NekoTypography.web(13), weight: .medium))
                    .foregroundStyle(NekoTheme.ink)

                Text(hint)
                    .font(.system(size: NekoTypography.web(8), weight: .regular))
                    .tracking(2.4)
                    .foregroundStyle(Color(red: 0.60, green: 0.40, blue: 0.64))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: 8)

                if let actionTitle {
                    Button(actionTitle) {
                        action?()
                    }
                    .font(.system(size: NekoTypography.web(10), weight: .regular))
                    .tracking(0.8)
                    .foregroundStyle(Color(red: 0.50, green: 0.30, blue: 0.58))
                    .buttonStyle(.plain)
                }
            }

            content
        }
        .padding(16)
        .background(sectionBackground, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Color.white.opacity(tone ? 0.60 : 0.70), lineWidth: 1)
        }
        .shadow(color: NekoTheme.soulViolet.opacity(tone ? 0.12 : 0.10), radius: 18, x: 0, y: 10)
        .padding(.horizontal, 20)
        .padding(.top, 12)
    }

    private var sectionBackground: some ShapeStyle {
        if tone {
            return AnyShapeStyle(
                LinearGradient(
                    colors: [
                        Color(red: 0.985, green: 0.930, blue: 0.980).opacity(0.96),
                        Color(red: 0.955, green: 0.930, blue: 0.995).opacity(0.90),
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
        }

        return AnyShapeStyle(
            LinearGradient(
                colors: [
                    Color.white.opacity(0.88),
                    Color(red: 0.985, green: 0.955, blue: 0.985).opacity(0.70),
                ],
                startPoint: .top,
                endPoint: .bottomTrailing
            )
        )
    }
}

private struct PersonaTraitDisplay: Identifiable {
    var id: String { label }
    let icon: String
    let label: String
    let value: Int
}

private struct PersonaTraitRing: View {
    let trait: PersonaTraitDisplay

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                Circle()
                    .stroke(Color(red: 0.934, green: 0.902, blue: 0.972), lineWidth: 8)

                Circle()
                    .trim(from: 0, to: CGFloat(min(max(trait.value, 0), 100)) / 100)
                    .stroke(NekoTheme.primaryGradient, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                    .rotationEffect(.degrees(-90))

                VStack(spacing: 0) {
                    Text("\(trait.value)%")
                        .font(.system(size: NekoTypography.web(15), weight: .semibold))
                        .foregroundStyle(NekoTheme.ink)
                        .tracking(-0.5)

                    Text(trait.icon)
                        .font(.system(size: NekoTypography.web(11)))
                }
            }
            .frame(width: 72, height: 72)

            Text(trait.label)
                .font(.system(size: NekoTypography.web(11), weight: .regular))
                .foregroundStyle(NekoTheme.ink.opacity(0.82))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct PersonaOrbitAvatar: View {
    let profile: CatProfile

    var body: some View {
        ZStack {
            Circle()
                .stroke(NekoTheme.softPink.opacity(0.72), lineWidth: 1)
            Circle()
                .stroke(NekoTheme.softLilac.opacity(0.72), lineWidth: 1)
                .padding(8)
            CatAvatarView(localImage: nil, remoteURL: profile.avatarURL, objectKey: profile.avatarObjectKey, size: 100)
                .padding(6)
                .background(Color.white.opacity(0.94), in: Circle())
                .shadow(color: NekoTheme.soulViolet.opacity(0.18), radius: 18, x: 0, y: 10)
        }
        .frame(width: 112, height: 112)
    }
}

private struct FlexibleChipRow: View {
    let items: [String]

    var body: some View {
        if items.isEmpty {
            EmptyView()
        } else {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 58), spacing: 6)], alignment: .leading, spacing: 6) {
                ForEach(items, id: \.self) { item in
                    Text(item)
                        .font(.system(size: NekoTypography.web(9.5), weight: .regular))
                        .tracking(0.8)
                        .foregroundStyle(Color(red: 0.50, green: 0.32, blue: 0.58))
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.white.opacity(0.80), in: Capsule())
                        .overlay {
                            Capsule()
                                .stroke(NekoTheme.softPink.opacity(0.55), lineWidth: 1)
                        }
                }
            }
        }
    }
}

private struct FlowChipWrap: View {
    let items: [String]

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 84), spacing: 8)], alignment: .leading, spacing: 8) {
            ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                Text(item)
                    .font(.system(size: NekoTypography.web(11), weight: .regular))
                    .tracking(0.5)
                    .foregroundStyle(index.isMultiple(of: 2) ? Color(red: 0.48, green: 0.30, blue: 0.56) : .white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                        Group {
                            if index.isMultiple(of: 2) {
                                Capsule()
                                    .fill(Color.white.opacity(0.85))
                            } else {
                                Capsule()
                                    .fill(NekoTheme.selectedGradient)
                            }
                        }
                    )
                    .overlay {
                        Capsule()
                            .stroke(index.isMultiple(of: 2) ? NekoTheme.softPink.opacity(0.55) : Color.clear, lineWidth: 1)
                    }
                    .shadow(color: index.isMultiple(of: 2) ? .clear : NekoTheme.soulViolet.opacity(0.12), radius: 8, x: 0, y: 5)
            }
        }
    }
}

private struct PersonaBottomActions: View {
    let onRestart: () -> Void
    let onSave: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button("重新识别", action: onRestart)
                .font(.system(size: NekoTypography.web(13), weight: .medium))
                .foregroundStyle(Color(red: 0.50, green: 0.30, blue: 0.58))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 15)
                .background(Color.white.opacity(0.96), in: Capsule())
                .overlay {
                    Capsule()
                        .stroke(Color(red: 0.780, green: 0.702, blue: 0.949), lineWidth: 1.5)
                }
                .shadow(color: NekoTheme.soulViolet.opacity(0.10), radius: 16, x: 0, y: 8)

            Button("保存结果", action: onSave)
                .font(.system(size: NekoTypography.web(13), weight: .medium))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 15)
                .background(NekoTheme.primaryGradient, in: Capsule())
                .shadow(color: NekoTheme.soulViolet.opacity(0.22), radius: 20, x: 0, y: 10)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 20)
        .padding(.top, 18)
        .padding(.bottom, 10)
        .background(
            LinearGradient(
                colors: [
                    NekoTheme.lilacBottom.opacity(0.02),
                    NekoTheme.lilacBottom.opacity(0.82),
                    NekoTheme.lilacBottom.opacity(0.96),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
        )
    }
}

private struct PersonaShareOverlay: View {
    let onClose: () -> Void
    let onWeChat: () -> Void
    let onMoments: () -> Void
    let onSaveImage: () -> Void

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.black.opacity(0.35)
                .ignoresSafeArea()
                .onTapGesture(perform: onClose)

            VStack(spacing: 0) {
                Capsule()
                    .fill(Color(red: 0.91, green: 0.88, blue: 0.93))
                    .frame(width: 40, height: 4)

                Text("分享我的猫人格")
                    .font(.system(size: NekoTypography.web(13), weight: .medium))
                    .foregroundStyle(NekoTheme.ink)
                    .padding(.top, 16)

                HStack(spacing: 0) {
                    PersonaShareItem(label: "微信好友", emoji: "💬", colors: [Color(red: 0.420, green: 0.831, blue: 0.420), Color(red: 0.169, green: 0.722, blue: 0.361)], action: onWeChat)
                    PersonaShareItem(label: "朋友圈", emoji: "🌈", colors: [Color(red: 1.000, green: 0.702, blue: 0.420), Color(red: 1.000, green: 0.420, blue: 0.710)], action: onMoments)
                    PersonaShareItem(label: "保存图片", emoji: "⬇️", colors: [NekoTheme.soulViolet, NekoTheme.soulPink], action: onSaveImage)
                }
                .padding(.top, 20)

                Button("取消", action: onClose)
                    .font(.system(size: NekoTypography.web(13), weight: .medium))
                    .foregroundStyle(Color(red: 0.45, green: 0.31, blue: 0.52))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .background(Color(red: 0.965, green: 0.935, blue: 0.975), in: Capsule())
                    .padding(.top, 18)
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 28)
            .background(Color.white.opacity(0.95), in: UnevenRoundedRectangle(topLeadingRadius: 28, topTrailingRadius: 28, style: .continuous))
            .shadow(color: Color.black.opacity(0.16), radius: 28, x: 0, y: -12)
        }
    }
}

private struct PersonaShareItem: View {
    let label: String
    let emoji: String
    let colors: [Color]
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Text(emoji)
                    .font(.system(size: 22))
                    .frame(width: 48, height: 48)
                    .background(
                        LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing),
                        in: Circle()
                    )
                    .shadow(color: Color.black.opacity(0.12), radius: 12, x: 0, y: 8)

                Text(label)
                    .font(.system(size: NekoTypography.web(11.5), weight: .regular))
                    .foregroundStyle(NekoTheme.ink.opacity(0.80))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
    }
}

private struct ShareNodesIcon: View {
    var body: some View {
        Canvas { context, size in
            let points = [
                CGPoint(x: size.width * 0.30, y: size.height * 0.50),
                CGPoint(x: size.width * 0.72, y: size.height * 0.24),
                CGPoint(x: size.width * 0.72, y: size.height * 0.76),
            ]
            var path = Path()
            path.move(to: points[0])
            path.addLine(to: points[1])
            path.move(to: points[0])
            path.addLine(to: points[2])
            context.stroke(path, with: .color(.white), style: StrokeStyle(lineWidth: 2.2, lineCap: .round))

            for point in points {
                let rect = CGRect(x: point.x - 3.2, y: point.y - 3.2, width: 6.4, height: 6.4)
                context.stroke(Path(ellipseIn: rect), with: .color(.white), lineWidth: 2.2)
            }
        }
    }
}

private struct NekoTabSymbol: View {
    enum Kind {
        case voice
        case cat
    }

    let kind: Kind
    let active: Bool

    var body: some View {
        Canvas { context, size in
            let color = active ? NekoTheme.soulViolet : NekoTheme.muted
            let stroke = StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round)

            switch kind {
            case .voice:
                var bubble = Path()
                bubble.move(to: point(4, 11, size))
                bubble.addCurve(
                    to: point(12, 5, size),
                    control1: point(4, 7.4, size),
                    control2: point(7.6, 5, size)
                )
                bubble.addCurve(
                    to: point(20, 11, size),
                    control1: point(16.4, 5, size),
                    control2: point(20, 7.4, size)
                )
                bubble.addCurve(
                    to: point(12, 17, size),
                    control1: point(20, 14.6, size),
                    control2: point(16.4, 17, size)
                )
                bubble.addCurve(
                    to: point(9.7, 16.78, size),
                    control1: point(11.2, 17, size),
                    control2: point(10.4, 16.92, size)
                )
                bubble.addLine(to: point(6.3, 19, size))
                bubble.addCurve(
                    to: point(5.32, 18.4, size),
                    control1: point(5.85, 19.3, size),
                    control2: point(5.25, 18.95, size)
                )
                bubble.addLine(to: point(5.72, 15.55, size))
                bubble.addCurve(
                    to: point(4, 11, size),
                    control1: point(4.65, 14.3, size),
                    control2: point(4, 12.75, size)
                )
                context.stroke(bubble, with: .color(color), style: stroke)

                var sparkle = Path()
                sparkle.move(to: point(12, 10.2, size))
                sparkle.addLine(to: point(12, 12.2, size))
                sparkle.move(to: point(11, 11.2, size))
                sparkle.addLine(to: point(13, 11.2, size))
                context.stroke(sparkle, with: .color(color), style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round))

            case .cat:
                var cat = Path()
                cat.move(to: point(5.5, 9.5, size))
                cat.addLine(to: point(4.2, 4.5, size))
                cat.addCurve(
                    to: point(4.85, 4, size),
                    control1: point(4.1, 4.1, size),
                    control2: point(4.5, 3.8, size)
                )
                cat.addLine(to: point(9, 6.2, size))

                cat.move(to: point(18.5, 9.5, size))
                cat.addLine(to: point(19.8, 4.5, size))
                cat.addCurve(
                    to: point(19.15, 4, size),
                    control1: point(19.9, 4.1, size),
                    control2: point(19.5, 3.8, size)
                )
                cat.addLine(to: point(15, 6.2, size))

                cat.move(to: point(4.8, 12.5, size))
                cat.addCurve(
                    to: point(12, 6, size),
                    control1: point(4.8, 8.6, size),
                    control2: point(8.05, 6, size)
                )
                cat.addCurve(
                    to: point(19.2, 12.5, size),
                    control1: point(15.95, 6, size),
                    control2: point(19.2, 8.6, size)
                )
                cat.addCurve(
                    to: point(12, 19.5, size),
                    control1: point(19.2, 16.6, size),
                    control2: point(16, 19.5, size)
                )
                cat.addCurve(
                    to: point(4.8, 12.5, size),
                    control1: point(8, 19.5, size),
                    control2: point(4.8, 16.6, size)
                )
                context.stroke(cat, with: .color(color), style: stroke)

                var mouth = Path()
                mouth.move(to: point(10.6, 13.6, size))
                mouth.addCurve(
                    to: point(12, 13.7, size),
                    control1: point(11.3, 14.2, size),
                    control2: point(11.6, 14.0, size)
                )
                mouth.addCurve(
                    to: point(13.4, 13.6, size),
                    control1: point(12.4, 14.0, size),
                    control2: point(12.7, 14.2, size)
                )
                context.stroke(mouth, with: .color(color), style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
            }
        }
    }

    private func point(_ x: CGFloat, _ y: CGFloat, _ size: CGSize) -> CGPoint {
        CGPoint(x: size.width * x / 24, y: size.height * y / 24)
    }
}

private struct VoicePublishSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appModel: NekoAppModel
    @Binding var latestPublishedVoice: CatVoiceResult?

    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var photoData: Data?
    @State private var photoPreviewImage: UIImage?
    @State private var scene = ""
    @State private var draftVoice: CatVoiceResult?
    @State private var publishedVoice: CatVoiceResult?
    @State private var step: PublishStep = .upload
    @State private var isAnalyzing = false
    @State private var isPublishing = false
    @State private var errorMessage: String?
    @State private var pendingAnalysisAfterLogin: Bool?

    private var catName: String {
        appModel.catProfile?.name.nonEmpty ?? "猫咪"
    }

    var body: some View {
        ZStack {
            NekoBackground()

            switch step {
            case .upload:
                PublishUploadScreen(
                    selectedPhotoItem: $selectedPhotoItem,
                    photoPreviewImage: photoPreviewImage,
                    profileAvatarURL: appModel.catProfile?.avatarURL,
                    profileAvatarObjectKey: appModel.catProfile?.avatarObjectKey,
                    canContinue: photoData != nil,
                    isDisabled: isAnalyzing || isPublishing,
                    onBack: { dismiss() },
                    onNext: { step = .background }
                )
            case .background:
                PublishBackgroundScreen(
                    scene: sceneBinding,
                    isAnalyzing: isAnalyzing,
                    onBack: { step = .upload },
                    onAnalyze: { Task { await generatePreview() } }
                )
            case .preview:
                PublishPreviewScreen(
                    catName: catName,
                    photoPreviewImage: photoPreviewImage,
                    draftVoice: draftVoice,
                    isLoading: isAnalyzing,
                    isReanalyzing: isAnalyzing,
                    isPublishing: isPublishing,
                    onBack: { step = .background },
                    onReanalyze: { Task { await generatePreview(stayOnPreview: true) } },
                    onPublish: { Task { await publishDraft() } }
                )
            case .success:
                PublishSuccessScreen(
                    catName: catName,
                    photoPreviewImage: photoPreviewImage,
                    voice: publishedVoice ?? draftVoice,
                    onReturnHome: { dismiss() }
                )
            }

            if let loadingText {
                PublishLoadingOverlay(title: loadingText.title, hint: loadingText.hint)
            }
        }
        .nekoToastHost(errorMessage: $errorMessage, noticeMessage: .constant(nil))
        .nekoToastHost(
            errorMessage: $appModel.errorMessage,
            noticeMessage: $appModel.noticeMessage
        )
        .preferredColorScheme(.light)
        .nekoEdgeSwipeBack(isEnabled: !isAnalyzing && !isPublishing) {
            handleEdgeSwipeBack()
        }
        .onChange(of: selectedPhotoItem) { _, item in
            Task { await loadPhoto(from: item) }
        }
        .onChange(of: appModel.session?.accessToken) { _, accessToken in
            guard accessToken != nil, let stayOnPreview = pendingAnalysisAfterLogin else { return }
            pendingAnalysisAfterLogin = nil
            Task { await generatePreview(stayOnPreview: stayOnPreview) }
        }
    }

    @MainActor
    private func handleEdgeSwipeBack() {
        if errorMessage != nil {
            errorMessage = nil
            return
        }

        switch step {
        case .upload:
            dismiss()
        case .background:
            step = .upload
        case .preview:
            step = .background
        case .success:
            dismiss()
        }
    }

    @MainActor
    private func loadPhoto(from item: PhotosPickerItem?) async {
        guard let item else { return }
        defer { selectedPhotoItem = nil }

        do {
            guard let data = try await item.loadTransferable(type: Data.self) else {
                throw NekoMediaError.unsupportedImage
            }
            guard data.count <= AppConfig.maxVoiceImageBytes else {
                throw NekoMediaError.imageTooLarge
            }
            let prepared = try MediaUploadProcessor.prepareVoiceImage(from: data)
            photoData = prepared.data
            photoPreviewImage = UIImage(data: prepared.data)
            draftVoice = nil
            publishedVoice = nil
            step = .upload
        } catch {
            errorMessage = userFacingMessage(error)
        }
    }

    @MainActor
    private func generatePreview(stayOnPreview: Bool = false) async {
        guard let photoData else {
            errorMessage = "先上传一张猫咪照片吧。"
            return
        }
        guard appModel.session != nil else {
            pendingAnalysisAfterLogin = stayOnPreview
            appModel.requestLogin(message: "识别猫咪心声前需要先登录。登录后，AI 心声会绑定到你的猫咪档案。")
            return
        }
        guard !isAnalyzing else { return }

        if !stayOnPreview {
            draftVoice = nil
            step = .preview
        }

        isAnalyzing = true
        defer { isAnalyzing = false }

        do {
            let voice = try await appModel.generateCatVoicePreview(imageData: photoData, scene: scene)
            draftVoice = voice
        } catch {
            errorMessage = userFacingMessage(error)
            if !stayOnPreview {
                step = .background
            }
        }
    }

    @MainActor
    private func publishDraft() async {
        guard let photoData else {
            errorMessage = "先上传一张猫咪照片吧。"
            step = .upload
            return
        }
        guard let draftVoice else {
            errorMessage = "先让 AI 识别出一条猫咪心声吧。"
            step = .background
            return
        }
        guard !isPublishing else { return }

        isPublishing = true
        defer { isPublishing = false }

        do {
            let saved = try await appModel.saveGeneratedCatVoice(draftVoice, imageData: photoData)
            publishedVoice = saved
            latestPublishedVoice = saved
            step = .success
        } catch {
            errorMessage = userFacingMessage(error)
        }
    }

    private var sceneBinding: Binding<String> {
        Binding(
            get: { scene },
            set: { scene = String($0.prefix(120)) }
        )
    }

    private var loadingText: (title: String, hint: String)? {
        if isPublishing {
            return ("正在发布猫咪心声…", "PUBLISHING")
        }
        if isAnalyzing {
            if step == .preview {
                return nil
            }
            return (step == .preview ? "AI 正在重新识别…" : "AI 正在识别它的小心思…", step == .preview ? "RE · ANALYZING" : "ANALYZING")
        }
        return nil
    }

    private func userFacingMessage(_ error: Error) -> String {
        NekoUserFacingError.message(for: error, fallback: "动态发布失败，请稍后再试。")
    }
}

private enum PublishStep {
    case upload
    case background
    case preview
    case success
}

private enum PublishWebStyle {
    static let step = Color(red: 0.535, green: 0.374, blue: 0.635)
    static let uploadPink = Color(red: 0.980, green: 0.910, blue: 0.962)
    static let uploadCream = Color(red: 0.985, green: 0.902, blue: 0.925)
    static let textarea = Color(red: 0.987, green: 0.965, blue: 0.992)
    static let shadow = NekoTheme.soulViolet.opacity(0.18)
    static let photoStroke = Color(red: 0.545, green: 0.345, blue: 0.615)

    static let uploadGradient = LinearGradient(
        colors: [uploadPink, uploadCream],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let warmPhotoGradient = LinearGradient(
        colors: [
            Color(red: 0.988, green: 0.964, blue: 0.878),
            Color(red: 0.958, green: 0.893, blue: 0.722),
            Color(red: 0.914, green: 0.818, blue: 0.620),
        ],
        startPoint: .top,
        endPoint: .bottom
    )

    static let insightGradient = LinearGradient(
        colors: [
            Color(red: 0.988, green: 0.942, blue: 0.978).opacity(0.90),
            Color(red: 0.958, green: 0.918, blue: 0.996).opacity(0.86),
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}

private struct PublishUploadScreen: View {
    @Binding var selectedPhotoItem: PhotosPickerItem?
    let photoPreviewImage: UIImage?
    let profileAvatarURL: URL?
    let profileAvatarObjectKey: String?
    let canContinue: Bool
    let isDisabled: Bool
    let onBack: () -> Void
    let onNext: () -> Void

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .bottom) {
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 0) {
                        PublishTopBar(stepText: "STEP 01 / 03", onBack: onBack) {
                            Color.clear.frame(width: 36, height: 36)
                        }

                        VStack(alignment: .leading, spacing: 6) {
                            Text("记录一个瞬间")
                                .font(.system(size: 24, weight: .light))
                                .foregroundStyle(NekoTheme.ink)
                            Text("上传一张照片，AI 帮你读懂它的小心思 · 不超过 10MB")
                                .font(.system(size: NekoTypography.web(12.5), weight: .regular))
                                .foregroundStyle(NekoTheme.muted)
                                .lineSpacing(4)
                        }
                        .padding(.horizontal, 28)
                        .padding(.top, 24)

                        PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                            PublishUploadPhotoCard(
                                photoPreviewImage: photoPreviewImage,
                                profileAvatarURL: profileAvatarURL,
                                profileAvatarObjectKey: profileAvatarObjectKey
                            )
                        }
                        .buttonStyle(.plain)
                        .disabled(isDisabled)
                        .padding(.horizontal, 20)
                        .padding(.top, 28)

                        PublishInfoCard(title: "推荐照片") {
                            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: 8) {
                                PublishTipItem(icon: "😺", text: "猫咪正脸")
                                PublishTipItem(icon: "🐾", text: "有趣行为")
                                PublishTipItem(icon: "👀", text: "明显表情")
                                PublishTipItem(icon: "💗", text: "与主人互动")
                            }
                            Text("自然的瞬间，往往最能体现它当时的小心思")
                                .font(.system(size: NekoTypography.web(11), weight: .regular))
                                .foregroundStyle(PublishWebStyle.step)
                                .lineSpacing(4)
                                .padding(.top, 4)
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 16)

                        PublishInfoCard(title: "AI 会做什么？") {
                            Text("AI 将结合这张照片与猫咪人格档案，来生成一条专属于它的猫咪心声。")
                                .font(.system(size: NekoTypography.web(11.5), weight: .regular))
                                .foregroundStyle(NekoTheme.ink.opacity(0.85))
                                .lineSpacing(5)
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 16)
                    }
                    .frame(width: proxy.size.width, alignment: .leading)
                    .padding(.top, 52)
                    .padding(.bottom, 124)
                }

                PublishBottomCTA(title: "下一步", isEnabled: canContinue, isBusy: false, action: onNext)
                    .frame(width: proxy.size.width)
            }
        }
    }
}

private struct PublishBackgroundScreen: View {
    @Binding var scene: String
    let isAnalyzing: Bool
    let onBack: () -> Void
    let onAnalyze: () -> Void

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .bottom) {
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 0) {
                        PublishTopBar(stepText: "STEP 02 / 03", onBack: onBack) {
                            Button(action: onAnalyze) {
                                Text("跳过")
                                    .font(.system(size: NekoTypography.web(11), weight: .regular))
                                    .tracking(2.2)
                                    .foregroundStyle(PublishWebStyle.step)
                                    .padding(.horizontal, 14)
                                    .frame(height: 36)
                                    .background(.white.opacity(0.70), in: Capsule())
                                    .shadow(color: PublishWebStyle.shadow, radius: 14, x: 0, y: 7)
                            }
                            .buttonStyle(.plain)
                            .disabled(isAnalyzing)
                        }

                        VStack(alignment: .leading, spacing: 6) {
                            Text("发生了什么呢？")
                                .font(.system(size: 22, weight: .light))
                                .foregroundStyle(NekoTheme.ink)
                            Text("补充背景信息，可以让 AI 更懂它哦 （可选）")
                                .font(.system(size: NekoTypography.web(12), weight: .regular))
                                .foregroundStyle(NekoTheme.muted)
                        }
                        .padding(.horizontal, 28)
                        .padding(.top, 24)

                        VStack(alignment: .leading, spacing: 10) {
                            PublishSectionTitle("文字描述")
                            ZStack(alignment: .topLeading) {
                                if scene.isEmpty {
                                    Text("例如：我刚打开猫条，它就跑过来了")
                                        .font(.system(size: NekoTypography.web(12.5), weight: .regular))
                                        .foregroundStyle(NekoTheme.mutedLight)
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 13)
                                }
                                TextEditor(text: $scene)
                                    .font(.system(size: NekoTypography.web(12.5), weight: .regular))
                                    .foregroundStyle(NekoTheme.ink)
                                    .lineSpacing(4)
                                    .scrollContentBackground(.hidden)
                                    .padding(8)
                                    .frame(minHeight: 110)
                                    .background(PublishWebStyle.textarea, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                            }
                            Text("\(scene.count) / 120")
                                .font(.system(size: NekoTypography.web(9.5), weight: .regular))
                                .foregroundStyle(PublishWebStyle.step.opacity(0.82))
                                .frame(maxWidth: .infinity, alignment: .trailing)
                        }
                        .padding(16)
                        .background(.white.opacity(0.85), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 22, style: .continuous)
                                .stroke(.white.opacity(0.70), lineWidth: 1)
                        }
                        .shadow(color: PublishWebStyle.shadow, radius: 22, x: 0, y: 12)
                        .padding(.horizontal, 20)
                        .padding(.top, 20)
                    }
                    .frame(width: proxy.size.width, alignment: .leading)
                    .padding(.top, 52)
                    .padding(.bottom, 124)
                }

                PublishBottomCTA(title: "下一步", isEnabled: !isAnalyzing, isBusy: isAnalyzing, action: onAnalyze)
                    .frame(width: proxy.size.width)
            }
        }
    }
}

private struct PublishPreviewScreen: View {
    let catName: String
    let photoPreviewImage: UIImage?
    let draftVoice: CatVoiceResult?
    let isLoading: Bool
    let isReanalyzing: Bool
    let isPublishing: Bool
    let onBack: () -> Void
    let onReanalyze: () -> Void
    let onPublish: () -> Void

    var body: some View {
        GeometryReader { proxy in
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    PublishTopBar(stepText: "STEP 03 / 03", onBack: onBack) {
                        Color.clear.frame(width: 36, height: 36)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 6) {
                            Text("✦")
                                .foregroundStyle(NekoTheme.soulViolet)
                            Text("AI 已 读 懂 它 的 心 声")
                        }
                        .font(.system(size: NekoTypography.web(9.5), weight: .regular))
                        .tracking(3.0)
                        .foregroundStyle(PublishWebStyle.step)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 5)
                        .background(.white.opacity(0.75), in: Capsule())

                        Text("这是它想对你说的话")
                            .font(.system(size: 20, weight: .light))
                            .foregroundStyle(NekoTheme.ink)
                    }
                    .padding(.horizontal, 28)
                    .padding(.top, 20)

                    PublishPreviewStageCard(
                        catName: catName,
                        photoPreviewImage: photoPreviewImage,
                        voice: draftVoice,
                        isLoading: isLoading
                    )
                        .padding(.horizontal, 20)
                        .padding(.top, 16)

                    HStack(spacing: 10) {
                        Button("重新识别", action: onReanalyze)
                            .buttonStyle(PublishSecondaryPillStyle())
                            .disabled(isReanalyzing || isPublishing)

                        Button(action: onPublish) {
                            HStack(spacing: 8) {
                                if isPublishing {
                                    ProgressView()
                                        .tint(.white)
                                }
                                Text(isPublishing ? "发布中…" : "发布心声")
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(PublishPrimaryPillStyle())
                        .disabled(isReanalyzing || isPublishing || draftVoice == nil)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 20)
                }
                .frame(width: proxy.size.width, alignment: .leading)
                .padding(.top, 52)
                .padding(.bottom, 38)
            }
        }
    }
}

private struct PublishSuccessScreen: View {
    let catName: String
    let photoPreviewImage: UIImage?
    let voice: CatVoiceResult?
    let onReturnHome: () -> Void

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .bottom) {
                Circle()
                    .fill(NekoTheme.soulPink.opacity(0.32))
                    .frame(width: 224, height: 224)
                    .blur(radius: 44)
                    .offset(x: -130, y: -265)
                Circle()
                    .fill(NekoTheme.soulViolet.opacity(0.24))
                    .frame(width: 260, height: 260)
                    .blur(radius: 54)
                    .offset(x: 160, y: -30)

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 0) {
                        VStack(spacing: 9) {
                            Text("A VOICE IS BORN")
                                .font(.system(size: NekoTypography.web(10), weight: .regular))
                                .tracking(4.5)
                                .foregroundStyle(Color(red: 0.665, green: 0.420, blue: 0.635))
                            Text("它，第一次开口了")
                                .font(.system(size: 22, weight: .medium))
                                .foregroundStyle(NekoTheme.ink)
                            Text("\(catName)的声音，\n刚刚从猫咪世界传了过来")
                                .font(.system(size: NekoTypography.web(12.5), weight: .regular))
                                .foregroundStyle(PublishWebStyle.step)
                                .multilineTextAlignment(.center)
                                .lineSpacing(5)
                        }
                        .padding(.horizontal, 22)

                        PublishSuccessVoiceCard(catName: catName, photoPreviewImage: photoPreviewImage, voice: voice)
                            .padding(.horizontal, 20)
                            .padding(.top, 28)

                        VStack(alignment: .leading, spacing: 10) {
                            HStack(spacing: 8) {
                                Text("✦")
                                    .foregroundStyle(NekoTheme.soulViolet)
                                Text("AI 发 现")
                                    .font(.system(size: NekoTypography.web(10), weight: .regular))
                                    .tracking(4.0)
                                    .foregroundStyle(PublishWebStyle.step)
                            }

                            Text(voice?.analysis?.nonEmpty ?? "暂未获得\(catName)的 AI 心声解析。")
                                .font(.system(size: NekoTypography.web(12.5), weight: .regular))
                                .foregroundStyle(NekoTheme.ink.opacity(0.86))
                                .lineSpacing(6)
                        }
                        .padding(16)
                        .background(PublishWebStyle.insightGradient, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 22, style: .continuous)
                                .stroke(.white.opacity(0.70), lineWidth: 1)
                        }
                        .shadow(color: PublishWebStyle.shadow, radius: 22, x: 0, y: 12)
                        .padding(.horizontal, 20)
                        .padding(.top, 16)

                        Text("把这个来自猫咪世界的故事\n分享给你在乎的人")
                            .font(.system(size: NekoTypography.web(11.5), weight: .regular))
                            .foregroundStyle(PublishWebStyle.step)
                            .multilineTextAlignment(.center)
                            .lineSpacing(5)
                            .padding(.top, 20)
                    }
                    .frame(width: proxy.size.width)
                    .padding(.top, 64)
                    .padding(.bottom, 114)
                }

                PublishBottomCTA(title: "返回首页", isEnabled: true, isBusy: false, action: onReturnHome)
                    .frame(width: proxy.size.width)
            }
        }
    }
}

private struct PublishTopBar<Trailing: View>: View {
    let stepText: String
    let onBack: () -> Void
    private let trailing: Trailing

    init(stepText: String, onBack: @escaping () -> Void, @ViewBuilder trailing: () -> Trailing) {
        self.stepText = stepText
        self.onBack = onBack
        self.trailing = trailing()
    }

    var body: some View {
        HStack {
            PublishBackButton(onBack: onBack)
            Spacer()
            Text(stepText)
                .font(.system(size: NekoTypography.web(10), weight: .regular))
                .tracking(4.0)
                .foregroundStyle(PublishWebStyle.step)
            Spacer()
            trailing
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 24)
    }
}

private struct PublishBackButton: View {
    let onBack: () -> Void

    var body: some View {
        Button(action: onBack) {
            PublishChevronLeftIcon()
                .stroke(NekoTheme.soulViolet, style: StrokeStyle(lineWidth: 2.25, lineCap: .round, lineJoin: .round))
                .frame(width: 16, height: 16)
                .frame(width: 36, height: 36)
                .background(.white.opacity(0.80), in: Circle())
                .shadow(color: PublishWebStyle.shadow, radius: 14, x: 0, y: 7)
        }
        .buttonStyle(.plain)
    }
}

private struct PublishUploadPhotoCard: View {
    let photoPreviewImage: UIImage?
    let profileAvatarURL: URL?
    let profileAvatarObjectKey: String?

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(PublishWebStyle.uploadGradient)

            if let photoPreviewImage {
                VStack(spacing: 12) {
                    Image(uiImage: photoPreviewImage)
                        .resizable()
                        .scaledToFill()
                        .frame(height: 188)
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

                    HStack(spacing: 6) {
                        Text("✓ 已上传")
                            .foregroundStyle(Color(red: 0.735, green: 0.408, blue: 0.685))
                        Text("· 点击可重新选择")
                            .foregroundStyle(NekoTheme.muted)
                    }
                    .font(.system(size: NekoTypography.web(12), weight: .regular))
                }
                .padding(20)
            } else {
                ZStack {
                    Circle()
                        .fill(.white.opacity(0.40))
                        .frame(width: 128, height: 128)
                        .blur(radius: 32)
                        .offset(x: 120, y: -90)
                    Circle()
                        .fill(NekoTheme.soulPink.opacity(0.32))
                        .frame(width: 116, height: 116)
                        .blur(radius: 32)
                        .offset(x: -118, y: 94)

                    VStack(spacing: 16) {
                        ZStack {
                            Circle()
                                .fill(NekoTheme.soulPink.opacity(0.42))
                                .frame(width: 106, height: 106)
                                .blur(radius: 24)
                            CatAvatarView(
                                localImage: nil,
                                remoteURL: profileAvatarURL,
                                objectKey: profileAvatarObjectKey,
                                size: 80
                            )
                        }

                        VStack(spacing: 8) {
                            ZStack {
                                Circle()
                                    .fill(.white.opacity(0.86))
                                    .frame(width: 40, height: 40)
                                    .shadow(color: PublishWebStyle.shadow, radius: 14, x: 0, y: 7)
                                PublishPhotoIcon()
                                    .stroke(PublishWebStyle.photoStroke, style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
                                    .frame(width: 20, height: 20)
                            }
                            Text("点击上传照片")
                                .font(.system(size: NekoTypography.web(14), weight: .medium))
                                .foregroundStyle(NekoTheme.ink)
                            Text("支持 JPG / PNG")
                                .font(.system(size: NekoTypography.web(11), weight: .regular))
                                .foregroundStyle(NekoTheme.muted)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
        .frame(minHeight: 220)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(.white.opacity(0.70), lineWidth: 1)
        }
        .shadow(color: PublishWebStyle.shadow, radius: 28, x: 0, y: 14)
    }
}

private struct PublishInfoCard<Content: View>: View {
    let title: String
    private let content: Content

    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            PublishSectionTitle(title)
            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white.opacity(0.65), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(.white.opacity(0.70), lineWidth: 1)
        }
    }
}

private struct PublishSectionTitle: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(.system(size: NekoTypography.web(10), weight: .regular))
            .tracking(3.5)
            .foregroundStyle(PublishWebStyle.step)
    }
}

private struct PublishTipItem: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(spacing: 6) {
            Text(icon)
                .font(.system(size: NekoTypography.web(13)))
            Text(text)
                .font(.system(size: NekoTypography.web(11.5), weight: .regular))
                .foregroundStyle(NekoTheme.ink)
        }
    }
}

private struct PublishBottomCTA: View {
    let title: String
    let isEnabled: Bool
    let isBusy: Bool
    let action: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            LinearGradient(
                colors: [.clear, NekoTheme.lilacBottom.opacity(0.78)],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 18)

            Button(action: action) {
                HStack(spacing: 8) {
                    if isBusy {
                        ProgressView()
                            .tint(.white)
                    }
                    Text(isBusy ? "识别中…" : title)
                }
                .font(.system(size: NekoTypography.web(14), weight: .medium))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 15)
                .background(NekoTheme.primaryGradient, in: Capsule())
                .shadow(color: isEnabled ? NekoTheme.soulViolet.opacity(0.30) : .clear, radius: 22, x: 0, y: 10)
                .opacity(isEnabled ? 1 : 0.40)
            }
            .buttonStyle(.plain)
            .disabled(!isEnabled)
            .padding(.horizontal, 20)
            .padding(.bottom, 10)
            .background(NekoTheme.lilacBottom.opacity(0.78))
        }
        .ignoresSafeArea(edges: .bottom)
        .ignoresSafeArea(.keyboard, edges: .bottom)
    }
}

private struct PublishPreviewStageCard: View {
    let catName: String
    let photoPreviewImage: UIImage?
    let voice: CatVoiceResult?
    let isLoading: Bool

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                PublishWebStyle.warmPhotoGradient

                if let photoPreviewImage {
                    Image(uiImage: photoPreviewImage)
                        .resizable()
                        .scaledToFill()
                        .frame(width: proxy.size.width, height: 560)
                        .clipped()
                } else {
                    Text("等待照片")
                        .font(.system(size: NekoTypography.web(12), weight: .regular))
                        .tracking(2.0)
                        .foregroundStyle(PublishWebStyle.step)
                        .frame(width: proxy.size.width, height: 560)
                }

                LinearGradient(
                    colors: [Color.black.opacity(0.16), .clear],
                    startPoint: .top,
                    endPoint: .center
                )

                VStack(spacing: 0) {
                    if let voiceText {
                        PublishSpeechBubble(
                            catName: catName,
                            text: voiceText,
                            centered: true
                        )
                        .padding(.top, 12)
                        .transition(.opacity.combined(with: .scale(scale: 0.96)))
                    }

                    if isLoading {
                        HStack(spacing: 8) {
                            ProgressView()
                                .tint(.white)
                                .scaleEffect(0.82)
                            Text("AI 正在听它怎么说")
                                .font(.system(size: NekoTypography.web(10.5), weight: .medium))
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 13)
                        .padding(.vertical, 7)
                        .background(Color.black.opacity(0.22), in: Capsule())
                        .padding(.top, voiceText == nil ? 22 : 10)
                        .transition(.opacity.combined(with: .scale(scale: 0.96)))
                    }

                    Spacer()

                    VStack(alignment: .leading, spacing: 8) {
                        PublishSectionTitle("AI 心 声 解 析")
                        Text(analysisText)
                            .font(.system(size: NekoTypography.web(12), weight: .regular))
                            .foregroundStyle(NekoTheme.ink.opacity(0.86))
                            .lineSpacing(5)
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.white.opacity(0.85), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .stroke(.white.opacity(0.70), lineWidth: 1)
                    }
                    .shadow(color: NekoTheme.ink.opacity(0.14), radius: 20, x: 0, y: 10)
                    .padding(16)
                }
            }
            .frame(width: proxy.size.width, height: 560)
        }
        .frame(height: 560)
        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .stroke(.white.opacity(0.70), lineWidth: 1)
        }
        .shadow(color: NekoTheme.soulViolet.opacity(0.22), radius: 30, x: 0, y: 16)
        .animation(.easeInOut(duration: 0.22), value: isLoading)
        .animation(.easeInOut(duration: 0.22), value: voiceText ?? "")
    }

    private var voiceText: String? {
        voice?.text.nonEmpty
    }

    private var analysisText: String {
        if let analysis = voice?.analysis?.nonEmpty {
            return analysis
        }
        return isLoading ? "AI 正在结合照片、场景和猫咪人格档案生成这一刻的心声…" : "暂未获得 AI 心声解析，请点击重新识别。"
    }
}

private struct PublishSuccessVoiceCard: View {
    let catName: String
    let photoPreviewImage: UIImage?
    let voice: CatVoiceResult?

    private var tags: [String] {
        let next = voice?.tags ?? []
        return next.isEmpty ? ["💗 想念", "😼 傲娇"] : next
    }

    var body: some View {
        GeometryReader { proxy in
            VStack(spacing: 0) {
                ZStack(alignment: .topLeading) {
                    Rectangle()
                        .fill(
                            LinearGradient(
                                colors: [Color(red: 0.988, green: 0.936, blue: 0.982), Color(red: 0.954, green: 0.918, blue: 0.996)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )

                    if let photoPreviewImage {
                        Image(uiImage: photoPreviewImage)
                            .resizable()
                            .scaledToFit()
                            .frame(width: proxy.size.width, height: 300)
                    } else {
                        Text("等待照片")
                            .font(.system(size: NekoTypography.web(12), weight: .regular))
                            .tracking(2.0)
                            .foregroundStyle(PublishWebStyle.step)
                            .frame(width: proxy.size.width, height: 300)
                    }

                    LinearGradient(
                        colors: [Color.black.opacity(0.18), .clear],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: 150)

                    PublishSpeechBubble(
                        catName: catName,
                        text: "💭 \(voice?.text.nonEmpty ?? "这条心声没有生成成功，请返回重新识别。")",
                        centered: false
                    )
                    .padding(.leading, 14)
                    .padding(.top, 14)

                    Text("✦")
                        .font(.system(size: NekoTypography.web(12)))
                        .foregroundStyle(NekoTheme.soulPink)
                        .shadow(color: .white.opacity(0.8), radius: 10)
                        .frame(width: proxy.size.width, alignment: .trailing)
                        .padding(.trailing, 16)
                        .padding(.top, 8)
                }
                .frame(width: proxy.size.width, height: 300)

                HStack(spacing: 8) {
                    ForEach(Array(tags.prefix(2)), id: \.self) { tag in
                        Text(tag)
                            .font(.system(size: NekoTypography.web(10.5), weight: .medium))
                            .foregroundStyle(Color(red: 0.455, green: 0.285, blue: 0.545))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(
                                LinearGradient(
                                    colors: [Color(red: 0.982, green: 0.925, blue: 0.976), Color(red: 0.958, green: 0.918, blue: 0.996)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                in: Capsule()
                            )
                    }
                    Spacer()
                    Text("刚刚发布")
                        .font(.system(size: NekoTypography.web(10), weight: .regular))
                        .tracking(2.5)
                        .foregroundStyle(PublishWebStyle.step.opacity(0.86))
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 13)
                .background(.white.opacity(0.85))
            }
        }
        .frame(height: 344)
        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .stroke(.white.opacity(0.75), lineWidth: 1)
        }
        .shadow(color: NekoTheme.soulViolet.opacity(0.26), radius: 32, x: 0, y: 16)
    }
}

private struct PublishSpeechBubble: View {
    let catName: String
    let text: String
    let centered: Bool

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text(catName)
                    .font(.system(size: NekoTypography.web(8), weight: .regular))
                    .tracking(3.5)
                    .foregroundStyle(PublishWebStyle.step)
                Text(text)
                    .font(.system(size: NekoTypography.web(12.5), weight: .regular))
                    .foregroundStyle(NekoTheme.ink)
                    .lineSpacing(4)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(.white.opacity(0.95), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .shadow(color: NekoTheme.ink.opacity(0.16), radius: 18, x: 0, y: 8)

            if centered {
                Triangle()
                    .fill(.white.opacity(0.95))
                    .frame(width: 16, height: 12)
                    .shadow(color: NekoTheme.ink.opacity(0.08), radius: 8, x: 0, y: 5)
            }
        }
        .frame(maxWidth: centered ? 280 : nil, alignment: centered ? .center : .leading)
        .frame(maxWidth: centered ? .infinity : nil, alignment: centered ? .center : .leading)
    }
}

private struct PublishLoadingOverlay: View {
    let title: String
    let hint: String

    var body: some View {
        ZStack {
            Color.white.opacity(0.60)
                .ignoresSafeArea()
                .background(.ultraThinMaterial)

            VStack(spacing: 18) {
                ZStack {
                    Circle()
                        .fill(NekoTheme.soulPink.opacity(0.60))
                        .frame(width: 64, height: 64)
                        .blur(radius: 16)
                    ProgressView()
                        .tint(NekoTheme.soulViolet)
                        .scaleEffect(1.25)
                }
                Text(title)
                    .font(.system(size: NekoTypography.web(13), weight: .medium))
                    .foregroundStyle(NekoTheme.ink)
                Text(hint)
                    .font(.system(size: NekoTypography.web(11), weight: .regular))
                    .tracking(2.0)
                    .foregroundStyle(PublishWebStyle.step)
            }
        }
        .zIndex(50)
    }
}

private struct PublishPrimaryPillStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: NekoTypography.web(13), weight: .medium))
            .foregroundStyle(.white)
            .padding(.vertical, 14)
            .padding(.horizontal, 18)
            .background(NekoTheme.primaryGradient, in: Capsule())
            .shadow(color: NekoTheme.soulViolet.opacity(0.26), radius: 18, x: 0, y: 9)
            .opacity(configuration.isPressed ? 0.86 : 1)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
    }
}

private struct PublishSecondaryPillStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: NekoTypography.web(12.5), weight: .regular))
            .foregroundStyle(NekoTheme.ink)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .padding(.horizontal, 16)
            .background(.white.opacity(configuration.isPressed ? 0.95 : 0.85), in: Capsule())
            .shadow(color: PublishWebStyle.shadow, radius: 18, x: 0, y: 9)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
    }
}

private struct PublishChevronLeftIcon: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.maxX * 0.68, y: rect.minY + rect.height * 0.18))
        path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.32, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.maxX * 0.68, y: rect.minY + rect.height * 0.82))
        return path
    }
}

private struct PublishPhotoIcon: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let w = rect.width
        let h = rect.height

        path.addRoundedRect(
            in: CGRect(x: rect.minX + w * 0.10, y: rect.minY + h * 0.20, width: w * 0.80, height: h * 0.60),
            cornerSize: CGSize(width: w * 0.15, height: h * 0.15)
        )

        path.addEllipse(in: CGRect(x: rect.minX + w * 0.35, y: rect.minY + h * 0.35, width: w * 0.30, height: h * 0.30))

        path.move(to: CGPoint(x: rect.minX + w * 0.20, y: rect.minY + h * 0.70))
        path.addLine(to: CGPoint(x: rect.minX + w * 0.35, y: rect.minY + h * 0.50))
        path.addLine(to: CGPoint(x: rect.minX + w * 0.50, y: rect.minY + h * 0.60))
        path.addLine(to: CGPoint(x: rect.minX + w * 0.70, y: rect.minY + h * 0.40))
        path.addLine(to: CGPoint(x: rect.minX + w * 0.80, y: rect.minY + h * 0.50))

        return path
    }
}

private struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

private struct VoicePreviewCard: View {
    let voice: CatVoiceResult

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("已发布")
                    .font(.system(size: NekoTypography.web(11), weight: .semibold))
                    .tracking(3)
                    .foregroundStyle(NekoTheme.soulViolet)
                Spacer()
                Text(voice.time)
                    .font(.system(size: NekoTypography.web(12), weight: .medium))
                    .foregroundStyle(NekoTheme.muted)
            }

            Text("“\(voice.text)”")
                .font(.system(size: NekoTypography.web(17), weight: .light))
                .lineSpacing(6)
                .foregroundStyle(NekoTheme.ink)

            if let analysis = voice.analysis, !analysis.isEmpty {
                Text(analysis)
                    .font(.system(size: NekoTypography.web(13)))
                    .foregroundStyle(NekoTheme.muted)
                    .lineSpacing(5)
            }

            if !voice.tags.isEmpty {
                HStack {
                    ForEach(voice.tags.prefix(3), id: \.self) { tag in
                        Text(tag)
                            .font(.system(size: NekoTypography.web(11), weight: .medium))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(NekoTheme.softPink.opacity(0.72), in: Capsule())
                            .foregroundStyle(NekoTheme.soulViolet)
                    }
                }
            }
        }
        .padding(18)
        .background(NekoTheme.cardGradient, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 26, style: .continuous).stroke(.white.opacity(0.68), lineWidth: 1) }
        .shadow(color: NekoTheme.soulViolet.opacity(0.12), radius: 24, x: 0, y: 12)
    }
}

private struct LatestVoiceCard: View {
    let voice: CatVoiceResult

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "quote.bubble.fill")
                .foregroundStyle(NekoTheme.soulViolet)
                .font(.system(size: 18, weight: .semibold))

            VStack(alignment: .leading, spacing: 6) {
                Text("刚发布的动态")
                    .font(.system(size: NekoTypography.web(12), weight: .semibold))
                    .foregroundStyle(NekoTheme.muted)
                Text("“\(voice.text)”")
                    .font(.system(size: NekoTypography.web(14), weight: .medium))
                    .foregroundStyle(NekoTheme.ink)
                    .lineLimit(3)
            }

            Spacer(minLength: 0)
        }
        .padding(16)
        .background(NekoTheme.cardGradient, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}

private struct CatAvatarView: View {
    let localImage: UIImage?
    let remoteURL: URL?
    var objectKey: String? = nil
    let size: CGFloat

    var body: some View {
        ZStack {
            Circle()
                .fill(Color.white.opacity(0.78))

            if let localImage {
                Image(uiImage: localImage)
                    .resizable()
                    .scaledToFill()
            } else {
                NekoRemoteImageView(
                    remoteURL: remoteURL,
                    objectKey: objectKey,
                    contentMode: .fill
                ) {
                    fallback
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay {
            Circle()
                .stroke(.white.opacity(0.88), lineWidth: 2)
        }
        .shadow(color: NekoTheme.soulViolet.opacity(0.18), radius: 16, x: 0, y: 8)
    }

    private var fallback: some View {
        Image(systemName: "pawprint.fill")
            .font(.system(size: size * 0.36, weight: .semibold))
            .foregroundStyle(NekoTheme.soulViolet)
    }
}

private struct FieldTitle: View {
    private let title: String

    init(_ title: String) {
        self.title = title
    }

    var body: some View {
        Text(title)
            .font(.system(size: NekoTypography.web(11), weight: .semibold))
            .tracking(2)
            .foregroundStyle(NekoTheme.muted)
    }
}

private struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: NekoTypography.web(15), weight: .semibold))
            .foregroundStyle(.white)
            .padding(.vertical, 15)
            .background(NekoTheme.primaryGradient, in: Capsule())
            .shadow(color: NekoTheme.soulViolet.opacity(0.18), radius: 20, x: 0, y: 10)
            .opacity(configuration.isPressed ? 0.86 : 1)
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
    }
}

private struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: NekoTypography.web(15), weight: .semibold))
            .foregroundStyle(NekoTheme.ink)
            .padding(.vertical, 15)
            .background(.white.opacity(configuration.isPressed ? 0.62 : 0.82), in: Capsule())
    }
}

#Preview {
    ContentView()
        .environmentObject(NekoAppModel())
}
