import AVFoundation
import Combine
import PhotosUI
import SwiftUI
import UIKit

struct NekoCameraView: View {
    let onClose: () -> Void
    let onUsePhoto: (UIImage) -> Void
    let guidanceText: String

    @StateObject private var camera = NekoCameraController()
    @State private var capturedImage: UIImage?
    @State private var recentImage: UIImage?
    @State private var showsPhotoLibrary = false

    init(
        guidanceText: String = "请拍摄猫咪清晰正脸",
        recentImage: UIImage? = nil,
        onClose: @escaping () -> Void,
        onUsePhoto: @escaping (UIImage) -> Void
    ) {
        self.guidanceText = guidanceText
        self.onClose = onClose
        self.onUsePhoto = onUsePhoto
        _recentImage = State(initialValue: recentImage)
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if let capturedImage {
                Image(uiImage: capturedImage)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.black)
                    .ignoresSafeArea()
            } else if camera.authorizationDenied {
                cameraUnavailableView
            } else {
                NekoCameraPreview(session: camera.session)
                    .ignoresSafeArea()

                LinearGradient(
                    colors: [.black.opacity(0.42), .clear, .black.opacity(0.58)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()
                .allowsHitTesting(false)
            }

            VStack(spacing: 0) {
                topBar
                Spacer()
                if capturedImage == nil, !camera.authorizationDenied {
                    Text(guidanceText)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.white.opacity(0.88))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(.black.opacity(0.22), in: Capsule())
                        .padding(.bottom, 18)
                }
                bottomControls
            }
            .padding(.horizontal, 22)
            .padding(.top, 8)
            .padding(.bottom, 14)
        }
        .statusBarHidden()
        .onAppear {
            camera.onPhotoCaptured = { image in
                capturedImage = image
                recentImage = image
            }
            camera.start()
        }
        .onDisappear {
            camera.stop()
        }
        .fullScreenCover(isPresented: $showsPhotoLibrary) {
            NekoPhotoLibraryPicker(
                onCancel: {
                    showsPhotoLibrary = false
                },
                onConfirm: { image in
                    recentImage = image
                    capturedImage = image
                    camera.stop()
                    showsPhotoLibrary = false
                }
            )
        }
    }

    private var topBar: some View {
        HStack {
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 42, height: 42)
                    .background(.black.opacity(0.30), in: Circle())
                    .overlay { Circle().stroke(.white.opacity(0.22), lineWidth: 1) }
            }
            .accessibilityLabel("关闭相机")

            Spacer()

            Text("NEKO.ID")
                .font(.system(size: 10, weight: .semibold))
                .tracking(4.2)
                .foregroundStyle(.white.opacity(0.88))

            Spacer()

            Color.clear.frame(width: 42, height: 42)
        }
    }

    @ViewBuilder
    private var bottomControls: some View {
        if let capturedImage {
            HStack(spacing: 12) {
                Button {
                    self.capturedImage = nil
                    camera.start()
                } label: {
                    Text("重拍")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(NekoCameraSecondaryButtonStyle())

                Button {
                    onUsePhoto(capturedImage)
                } label: {
                    Text("使用照片")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(NekoCameraPrimaryButtonStyle())
            }
            .padding(.bottom, 8)
        } else if !camera.authorizationDenied {
            HStack {
                Button {
                    showsPhotoLibrary = true
                } label: {
                    Group {
                        if let recentImage {
                            Image(uiImage: recentImage)
                                .resizable()
                                .scaledToFill()
                        } else {
                            Image(systemName: "photo.on.rectangle")
                                .font(.system(size: 19, weight: .medium))
                                .foregroundStyle(.white)
                        }
                    }
                    .frame(width: 48, height: 48)
                    .background(.white.opacity(0.14))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(.white.opacity(0.78), lineWidth: 1.5)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("从照片图库选择")

                Spacer()

                Button {
                    camera.capturePhoto()
                } label: {
                    ZStack {
                        Circle()
                            .stroke(.white, lineWidth: 5)
                            .frame(width: 78, height: 78)
                        Circle()
                            .fill(.white)
                            .frame(width: 64, height: 64)
                            .shadow(color: NekoTheme.soulPink.opacity(0.34), radius: 14)
                    }
                }
                .disabled(!camera.isReady || camera.isCapturing)
                .opacity(camera.isReady ? 1 : 0.55)
                .accessibilityLabel("拍照")

                Spacer()

                Button {
                    camera.switchCamera()
                } label: {
                    Image(systemName: "camera.rotate.fill")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundStyle(.white)
                        .frame(width: 48, height: 48)
                        .background(.black.opacity(0.30), in: Circle())
                        .overlay { Circle().stroke(.white.opacity(0.22), lineWidth: 1) }
                }
                .disabled(!camera.isReady)
                .accessibilityLabel("切换前后摄像头")
            }
            .frame(height: 88)
        }
    }

    private var cameraUnavailableView: some View {
        VStack(spacing: 14) {
            Image(systemName: "camera.fill")
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(NekoTheme.soulViolet)
            Text("需要相机权限")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(NekoTheme.ink)
            Text("请在系统设置中允许 NEKO.ID 使用相机，或从照片图库选择猫咪照片。")
                .font(.system(size: 13))
                .foregroundStyle(NekoTheme.muted)
                .multilineTextAlignment(.center)
                .lineSpacing(4)
            Button("打开系统设置") {
                guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                UIApplication.shared.open(url)
            }
            .buttonStyle(NekoCameraPrimaryButtonStyle())
            Button("从照片图库选择") {
                showsPhotoLibrary = true
            }
            .foregroundStyle(NekoTheme.soulViolet)
        }
        .padding(28)
        .background(NekoTheme.backgroundGradient, in: RoundedRectangle(cornerRadius: 30, style: .continuous))
        .padding(24)
    }

}

private struct NekoPhotoLibraryPicker: UIViewControllerRepresentable {
    let onCancel: () -> Void
    let onConfirm: (UIImage) -> Void

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var configuration = PHPickerConfiguration(photoLibrary: .shared())
        configuration.filter = .images
        configuration.selectionLimit = 1
        configuration.preferredAssetRepresentationMode = .current

        let picker = PHPickerViewController(configuration: configuration)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onCancel: onCancel, onConfirm: onConfirm)
    }

    final class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let onCancel: () -> Void
        let onConfirm: (UIImage) -> Void

        init(onCancel: @escaping () -> Void, onConfirm: @escaping (UIImage) -> Void) {
            self.onCancel = onCancel
            self.onConfirm = onConfirm
        }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            guard let provider = results.first?.itemProvider else {
                onCancel()
                return
            }

            provider.loadObject(ofClass: UIImage.self) { [onConfirm, onCancel] object, _ in
                DispatchQueue.main.async {
                    guard let image = object as? UIImage else {
                        onCancel()
                        return
                    }
                    onConfirm(image)
                }
            }
        }
    }
}

