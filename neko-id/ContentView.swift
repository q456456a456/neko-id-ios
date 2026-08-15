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

private struct NekoBackground: View {
    var body: some View {
        LinearGradient(
            colors: [
                Color(red: 1.00, green: 0.98, blue: 0.92),
                Color(red: 0.99, green: 0.93, blue: 0.98),
                Color(red: 0.95, green: 0.91, blue: 1.00),
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea()
    }
}

private struct LaunchingView: View {
    var body: some View {
        VStack(spacing: 16) {
            ProgressView()
                .tint(.pink)

            Text("正在寻找你的猫咪档案…")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .padding(24)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
    }
}

private struct LoginView: View {
    @EnvironmentObject private var appModel: NekoAppModel
    @State private var email = ""
    @State private var code = ""
    @State private var codeSent = false

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Spacer(minLength: 36)

            VStack(alignment: .leading, spacing: 8) {
                Text("NEKO.ID")
                    .font(.system(size: 12, weight: .semibold))
                    .tracking(5)
                    .foregroundStyle(.pink)

                Text("邮箱验证码登录")
                    .font(.system(size: 32, weight: .light))

                Text("登录后，猫咪档案会同步到 Supabase，并在这台设备上安全保存登录态。")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                    .lineSpacing(4)
            }

            VStack(spacing: 14) {
                TextField("you@example.com", text: $email)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.emailAddress)
                    .textContentType(.emailAddress)
                    .autocorrectionDisabled()
                    .padding()
                    .background(.white.opacity(0.72), in: RoundedRectangle(cornerRadius: 18, style: .continuous))

                Button {
                    codeSent = true
                    Task { await appModel.requestLoginCode(email: email) }
                } label: {
                    Label(codeSent ? "重新发送验证码" : "发送验证码", systemImage: "envelope")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(appModel.isBusy || email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                if codeSent {
                    TextField("6 位验证码", text: $code)
                        .keyboardType(.numberPad)
                        .textContentType(.oneTimeCode)
                        .multilineTextAlignment(.center)
                        .font(.system(size: 22, weight: .semibold, design: .rounded))
                        .tracking(8)
                        .padding()
                        .background(.white.opacity(0.72), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .onChange(of: code) { _, newValue in
                            code = String(newValue.filter(\.isNumber).prefix(6))
                        }

                    Button {
                        Task { await appModel.verifyLoginCode(email: email, code: code) }
                    } label: {
                        Label("完成登录", systemImage: "checkmark.circle")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(appModel.isBusy || code.count != 6)
                }
            }

            Spacer()
        }
        .padding(28)
        .overlay(alignment: .center) {
            if appModel.isBusy {
                ProgressView()
                    .tint(.pink)
                    .padding(18)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
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
                        .foregroundStyle(.pink)

                    Text("创建猫咪人格档案")
                        .font(.system(size: 30, weight: .light))

                    Text("先建立基础档案。照片、视频和 AI 人格生成会继续原生化接入。")
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                        .lineSpacing(4)
                }

                VStack(alignment: .leading, spacing: 16) {
                    PhotosPicker(selection: $selectedAvatarItem, matching: .images) {
                        HStack(spacing: 16) {
                            CatAvatarView(localImage: avatarPreviewImage, remoteURL: nil, size: 76)

                            VStack(alignment: .leading, spacing: 6) {
                                Text(avatarPreviewImage == nil ? "选择猫咪照片" : "更换猫咪照片")
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundStyle(.primary)

                                Text("会作为头像上传到私有云端，单张不超过 10MB。")
                                    .font(.system(size: 12))
                                    .foregroundStyle(.secondary)
                                    .multilineTextAlignment(.leading)
                            }

                            Spacer()

                            Image(systemName: "photo.badge.plus")
                                .font(.system(size: 20, weight: .semibold))
                                .foregroundStyle(.pink)
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
                .foregroundStyle(.secondary)
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
                    .tint(.pink)
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
    @State private var selectedAvatarItem: PhotosPickerItem?

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 8) {
                Text("NEKO HOME")
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(4)
                    .foregroundStyle(.pink)

                Text(appModel.catProfile?.name ?? "我的猫咪")
                    .font(.system(size: 34, weight: .light))

                Text(appModel.persona?.dailyMood ?? "原生 App 已连接 Supabase。下一步会把 AI 生成人格和心声发布接进来。")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                    .lineSpacing(4)
            }

            if let profile = appModel.catProfile {
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        CatAvatarView(localImage: nil, remoteURL: profile.avatarURL, size: 58)

                        VStack(alignment: .leading) {
                            Text(profile.name)
                                .font(.system(size: 20, weight: .semibold))
                            Text(appModel.persona?.type ?? "\(profile.gender.rawValue) · \(profile.ageStage.rawValue)")
                                .font(.system(size: 13))
                                .foregroundStyle(.secondary)
                        }

                        Spacer()
                    }

                    Text("档案 ID：\(profile.id)")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .padding(18)
                .background(.white.opacity(0.58), in: RoundedRectangle(cornerRadius: 26, style: .continuous))

                PhotosPicker(selection: $selectedAvatarItem, matching: .images) {
                    Label("更新猫咪头像", systemImage: "photo")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(SecondaryButtonStyle())
            }

            Spacer()

            Button {
                appModel.startOnboarding()
            } label: {
                Label("重新创建档案", systemImage: "sparkles")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(SecondaryButtonStyle())

            Button("退出登录") {
                appModel.signOut()
            }
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity)
        }
        .padding(28)
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

private struct CatAvatarView: View {
    let localImage: UIImage?
    let remoteURL: URL?
    let size: CGFloat

    var body: some View {
        ZStack {
            Circle()
                .fill(.white.opacity(0.72))

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
        .shadow(color: .pink.opacity(0.14), radius: 16, x: 0, y: 8)
    }

    private var fallback: some View {
        Image(systemName: "pawprint.fill")
            .font(.system(size: size * 0.36, weight: .semibold))
            .foregroundStyle(.pink)
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
            .foregroundStyle(.secondary)
    }
}

private struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.vertical, 15)
            .background(
                LinearGradient(
                    colors: [Color.purple.opacity(0.75), Color.pink.opacity(0.78)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                in: Capsule()
            )
            .opacity(configuration.isPressed ? 0.78 : 1)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
    }
}

private struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(.primary)
            .padding(.vertical, 15)
            .background(.white.opacity(configuration.isPressed ? 0.62 : 0.82), in: Capsule())
    }
}

#Preview {
    ContentView()
        .environmentObject(NekoAppModel())
}
