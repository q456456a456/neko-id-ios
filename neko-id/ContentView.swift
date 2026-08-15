//
//  ContentView.swift
//  neko-id
//
//  Created by Amadeus on 2026/8/15.
//

import PhotosUI
import SwiftUI
import UIKit

struct ContentView: View {
    @EnvironmentObject private var appModel: NekoAppModel

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
                    HomeView()
                }
            }
            .navigationBarTitleDisplayMode(.inline)
        }
        .task {
            await appModel.bootstrap()
        }
        .alert("提示", isPresented: errorBinding) {
            Button("知道了", role: .cancel) {
                appModel.errorMessage = nil
            }
        } message: {
            Text(appModel.errorMessage ?? "")
        }
        .alert("完成", isPresented: noticeBinding) {
            Button("好", role: .cancel) {
                appModel.noticeMessage = nil
            }
        } message: {
            Text(appModel.noticeMessage ?? "")
        }
    }

    private var errorBinding: Binding<Bool> {
        Binding(
            get: { appModel.errorMessage != nil },
            set: { if !$0 { appModel.errorMessage = nil } }
        )
    }

    private var noticeBinding: Binding<Bool> {
        Binding(
            get: { appModel.noticeMessage != nil },
            set: { if !$0 { appModel.noticeMessage = nil } }
        )
    }
}