private struct NekoCameraPreview: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {
        uiView.previewLayer.session = session
    }

    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    }
}

private final class NekoCameraController: NSObject, ObservableObject, AVCapturePhotoCaptureDelegate {
    let session = AVCaptureSession()
    @Published private(set) var isReady = false
    @Published private(set) var isCapturing = false
    @Published private(set) var authorizationDenied = false
    var onPhotoCaptured: ((UIImage) -> Void)?

    private let sessionQueue = DispatchQueue(label: "uk.nekoid.camera.session", qos: .userInitiated)
    private let photoOutput = AVCapturePhotoOutput()
    private var currentPosition: AVCaptureDevice.Position = .back
    private var isConfigured = false

    func start() {
        Task {
            let granted = await requestCameraAccess()
            guard granted else {
                authorizationDenied = true
                return
            }
            authorizationDenied = false
            configureAndStartSession()
        }
    }

    func stop() {
        sessionQueue.async { [session] in
            if session.isRunning { session.stopRunning() }
        }
    }

    func capturePhoto() {
        guard isReady, !isCapturing else { return }
        isCapturing = true
        let settings = AVCapturePhotoSettings()
        settings.flashMode = .off
        settings.photoQualityPrioritization = .quality
        photoOutput.capturePhoto(with: settings, delegate: self)
    }

    func switchCamera() {
        guard isReady else { return }
        currentPosition = currentPosition == .back ? .front : .back
        isReady = false
        sessionQueue.async { [weak self] in
            self?.replaceVideoInput()
        }
    }

    private func requestCameraAccess() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            return true
        case .notDetermined:
            return await AVCaptureDevice.requestAccess(for: .video)
        default:
            return false
        }
    }

    private func configureAndStartSession() {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            if !self.isConfigured {
                self.session.beginConfiguration()
                self.session.sessionPreset = .photo
                self.replaceVideoInput(commitConfiguration: false)
                if self.session.canAddOutput(self.photoOutput) {
                    self.session.addOutput(self.photoOutput)
                    self.photoOutput.maxPhotoQualityPrioritization = .quality
                }
                self.session.commitConfiguration()
                self.isConfigured = true
            }
            if !self.session.isRunning { self.session.startRunning() }
            Task { @MainActor in self.isReady = true }
        }
    }

    private func replaceVideoInput(commitConfiguration: Bool = true) {
        if commitConfiguration { session.beginConfiguration() }
        defer {
            if commitConfiguration { session.commitConfiguration() }
            Task { @MainActor in self.isReady = true }
        }

        session.inputs.forEach { input in
            if input is AVCaptureDeviceInput { session.removeInput(input) }
        }

        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: currentPosition),
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input) else { return }
        session.addInput(input)
    }

    func photoOutput(
        _ output: AVCapturePhotoOutput,
        didFinishProcessingPhoto photo: AVCapturePhoto,
        error: Error?
    ) {
        defer { isCapturing = false }
        guard error == nil,
              let data = photo.fileDataRepresentation(),
              let image = UIImage(data: data) else { return }
        sessionQueue.async { [session] in
            if session.isRunning { session.stopRunning() }
        }
        onPhotoCaptured?(image)
    }
}

private struct NekoCameraPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.vertical, 15)
            .padding(.horizontal, 18)
            .background(NekoTheme.primaryGradient, in: Capsule())
            .opacity(configuration.isPressed ? 0.84 : 1)
    }
}

private struct NekoCameraSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.vertical, 15)
            .padding(.horizontal, 18)
            .background(.black.opacity(configuration.isPressed ? 0.44 : 0.28), in: Capsule())
            .overlay { Capsule().stroke(.white.opacity(0.46), lineWidth: 1) }
    }
}
