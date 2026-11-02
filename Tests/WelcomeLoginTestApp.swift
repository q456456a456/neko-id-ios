import SwiftUI
import UIKit

// Appended to OnboardingFlowView.swift only in the isolated test build, so these
// checks use the real welcome component without exposing it in the app module.
@main
struct WelcomeLoginTestApp: App {
    @StateObject private var model = NekoAppModel()
    @State private var checksCompleted = false

    var body: some Scene {
        WindowGroup {
            Group {
                if checksCompleted {
                    ContentView().environmentObject(model)
                } else {
                    Color.clear
                }
            }
            .task {
                guard !checksCompleted else { return }
                // Run fixtures before the interactive root can restore a
                // leftover test session and race the network assertions.
                await WelcomeLoginChecks.run()
                checksCompleted = true
            }
        }
    }
}

// Intercept every request: this fixture must never send SMS or reach production.
final class WelcomeLoginMockProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var hasProfile = true
    nonisolated(unsafe) static var rejectsCode = false
    nonisolated(unsafe) static var paths: [String] = []

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let path = request.url!.path
        Self.paths.append(path)
        let payload: String
        var status = 200
        switch path {
        case "/api/ios/auth/phone-otp":
            payload = #"{"ok":true,"data":{"sent":true}}"#
        case "/api/ios/auth/phone-verify":
            if Self.rejectsCode {
                status = 400
                payload = #"{"ok":false,"error":{"message":"验证码错误，请重新输入"}}"#
            } else {
                payload = #"{"ok":true,"data":{"accessToken":"fixture-access","refreshToken":"fixture-refresh","expiresAt":"2099-01-01T00:00:00Z","user":{"id":"fixture-user","phone":"8613800000000"}}}"#
            }
        case "/api/ios/cloud/state":
            let profile = Self.hasProfile
                ? #"{"id":"fixture-cat","name":"测试猫咪","gender":"小公猫","ageStage":"青年猫"}"#
                : "null"
            payload = "{\"ok\":true,\"data\":{\"profile\":\(profile),\"persona\":null,\"voices\":[]}}"
        case "/api/ios/cloud/voices":
            payload = #"{"ok":true,"data":[]}"#
        default:
            status = 500
            payload = #"{"ok":false,"error":{"message":"Unexpected fixture request"}}"#
        }
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: status,
            httpVersion: nil, headerFields: ["Content-Type": "application/json"])!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(payload.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

@MainActor
private enum WelcomeLoginChecks {
    static func snapshotRoot(model: NekoAppModel, label: String, directory: URL) async {
        for size in [CGSize(width: 320, height: 568), CGSize(width: 375, height: 667),
                     CGSize(width: 393, height: 852), CGSize(width: 430, height: 932)] {
            let controller = UIHostingController(rootView: ContentView()
                .environmentObject(model).preferredColorScheme(.light))
            let window = UIWindow(frame: CGRect(origin: .zero, size: size))
            window.rootViewController = controller
            window.isHidden = false
            controller.view.frame = window.bounds
            controller.view.layoutIfNeeded()
            try? await Task.sleep(for: .milliseconds(350))
            controller.view.layoutIfNeeded()
            let image = UIGraphicsImageRenderer(bounds: controller.view.bounds).image { _ in
                controller.view.drawHierarchy(in: controller.view.bounds, afterScreenUpdates: true)
            }
            try! image.pngData()!.write(to: directory.appendingPathComponent("\(label)-\(Int(size.width)).png"))
            window.isHidden = true
        }
    }

    static func snapshot(width: CGFloat, height: CGFloat, showLogin: Bool, directory: URL) async {
        let content = OnboardingWelcomeScreen(onExit: nil, onLogin: showLogin ? {} : nil, onStart: {})
            .preferredColorScheme(.light)
        let controller = UIHostingController(rootView: content)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: width, height: height))
        window.rootViewController = controller
        window.isHidden = false
        controller.view.frame = window.bounds
        controller.view.layoutIfNeeded()
        try? await Task.sleep(for: .milliseconds(200))
        let image = UIGraphicsImageRenderer(bounds: controller.view.bounds).image { _ in
            controller.view.drawHierarchy(in: controller.view.bounds, afterScreenUpdates: true)
        }
        let suffix = showLogin ? "login" : "baseline"
        try! image.pngData()!.write(to: directory.appendingPathComponent("welcome-\(Int(width))-\(suffix).png"))
        window.isHidden = true
    }

    static func run() async {
        let run = ProcessInfo.processInfo.environment["NEKO_LOGIN_RUN"] ?? "latest"
        let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("login-checks-\(run)")
        try! FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let model = NekoAppModel()
        model.signOut()
        await model.bootstrap()
        precondition(model.phase == .onboarding && model.session == nil)
        precondition(WelcomeLoginMockProtocol.paths.isEmpty, "Welcome must not require an API call")

        WelcomeLoginMockProtocol.rejectsCode = true
        let rejected = await model.verifyLoginCode(phone: "13800000000", code: "000000")
        precondition(!rejected && model.session == nil && model.phase == .onboarding)

        WelcomeLoginMockProtocol.rejectsCode = false
        let existing = await model.verifyLoginCode(phone: "13800000000", code: "123456", reloadCloudStateAfterLogin: true)
        precondition(existing && model.phase == .home && model.catProfile?.name == "测试猫咪")
        precondition(model.loginPrompt == nil)
        precondition(model.requestVoiceGeneration() && !model.isProfileRequiredPromptPresented,
                     "An existing profile must still open voice generation")
        await snapshotRoot(model: model, label: "home-existing", directory: directory)

        model.signOut()
        WelcomeLoginMockProtocol.hasProfile = false
        let emptyAccount = await model.verifyLoginCode(phone: "13800000000", code: "123456", reloadCloudStateAfterLogin: true)
        precondition(emptyAccount && model.phase == .home && model.session != nil && model.catProfile == nil)
        await snapshotRoot(model: model, label: "home-empty", directory: directory)

        // Both accounts have no voice entries or avatar: missing a profile must
        // reuse the original heart-voice empty state, not a separate design.
        for width in [320, 375, 393, 430] {
            let original = try! Data(contentsOf: directory.appendingPathComponent("home-existing-\(width).png"))
            let withoutProfile = try! Data(contentsOf: directory.appendingPathComponent("home-empty-\(width).png"))
            precondition(original == withoutProfile,
                         "Home without a profile must match the original voice empty state at \(width)pt")
        }

        let restored = NekoAppModel()
        await restored.bootstrap()
        precondition(restored.phase == .home && restored.session != nil && restored.catProfile == nil,
                     "A saved session without a profile must also enter home")

        let requestsBeforeGate = WelcomeLoginMockProtocol.paths.count
        precondition(!model.requestVoiceGeneration() && model.isProfileRequiredPromptPresented)
        precondition(model.phase == .home && model.session != nil)
        await snapshotRoot(model: model, label: "profile-required", directory: directory)
        model.isProfileRequiredPromptPresented = false
        precondition(model.phase == .home && model.session != nil,
                     "Cancelling the profile prompt must keep the user at home")
        precondition(!model.requestVoiceGeneration())
        model.startOnboarding()
        precondition(model.phase == .onboarding && !model.isProfileRequiredPromptPresented)
        await snapshotRoot(model: model, label: "onboarding-can-return", directory: directory)
        model.cancelOnboardingIfPossible()
        precondition(model.phase == .home && model.session != nil && model.catProfile == nil,
                     "Logged-in users can leave onboarding even without a profile")
        do {
            _ = try await model.generateCatVoicePreview(imageData: Data(), scene: "fixture")
            preconditionFailure("Missing profile must not reach generation")
        } catch NekoAppError.missingCatProfile {
            precondition(model.phase == .home)
        } catch {
            preconditionFailure("Unexpected error: \(error)")
        }
        do {
            let voice = CatVoiceResult(time: "刚刚", grad: "", text: "fixture")
            _ = try await model.saveGeneratedCatVoice(voice, imageData: Data())
            preconditionFailure("Missing profile must not reach publishing")
        } catch NekoAppError.missingCatProfile {
            precondition(model.phase == .home)
        } catch {
            preconditionFailure("Unexpected error: \(error)")
        }
        precondition(WelcomeLoginMockProtocol.paths.count == requestsBeforeGate,
                     "A missing profile must not send generation or upload requests")

        WelcomeLoginMockProtocol.hasProfile = true
        let withProfile = await model.verifyLoginCode(phone: "13800000000", code: "123456")
        precondition(withProfile && model.requestVoiceGeneration() && !model.isProfileRequiredPromptPresented,
                     "Loading a newly created profile must remove the generation restriction")

        model.signOut()
        WelcomeLoginMockProtocol.hasProfile = true
        let requestCount = WelcomeLoginMockProtocol.paths.count
        model.requestLogin(message: "保存档案")
        let saveFlow = await model.verifyLoginCode(phone: "13800000000", code: "123456", reloadCloudStateAfterLogin: false)
        precondition(saveFlow && model.phase == .onboarding && model.catProfile == nil)
        precondition(WelcomeLoginMockProtocol.paths.count == requestCount + 1,
                     "Save-result login must not navigate away before saving")
        precondition(!model.requestVoiceGeneration() && model.isProfileRequiredPromptPresented)
        model.signOut()
        precondition(!model.isProfileRequiredPromptPresented)
        model.cancelOnboardingIfPossible()
        precondition(model.phase == .onboarding && model.session == nil,
                     "Guests must retain their existing welcome flow")

        for size in [CGSize(width: 320, height: 568), CGSize(width: 375, height: 667),
                     CGSize(width: 393, height: 852), CGSize(width: 430, height: 932)] {
            await snapshot(width: size.width, height: size.height, showLogin: false, directory: directory)
            await snapshot(width: size.width, height: size.height, showLogin: true, directory: directory)
        }
        let report = """
        PASS: signed-out welcome needs no API request.
        PASS: invalid OTP cannot authenticate or enter home.
        PASS: existing account restores its profile and enters home.
        PASS: login and saved-session restoration without a profile enter home.
        PASS: missing-profile home matches the original heart-voice empty state at all four widths.
        PASS: missing profile blocks generation and presents a cancellable prompt.
        PASS: confirm enters onboarding; authenticated users can return home.
        PASS: missing-profile generation/publish guards send no requests and stay home.
        PASS: loading a profile unlocks generation.
        PASS: save-result login retains its separate no-reload behavior.
        PASS: sign-out clears the prompt and retains the guest welcome flow.
        CAPTURE: home, prompt and onboarding at 320, 375, 393 and 430 pt widths.
        Interactive fixture ready: all network requests are mocked.
        """
        try! report.write(to: directory.appendingPathComponent("welcome-login-checks.txt"), atomically: true, encoding: .utf8)
    }
}