private struct LaunchingView: View {
    var body: some View {
        VStack(spacing: 16) {
            ProgressView()
                .tint(NekoTheme.soulViolet)

            Text("正在寻找你的猫咪档案…")
                .font(.system(size: 14, weight: .medium))
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
    @State private var email = ""
    @State private var code = ""
    @State private var codeSent = false

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                Spacer(minLength: 72)

                VStack(alignment: .leading, spacing: 8) {
                    Text("NEKO ACCOUNT")
                        .font(.system(size: 10, weight: .semibold))
                        .tracking(4.6)
                        .foregroundStyle(NekoTheme.soulViolet)

                    Text("邮箱验证码登录")
                        .font(.system(size: 28, weight: .light))
                        .foregroundStyle(NekoTheme.ink)

                    Text("输入邮箱，我们会通过 Supabase Auth 给你发送 6 位验证码。")
                        .font(.system(size: 12.5))
                        .foregroundStyle(NekoTheme.muted)
                        .lineSpacing(4)
                        .padding(.top, 2)
                }

                NekoGlassCard(cornerRadius: 28) {
                    VStack(alignment: .leading, spacing: 12) {
                        FieldTitle("邮箱")
                        TextField("you@example.com", text: $email)
                            .textInputAutocapitalization(.never)
                            .keyboardType(.emailAddress)
                            .textContentType(.emailAddress)
                            .autocorrectionDisabled()
                            .font(.system(size: 14, weight: .regular))
                            .foregroundStyle(NekoTheme.ink)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 14)
                            .background(NekoTheme.field, in: RoundedRectangle(cornerRadius: 16, style: .continuous))

                        Button {
                            codeSent = true
                            Task { await appModel.requestLoginCode(email: email) }
                        } label: {
                            Label(codeSent ? "重新发送验证码" : "发送验证码", systemImage: "envelope")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(NekoPrimaryButtonStyle())
                        .disabled(appModel.isBusy || email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                        if codeSent {
                            VStack(alignment: .leading, spacing: 12) {
                                FieldTitle("6 位验证码")
                                TextField("123456", text: $code)
                                    .keyboardType(.numberPad)
                                    .textContentType(.oneTimeCode)
                                    .multilineTextAlignment(.center)
                                    .font(.system(size: 22, weight: .semibold, design: .rounded))
                                    .tracking(8)
                                    .foregroundStyle(NekoTheme.ink)
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 13)
                                    .background(NekoTheme.field, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                                    .onChange(of: code) { _, newValue in
                                        code = String(newValue.filter(\.isNumber).prefix(6))
                                    }

                                Button {
                                    Task { await appModel.verifyLoginCode(email: email, code: code) }
                                } label: {
                                    Label("完成登录", systemImage: "checkmark.circle")
                                        .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(NekoPrimaryButtonStyle())
                                .disabled(appModel.isBusy || code.count != 6)

                                Text("如果看不到验证码，先检查垃圾邮件。")
                                    .font(.system(size: 11))
                                    .foregroundStyle(NekoTheme.muted)
                                    .frame(maxWidth: .infinity, alignment: .center)
                            }
                            .padding(.top, 8)
                        }
                    }
                    .padding(16)
                }
                .padding(.top, 30)

                Text("邮箱会作为账号唯一标识。登录后，猫咪档案、人格和心声会只绑定到当前用户。")
                    .font(.system(size: 11.5))
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
        .overlay(alignment: .center) {
            if appModel.isBusy {
                ProgressView()
                    .tint(NekoTheme.soulViolet)
                    .padding(18)
                    .background(.white.opacity(0.82), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            }
        }
    }
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
                        .font(.system(size: 11, weight: .semibold))
                        .tracking(4)
                        .foregroundStyle(NekoTheme.soulViolet)

                    Text("创建猫咪人格档案")
                        .font(.system(size: 30, weight: .light))
                        .foregroundStyle(NekoTheme.ink)

                    Text("先建立基础档案。照片、视频和 AI 人格生成会继续原生化接入。")
                        .font(.system(size: 14))
                        .foregroundStyle(NekoTheme.muted)
                        .lineSpacing(4)
                }

                VStack(alignment: .leading, spacing: 16) {
                    PhotosPicker(selection: $selectedAvatarItem, matching: .images) {
                        HStack(spacing: 16) {
                            CatAvatarView(localImage: avatarPreviewImage, remoteURL: nil, size: 76)

                            VStack(alignment: .leading, spacing: 6) {
                                Text(avatarPreviewImage == nil ? "选择猫咪照片" : "更换猫咪照片")
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundStyle(NekoTheme.ink)

                                Text("会作为头像上传到私有云端，单张不超过 10MB。")
                                    .font(.system(size: 12))
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
                .font(.system(size: 13, weight: .medium))
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
    @State private var isPublishSheetPresented = false
    @State private var isMePresented = false
    @State private var isPersonaPresented = false
    @State private var latestPublishedVoice: CatVoiceResult?

    var body: some View {
        ZStack(alignment: .bottom) {
            NekoBackground()

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
                                .font(.system(size: 16, weight: .medium))
                                .foregroundStyle(NekoTheme.ink)
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 26)

                        if let latestPublishedVoice {
                            VStack(spacing: 10) {
                                DayDivider(label: "今天")
                                TimelineLatestVoiceRow(voice: latestPublishedVoice, profile: profile)
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
                .padding(.bottom, 124)
            }

            HomeTabBar(
                active: .home,
                onHome: {},
                onPublish: { isPublishSheetPresented = true },
                onAccount: { isMePresented = true }
            )
        }
        .sheet(isPresented: $isPublishSheetPresented) {
            VoicePublishSheet(latestPublishedVoice: $latestPublishedVoice)
                .environmentObject(appModel)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .navigationDestination(isPresented: $isMePresented) {
            MeView()
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
    }
}

private struct HomeProfileCard: View {
    let profile: CatProfile
    let persona: CatPersonaResult?
    let onAccount: () -> Void

    var body: some View {
        NekoGlassCard(cornerRadius: 24, tint: true) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 12) {
                    CatAvatarView(localImage: nil, remoteURL: profile.avatarURL, size: 46)

                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 7) {
                            Text(profile.name)
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(NekoTheme.ink)
                                .lineLimit(1)

                            Text(persona?.mbti ?? "INTJ-A")
                                .font(.system(size: 8.5, weight: .semibold))
                                .tracking(1.3)
                                .foregroundStyle(NekoTheme.soulViolet)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 1.5)
                                .background(Color.white.opacity(0.86), in: Capsule())
                        }

                        Text(persona?.type ?? "\(profile.gender.rawValue) · \(profile.ageStage.rawValue)")
                            .font(.system(size: 10.5, weight: .medium))
                            .foregroundStyle(NekoTheme.muted)
                            .lineLimit(1)
                    }

                    Spacer(minLength: 8)

                    Button {
                        onAccount()
                    } label: {
                        Text("查看人格 ›")
                            .font(.system(size: 10, weight: .semibold))
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
                        .font(.system(size: 14))
                    Text(persona?.dailyMood ?? "今天好像有点想你")
                        .font(.system(size: 12, weight: .regular))
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

                    CatAvatarView(localImage: nil, remoteURL: profile.avatarURL, size: 56)
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
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(NekoTheme.ink)
                    .padding(.top, 20)

                Text("记录一个瞬间，听听它怎么说")
                    .font(.system(size: 12))
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
                        .font(.system(size: 13, weight: .medium))
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
            .font(.system(size: 11, weight: .medium))
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

private struct TimelineLatestVoiceRow: View {
    let voice: CatVoiceResult
    let profile: CatProfile

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(spacing: 6) {
                Text(voice.time)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
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

            VoiceFeedCard(voice: voice, profile: profile)
        }
    }
}

private struct VoiceFeedCard: View {
    let voice: CatVoiceResult
    let profile: CatProfile

    var body: some View {
        NekoGlassCard(cornerRadius: 24) {
            VStack(alignment: .leading, spacing: 0) {
                ZStack(alignment: .topLeading) {
                    NekoTheme.photoPlaceholderGradient
                        .frame(height: 220)

                    VStack(alignment: .leading, spacing: 5) {
                        Text(profile.name)
                            .font(.system(size: 8, weight: .semibold))
                            .tracking(3)
                            .foregroundStyle(NekoTheme.muted)
                        Text("💭 \(voice.text)")
                            .font(.system(size: 12.5, weight: .regular))
                            .lineSpacing(4)
                            .foregroundStyle(NekoTheme.ink)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 11)
                    .background(Color.white.opacity(0.95), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .padding(14)
                    .shadow(color: NekoTheme.ink.opacity(0.10), radius: 20, x: 0, y: 10)

                    VStack {
                        Spacer()
                        HStack {
                            Spacer()
                            CatAvatarView(localImage: nil, remoteURL: profile.avatarURL, size: 96)
                                .padding(20)
                        }
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))

                HStack(spacing: 8) {
                    ForEach(voice.tags.prefix(2), id: \.self) { tag in
                        Text(tag)
                            .font(.system(size: 10.5, weight: .semibold))
                            .foregroundStyle(NekoTheme.soulViolet)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(
                                LinearGradient(colors: [NekoTheme.softPink.opacity(0.86), NekoTheme.softLilac.opacity(0.76)], startPoint: .leading, endPoint: .trailing),
                                in: Capsule()
                            )
                    }

                    if let location = voice.location, !location.isEmpty {
                        Text("· \(location)")
                            .font(.system(size: 10.5))
                            .foregroundStyle(NekoTheme.muted)
                            .lineLimit(1)
                    }

                    Spacer()

                    Text("⋯")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(NekoTheme.muted)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
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
                .font(.system(size: 10, weight: .semibold))
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
                    .font(.system(size: 10, weight: .semibold))
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
                        .frame(width: 66, height: 66)
                        .blur(radius: 7)
                        .opacity(0.70)

                    Circle()
                        .fill(NekoTheme.primaryGradient)
                        .frame(width: 58, height: 58)
                        .shadow(color: NekoTheme.soulViolet.opacity(0.36), radius: 22, x: 0, y: 12)
                        .overlay {
                            Circle().stroke(Color.white.opacity(0.65), lineWidth: 2)
                        }
                    Text("＋")
                        .font(.system(size: 26, weight: .medium))
                        .foregroundStyle(.white)
                        .offset(y: -1)
                }
                .offset(y: -26)
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
        .padding(.top, 8)
        .padding(.bottom, 8)
        .background {
            RoundedRectangle(cornerRadius: 32, style: .continuous)
                .fill(Color.white.opacity(0.86))
            RoundedRectangle(cornerRadius: 32, style: .continuous)
                .stroke(Color.white.opacity(0.78), lineWidth: 1)
        }
        .shadow(color: NekoTheme.soulViolet.opacity(0.18), radius: 22, x: 0, y: 10)
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
    }
}

private struct HomeTabIcon: View {
    let kind: NekoTabSymbol.Kind
    let label: String
    let active: Bool

    var body: some View {
        VStack(spacing: 3) {
            NekoTabSymbol(kind: kind, active: active)
                .frame(width: 23, height: 23)
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .tracking(1.6)
        }
        .foregroundStyle(active ? NekoTheme.soulViolet : NekoTheme.muted)
        .frame(width: 46)
    }
}

private struct MeView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appModel: NekoAppModel
    @State private var isPublishSheetPresented = false
    @State private var isAccountPresented = false
    @State private var latestPublishedVoice: CatVoiceResult?

    var body: some View {
        ZStack(alignment: .bottom) {
            NekoBackground()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    HStack {
                        Text("我的")
                            .font(.system(size: 17, weight: .light))
                            .tracking(1)
                            .foregroundStyle(NekoTheme.ink)

                        Spacer()

                        Button {
                            appModel.noticeMessage = "设置中心即将上线 ⚙️"
                        } label: {
                            Text("⚙")
                                .font(.system(size: 14))
                                .frame(width: 36, height: 36)
                                .background(Color.white.opacity(0.80), in: Circle())
                                .shadow(color: NekoTheme.soulViolet.opacity(0.14), radius: 14, x: 0, y: 6)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 52)

                    if let profile = appModel.catProfile {
                        MeSummaryCard(profile: profile, persona: appModel.persona)
                            .padding(.horizontal, 20)
                            .padding(.top, 16)
                    }

                    CloudMemoryPanel {
                        isAccountPresented = true
                    }
                        .padding(.horizontal, 20)
                        .padding(.top, 16)

                    VStack(spacing: 10) {
                        MeRowButton(icon: "☁", title: "账号与云端数据", sub: "邮箱登录、昵称和同步管理") {
                            isAccountPresented = true
                        }
                        MeRowButton(icon: "✎", title: "修改人格档案", sub: "编辑猫咪基本信息") {
                            appModel.startOnboarding()
                        }
                        MeRowButton(icon: "♡", title: "管理猫咪心声", sub: "查看和管理所有心声") {
                            appModel.noticeMessage = "管理猫咪心声即将支持。"
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 20)
                    .padding(.bottom, 112)
                }
            }

            HomeTabBar(
                active: .me,
                onHome: { dismiss() },
                onPublish: { isPublishSheetPresented = true },
                onAccount: {}
            )
        }
        .navigationBarBackButtonHidden(true)
        .sheet(isPresented: $isPublishSheetPresented) {
            VoicePublishSheet(latestPublishedVoice: $latestPublishedVoice)
                .environmentObject(appModel)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .navigationDestination(isPresented: $isAccountPresented) {
            AccountCenterView()
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
                        CatAvatarView(localImage: nil, remoteURL: profile.avatarURL, size: 72)
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
                        .font(.system(size: 10, weight: .medium))
                        .tracking(1.4)
                        .foregroundStyle(NekoTheme.soulViolet)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.white.opacity(0.80), in: Capsule())
                    }

                    Spacer(minLength: 0)
                }

                Text("\"\(persona?.monologue ?? "它喜欢在窗边看世界，但只要你叫它的名字，它就会立刻回头。")\"")
                    .font(.system(size: 11.5))
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

private struct CloudMemoryPanel: View {
    @EnvironmentObject private var appModel: NekoAppModel
    let onAccountCenter: () -> Void

    var body: some View {
        NekoGlassCard(cornerRadius: 22) {
            VStack(alignment: .leading, spacing: 0) {
                if let email = appModel.session?.user.email, !email.isEmpty {
                    HStack(alignment: .top, spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            CloudMemoryTitle()

                            Text(email)
                                .font(.system(size: 12, weight: .regular))
                                .foregroundStyle(NekoTheme.ink.opacity(0.80))
                                .lineLimit(1)
                        }

                        Spacer(minLength: 10)

                        Button("退出") {
                            appModel.signOut()
                        }
                        .font(.system(size: 11, weight: .regular))
                        .foregroundStyle(NekoTheme.muted)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(Color.white.opacity(0.90), in: Capsule())
                        .buttonStyle(.plain)
                    }

                    Button("账号中心", action: onAccountCenter)
                        .font(.system(size: 12, weight: .regular))
                        .foregroundStyle(NekoTheme.ink)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Color.white.opacity(0.90), in: Capsule())
                        .padding(.top, 12)
                        .buttonStyle(.plain)

                    HStack(spacing: 8) {
                        Button {
                            appModel.noticeMessage = "云端同步已自动开启。"
                        } label: {
                            Text("保存到云端")
                                .frame(maxWidth: .infinity)
                        }
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white)
                        .padding(.vertical, 10)
                        .background(NekoTheme.primaryGradient, in: Capsule())
                        .buttonStyle(.plain)

                        Button {
                            appModel.noticeMessage = "已检查云端记忆。"
                        } label: {
                            Text("从云端恢复")
                                .frame(maxWidth: .infinity)
                        }
                        .font(.system(size: 12, weight: .regular))
                        .foregroundStyle(NekoTheme.ink)
                        .padding(.vertical, 10)
                        .background(Color.white.opacity(0.90), in: Capsule())
                        .buttonStyle(.plain)
                    }
                    .padding(.top, 8)
                } else {
                    CloudMemoryTitle()

                    Text("登录后，猫咪档案、人格和心声会保存到 Supabase。现在只支持邮箱验证码登录。")
                        .font(.system(size: 11.5))
                        .foregroundStyle(NekoTheme.ink.opacity(0.75))
                        .lineSpacing(4)
                        .padding(.top, 10)

                    Button {
                        appModel.noticeMessage = "你已经在 App 内使用邮箱验证码登录。"
                    } label: {
                        Text("邮箱验证码登录")
                            .frame(maxWidth: .infinity)
                    }
                    .font(.system(size: 12, weight: .medium))
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
                .font(.system(size: 13))
                .foregroundStyle(NekoTheme.soulViolet)
            Text("云 端 记 忆")
                .font(.system(size: 10, weight: .medium))
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
                    .font(.system(size: 16))
                    .foregroundStyle(NekoTheme.soulViolet)
                    .frame(width: 40, height: 40)
                    .background(NekoTheme.tintGradient, in: RoundedRectangle(cornerRadius: 16, style: .continuous))

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.system(size: 13.5, weight: .medium))
                        .foregroundStyle(NekoTheme.ink)
                    Text(sub)
                        .font(.system(size: 10.5))
                        .foregroundStyle(NekoTheme.muted)
                }

                Spacer()

                Text("›")
                    .font(.system(size: 16, weight: .medium))
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

private struct AccountCenterView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appModel: NekoAppModel
    @State private var selectedAvatarItem: PhotosPickerItem?

    var body: some View {
        ZStack {
            NekoBackground()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    HStack {
                        Button {
                            dismiss()
                        } label: {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(NekoTheme.soulViolet)
                                .frame(width: 36, height: 36)
                                .background(Color.white.opacity(0.82), in: Circle())
                                .shadow(color: NekoTheme.soulViolet.opacity(0.14), radius: 14, x: 0, y: 6)
                        }
                        .buttonStyle(.plain)

                        Spacer()

                        Text("账号与云端数据")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(NekoTheme.ink)

                        Spacer()

                        Color.clear.frame(width: 36, height: 36)
                    }
                    .padding(.top, 52)

                    NekoGlassCard(cornerRadius: 24) {
                        VStack(alignment: .leading, spacing: 14) {
                            Text("NEKO ACCOUNT")
                                .font(.system(size: 10, weight: .semibold))
                                .tracking(4)
                                .foregroundStyle(NekoTheme.soulViolet)

                            Text(appModel.session?.user.email ?? "未登录")
                                .font(.system(size: 17, weight: .medium))
                                .foregroundStyle(NekoTheme.ink)

                            PhotosPicker(selection: $selectedAvatarItem, matching: .images) {
                                Label("更新猫咪头像", systemImage: "photo")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(NekoSecondaryButtonStyle())

                            Button {
                                appModel.startOnboarding()
                            } label: {
                                Label("重新创建档案", systemImage: "sparkles")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(NekoSecondaryButtonStyle())

                            Button("退出登录") {
                                appModel.signOut()
                            }
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(NekoTheme.muted)
                            .frame(maxWidth: .infinity)
                            .padding(.top, 6)
                        }
                        .padding(16)
                    }

                    Text("邮箱会作为账号唯一标识。登录后，猫咪档案、人格和心声会只绑定到当前用户。")
                        .font(.system(size: 11.5))
                        .lineSpacing(4)
                        .foregroundStyle(NekoTheme.muted)
                        .padding(.horizontal, 6)

                    Spacer(minLength: 32)
                }
                .padding(.horizontal, 24)
            }
        }
        .navigationBarBackButtonHidden(true)
        .onChange(of: selectedAvatarItem) { _, item in
            Task { await uploadAvatar(from: item) }
        }
    }

    @MainActor
    private func uploadAvatar(from item: PhotosPickerItem?) async {
        guard let item else { return }

        do {
            guard let data = try await item.loadTransferable(type: Data.self) else {
                throw NekoMediaError.unsupportedImage
            }
            await appModel.uploadAvatarImageData(data)
        } catch {
            appModel.errorMessage = "读取照片失败，请重新选择一张图片。"
        }
    }
}

private struct PersonaDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appModel: NekoAppModel
    @State private var isShareOpen = false

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
        ZStack(alignment: .bottom) {
            NekoBackground()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    PersonaTopBar(
                        onBack: { dismiss() },
                        onShare: {
                            withAnimation(.spring(response: 0.24, dampingFraction: 0.9)) {
                                isShareOpen = true
                            }
                        }
                    )

                    PersonaHeroCard(profile: profile, persona: safePersona)

                    PersonaSection(title: "AI 内心独白", hint: "INNER · VOICE", tone: true) {
                        VStack(alignment: .trailing, spacing: 12) {
                            Text(safePersona.monologue)
                                .font(.system(size: 14, weight: .light))
                                .italic()
                                .foregroundStyle(NekoTheme.ink)
                                .multilineTextAlignment(.center)
                                .lineSpacing(7)
                                .padding(.horizontal, 18)
                                .padding(.top, 4)
                                .frame(maxWidth: .infinity)
                                .overlay(alignment: .topLeading) {
                                    Text("“")
                                        .font(.system(size: 34, weight: .regular, design: .serif))
                                        .foregroundStyle(NekoTheme.soulViolet.opacity(0.26))
                                        .offset(x: -4, y: -14)
                                }
                                .overlay(alignment: .bottomTrailing) {
                                    Text("”")
                                        .font(.system(size: 34, weight: .regular, design: .serif))
                                        .foregroundStyle(NekoTheme.soulViolet.opacity(0.26))
                                        .offset(x: 2, y: 14)
                                }

                            Text("—— \(profile.name) · by NEKO")
                                .font(.system(size: 10, weight: .medium))
                                .tracking(2.5)
                                .foregroundStyle(NekoTheme.muted)
                        }
                    }

                    PersonaSection(title: "AI 人格解析", hint: "PERSONALITY · ANALYSIS") {
                        Text(safePersona.analysis)
                            .font(.system(size: 12.5, weight: .regular))
                            .foregroundStyle(NekoTheme.ink.opacity(0.85))
                            .lineSpacing(7)
                    }

                    PersonaSection(title: "它眼中的你", hint: "YOUR · ROLE") {
                        VStack(alignment: .leading, spacing: 12) {
                            Text(safePersona.ownerRole)
                                .font(.system(size: 12.5, weight: .regular))
                                .foregroundStyle(NekoTheme.ink.opacity(0.85))
                                .lineSpacing(7)

                            HStack(spacing: 8) {
                                ForEach(["温柔", "安全感", "可信", "陪伴者"], id: \.self) { chip in
                                    Text(chip)
                                        .font(.system(size: 10, weight: .medium))
                                        .tracking(1.0)
                                        .foregroundStyle(.white)
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 4)
                                        .background(NekoTheme.selectedGradient, in: Capsule())
                                        .shadow(color: NekoTheme.soulViolet.opacity(0.14), radius: 8, x: 0, y: 4)
                                }
                            }
                        }
                    }

                    PersonaSection(title: "个性画像", hint: "PERSONALITY · PORTRAIT") {
                        HStack(spacing: 0) {
                            ForEach(displayTraits) { trait in
                                PersonaTraitRing(trait: trait)
                            }
                        }
                    }

                    PersonaSection(
                        title: "人格标签",
                        hint: "TAGS · 06",
                        actionTitle: "查看全部 ›"
                    ) {
                        FlowChipWrap(items: Array(displayTags.prefix(6)))
                    }

                    PersonaSection(title: "AI 观察依据", hint: "WHY · AI · THINKS · SO") {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("最近 30 天观察")
                                .font(.system(size: 10.5, weight: .regular))
                                .tracking(1.2)
                                .foregroundStyle(NekoTheme.muted)

                            VStack(spacing: 8) {
                                ForEach(displayObservations) { item in
                                    VStack(alignment: .leading, spacing: 6) {
                                        Text(item.label)
                                            .font(.system(size: 10, weight: .regular))
                                            .tracking(2.2)
                                            .foregroundStyle(NekoTheme.muted)

                                        Text(item.value)
                                            .font(.system(size: 12, weight: .medium))
                                            .foregroundStyle(NekoTheme.ink)
                                            .lineSpacing(4)
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 10)
                                    .background(Color.white.opacity(0.55), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                                    .overlay {
                                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                                            .stroke(NekoTheme.softPink.opacity(0.45), lineWidth: 1)
                                    }
                                }
                            }

                            VStack(alignment: .leading, spacing: 8) {
                                Text("AI 发现")
                                    .font(.system(size: 10, weight: .regular))
                                    .tracking(3)
                                    .foregroundStyle(NekoTheme.soulViolet)

                                Text("它更倾向于观察后行动，因此形成明显的观察型人格特征。")
                                    .font(.system(size: 12, weight: .regular))
                                    .foregroundStyle(NekoTheme.ink.opacity(0.85))
                                    .lineSpacing(5)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 12)
                            .background(Color.white.opacity(0.55), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .overlay {
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .stroke(Color.white.opacity(0.72), lineWidth: 1)
                            }
                        }
                    }
                }
                .padding(.bottom, 128)
            }

            if isShareOpen {
                PersonaShareOverlay(
                    onClose: closeShare,
                    onWeChat: {
                        closeShare()
                        appModel.noticeMessage = "正在调起微信，请选择要分享的好友…"
                    },
                    onMoments: {
                        closeShare()
                        appModel.noticeMessage = "正在打开朋友圈发布页…"
                    },
                    onSaveImage: {
                        closeShare()
                        appModel.noticeMessage = "已保存到相册"
                    }
                )
                .transition(.opacity)
            }
        }
        .safeAreaInset(edge: .bottom) {
            PersonaBottomActions(
                onRestart: {
                    dismiss()
                    appModel.startOnboarding()
                },
                onSave: { dismiss() }
            )
        }
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
    }

    private func closeShare() {
        withAnimation(.spring(response: 0.24, dampingFraction: 0.95)) {
            isShareOpen = false
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
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Color(red: 0.56, green: 0.32, blue: 0.62))
                        .frame(width: 36, height: 36)
                        .background(Color.white.opacity(0.80), in: Circle())
                        .shadow(color: NekoTheme.soulViolet.opacity(0.14), radius: 14, x: 0, y: 7)
                }
                .buttonStyle(.plain)

                Text("N E K O · I D")
                    .font(.system(size: 10, weight: .regular))
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
                        .font(.system(size: 15, weight: .light))
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
                            .font(.system(size: 9, weight: .regular))
                            .tracking(3)
                            .foregroundStyle(NekoTheme.muted)
                        Text(persona.mbti)
                            .font(.system(size: 11.5, weight: .medium))
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
            .font(.system(size: 9.5, weight: .regular))
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
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(NekoTheme.ink)

                Text(hint)
                    .font(.system(size: 8, weight: .regular))
                    .tracking(2.4)
                    .foregroundStyle(Color(red: 0.60, green: 0.40, blue: 0.64))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: 8)

                if let actionTitle {
                    Button(actionTitle) {
                        action?()
                    }
                    .font(.system(size: 10, weight: .regular))
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
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(NekoTheme.ink)
                        .tracking(-0.5)

                    Text(trait.icon)
                        .font(.system(size: 11))
                }
            }
            .frame(width: 72, height: 72)

            Text(trait.label)
                .font(.system(size: 11, weight: .regular))
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
            CatAvatarView(localImage: nil, remoteURL: profile.avatarURL, size: 100)
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
                        .font(.system(size: 9.5, weight: .regular))
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
                    .font(.system(size: 11, weight: .regular))
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
                .font(.system(size: 13, weight: .medium))
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
                .font(.system(size: 13, weight: .medium))
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
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(NekoTheme.ink)
                    .padding(.top, 16)

                HStack(spacing: 0) {
                    PersonaShareItem(label: "微信好友", emoji: "💬", colors: [Color(red: 0.420, green: 0.831, blue: 0.420), Color(red: 0.169, green: 0.722, blue: 0.361)], action: onWeChat)
                    PersonaShareItem(label: "朋友圈", emoji: "🌈", colors: [Color(red: 1.000, green: 0.702, blue: 0.420), Color(red: 1.000, green: 0.420, blue: 0.710)], action: onMoments)
                    PersonaShareItem(label: "保存图片", emoji: "⬇️", colors: [NekoTheme.soulViolet, NekoTheme.soulPink], action: onSaveImage)
                }
                .padding(.top, 20)

                Button("取消", action: onClose)
                    .font(.system(size: 13, weight: .medium))
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
                    .font(.system(size: 11.5, weight: .regular))
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
    @State private var generatedVoice: CatVoiceResult?
    @State private var isPublishing = false

    var body: some View {
        NavigationStack {
            ZStack {
                NekoBackground()

                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("PUBLISH VOICE")
                                .font(.system(size: 10, weight: .semibold))
                                .tracking(4.3)
                                .foregroundStyle(NekoTheme.soulViolet)

                            Text("发一条猫咪动态")
                                .font(.system(size: 28, weight: .light))
                                .foregroundStyle(NekoTheme.ink)

                            Text("选一张当下照片，NEKO 会生成猫咪第一人称心声，并保存到云端动态。")
                                .font(.system(size: 12.5))
                                .foregroundStyle(NekoTheme.muted)
                                .lineSpacing(4)
                        }

                        PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 24, style: .continuous)
                                    .fill(NekoTheme.tintGradient)

                                if let photoPreviewImage {
                                    Image(uiImage: photoPreviewImage)
                                        .resizable()
                                        .scaledToFill()
                                } else {
                                    VStack(spacing: 10) {
                                        Image(systemName: "photo.badge.plus")
                                            .font(.system(size: 38, weight: .semibold))
                                            .foregroundStyle(NekoTheme.soulViolet)
                                        Text("选择动态照片")
                                            .font(.system(size: 14, weight: .semibold))
                                            .foregroundStyle(NekoTheme.ink)
                                        Text("图片不超过 10MB，会用于生成猫咪心声")
                                            .font(.system(size: 12))
                                            .foregroundStyle(NekoTheme.muted)
                                    }
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .frame(height: 260)
                            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                            .overlay {
                                RoundedRectangle(cornerRadius: 24, style: .continuous)
                                    .stroke(.white.opacity(0.72), lineWidth: 1)
                            }
                            .shadow(color: NekoTheme.soulViolet.opacity(0.16), radius: 28, x: 0, y: 14)
                        }
                        .disabled(isPublishing)

                        NekoGlassCard(cornerRadius: 24) {
                            VStack(alignment: .leading, spacing: 10) {
                                FieldTitle("补充场景")
                                TextField("例如：它趴在窗边看风", text: $scene, axis: .vertical)
                                    .lineLimit(3, reservesSpace: true)
                                    .textInputAutocapitalization(.never)
                                    .font(.system(size: 14))
                                    .foregroundStyle(NekoTheme.ink)
                                    .padding(16)
                                    .background(NekoTheme.field, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                            }
                            .padding(16)
                        }

                        Button {
                            Task { await publishVoice() }
                        } label: {
                            HStack(spacing: 8) {
                                if isPublishing {
                                    ProgressView()
                                        .tint(.white)
                                }
                                Label(isPublishing ? "生成并发布中…" : "生成并发布", systemImage: "sparkles")
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(NekoPrimaryButtonStyle())
                        .disabled(isPublishing || photoData == nil)

                        if let generatedVoice {
                            VoicePreviewCard(voice: generatedVoice)
                        }
                    }
                    .padding(24)
                    .padding(.bottom, 32)
                }
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(generatedVoice == nil ? "关闭" : "完成") {
                        dismiss()
                    }
                    .foregroundStyle(NekoTheme.soulViolet)
                }
            }
        }
        .preferredColorScheme(.light)
        .onChange(of: selectedPhotoItem) { _, item in
            Task { await loadPhoto(from: item) }
        }
    }

    @MainActor
    private func loadPhoto(from item: PhotosPickerItem?) async {
        guard let item else { return }

        do {
            guard let data = try await item.loadTransferable(type: Data.self) else {
                throw NekoMediaError.unsupportedImage
            }
            let prepared = try MediaUploadProcessor.prepareAvatarImage(from: data)
            photoData = prepared.data
            photoPreviewImage = UIImage(data: prepared.data)
            generatedVoice = nil
        } catch {
            appModel.errorMessage = userFacingMessage(error)
        }
    }

    @MainActor
    private func publishVoice() async {
        guard let photoData else {
            appModel.errorMessage = "先选择一张猫咪动态照片吧。"
            return
        }
        guard !isPublishing else { return }

        isPublishing = true
        defer { isPublishing = false }

        do {
            let voice = try await appModel.publishCatVoice(imageData: photoData, scene: scene)
            generatedVoice = voice
            latestPublishedVoice = voice
        } catch {
            appModel.errorMessage = userFacingMessage(error)
        }
    }

    private func userFacingMessage(_ error: Error) -> String {
        if let description = (error as? LocalizedError)?.errorDescription, !description.isEmpty {
            return description
        }
        return "动态发布失败，请稍后再试。"
    }
}

private struct VoicePreviewCard: View {
    let voice: CatVoiceResult

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("已发布")
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(3)
                    .foregroundStyle(NekoTheme.soulViolet)
                Spacer()
                Text(voice.time)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(NekoTheme.muted)
            }

            Text("“\(voice.text)”")
                .font(.system(size: 17, weight: .light))
                .lineSpacing(6)
                .foregroundStyle(NekoTheme.ink)

            if let analysis = voice.analysis, !analysis.isEmpty {
                Text(analysis)
                    .font(.system(size: 13))
                    .foregroundStyle(NekoTheme.muted)
                    .lineSpacing(5)
            }

            if !voice.tags.isEmpty {
                HStack {
                    ForEach(voice.tags.prefix(3), id: \.self) { tag in
                        Text(tag)
                            .font(.system(size: 11, weight: .medium))
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
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(NekoTheme.muted)
                Text("“\(voice.text)”")
                    .font(.system(size: 14, weight: .medium))
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
    let size: CGFloat

    var body: some View {
        ZStack {
            Circle()
                .fill(Color.white.opacity(0.78))

            if let localImage {
                Image(uiImage: localImage)
                    .resizable()
                    .scaledToFill()
            } else if let remoteURL {
                AsyncImage(url: remoteURL) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                    default:
                        fallback
                    }
                }
            } else {
                fallback
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
            .font(.system(size: 11, weight: .semibold))
            .tracking(2)
            .foregroundStyle(NekoTheme.muted)
    }
}

private struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 15, weight: .semibold))
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
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(NekoTheme.ink)
            .padding(.vertical, 15)
            .background(.white.opacity(configuration.isPressed ? 0.62 : 0.82), in: Capsule())
    }
}

#Preview {
    ContentView()
        .environmentObject(NekoAppModel())
}
