import AVFoundation
import Combine
import Photos
import SwiftUI
import UIKit

struct NekoCameraView: View {
    let onClose: () -> Void
    let onUsePhoto: (UIImage) -> Void

    @StateObject private var camera = NekoCameraController()
    @State private var capturedImage: UIImage?
    @State private var recentImage: UIImage?
    @State private var showsPhotoLibrary = false

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
                    Text("请拍摄猫咪清晰正脸")
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
            loadRecentPhotoThumbnail()
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

    private func loadRecentPhotoThumbnail() {
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        if status == .notDetermined {
            PHPhotoLibrary.requestAuthorization(for: .readWrite) { newStatus in
                guard newStatus == .authorized || newStatus == .limited else { return }
                Task { @MainActor in loadRecentPhotoThumbnail() }
            }
            return
        }
        guard status == .authorized || status == .limited else { return }

        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        options.fetchLimit = 1
        guard let asset = PHAsset.fetchAssets(with: .image, options: options).firstObject else { return }

        let requestOptions = PHImageRequestOptions()
        requestOptions.deliveryMode = .opportunistic
        requestOptions.resizeMode = .fast
        PHImageManager.default().requestImage(
            for: asset,
            targetSize: CGSize(width: 160, height: 160),
            contentMode: .aspectFill,
            options: requestOptions
        ) { image, _ in
            guard let image else { return }
            Task { @MainActor in recentImage = image }
        }
    }

}

private struct NekoPhotoLibraryPicker: View {
    let onCancel: () -> Void
    let onConfirm: (UIImage) -> Void

    @StateObject private var library = NekoPhotoLibraryStore()
    @State private var selectedAssetID: String?
    @State private var isLoadingSelection = false

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 2), count: 3)

    var body: some View {
        VStack(spacing: 0) {
            header

            Group {
                if library.canReadPhotos {
                    if library.assets.isEmpty {
                        emptyState
                    } else {
                        assetGrid
                    }
                } else {
                    permissionState
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Color.white.ignoresSafeArea())
        .task {
            library.requestAccessAndLoad()
        }
    }

    private var header: some View {
        HStack(spacing: 14) {
            Button(action: onCancel) {
                Image(systemName: "xmark")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(Color.black.opacity(0.86))
                    .frame(width: 48, height: 48)
                    .background(.white, in: Circle())
                    .shadow(color: .black.opacity(0.06), radius: 18, x: 0, y: 8)
            }
            .accessibilityLabel("取消")

            Spacer()

            Text("选择照片")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Color.black.opacity(0.88))

            Spacer()

            Button {
                Task { await confirmSelection() }
            } label: {
                Text(isLoadingSelection ? "处理中" : "确认")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(selectedAssetID == nil ? Color.black.opacity(0.28) : NekoTheme.soulViolet)
                    .frame(width: 58, height: 40)
                    .background(.white, in: Capsule())
                    .shadow(color: .black.opacity(0.04), radius: 12, x: 0, y: 6)
            }
            .disabled(selectedAssetID == nil || isLoadingSelection)
            .accessibilityLabel("确认选择照片")
        }
        .padding(.horizontal, 22)
        .padding(.top, 18)
        .padding(.bottom, 16)
        .background(Color.white)
    }

    private var assetGrid: some View {
        ScrollView(showsIndicators: false) {
            LazyVGrid(columns: columns, spacing: 2) {
                ForEach(library.assets, id: \.localIdentifier) { asset in
                    Button {
                        selectedAssetID = asset.localIdentifier
                    } label: {
                        NekoPhotoLibraryAssetCell(
                            asset: asset,
                            isSelected: selectedAssetID == asset.localIdentifier
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 2)
            .padding(.bottom, 28)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(NekoTheme.soulViolet.opacity(0.72))
            Text("没有可选择的照片")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(NekoTheme.ink)
            Text("可以先把猫咪照片保存到相册，再回来选择。")
                .font(.system(size: 13))
                .foregroundStyle(NekoTheme.muted)
        }
        .multilineTextAlignment(.center)
        .padding(28)
    }

    private var permissionState: some View {
        VStack(spacing: 14) {
            Image(systemName: "photo.badge.exclamationmark")
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(NekoTheme.soulViolet.opacity(0.72))
            Text("需要相册权限")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(NekoTheme.ink)
            Text("允许访问相册后，才能从图库选择猫咪照片。")
                .font(.system(size: 13))
                .foregroundStyle(NekoTheme.muted)
                .multilineTextAlignment(.center)
            Button("打开系统设置") {
                guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                UIApplication.shared.open(url)
            }
            .buttonStyle(NekoCameraPrimaryButtonStyle())
            .padding(.top, 4)
        }
        .padding(28)
    }

    @MainActor
    private func confirmSelection() async {
        guard let selectedAssetID,
              let asset = library.assets.first(where: { $0.localIdentifier == selectedAssetID }),
              !isLoadingSelection else { return }

        isLoadingSelection = true
        defer { isLoadingSelection = false }

        guard let image = await library.fullSizeImage(for: asset) else { return }
        onConfirm(image)
    }
}

private struct NekoPhotoLibraryAssetCell: View {
    let asset: PHAsset
    let isSelected: Bool

    @State private var image: UIImage?

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .bottomTrailing) {
                Rectangle()
                    .fill(Color.black.opacity(0.05))

                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: proxy.size.width, height: proxy.size.height)
                        .clipped()
                }

                if isSelected {
                    Circle()
                        .fill(NekoTheme.soulPink)
                        .frame(width: 26, height: 26)
                        .overlay {
                            Image(systemName: "checkmark")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(.white)
                        }
                        .overlay {
                            Circle().stroke(.white, lineWidth: 2)
                        }
                        .padding(8)
                }
            }
            .contentShape(Rectangle())
            .task(id: asset.localIdentifier) {
                await loadThumbnail(side: proxy.size.width)
            }
        }
        .aspectRatio(1, contentMode: .fit)
    }

    @MainActor
    private func loadThumbnail(side: CGFloat) async {
        let scale = UIScreen.main.scale
        let targetSize = CGSize(width: max(side * scale, 180), height: max(side * scale, 180))
        let options = PHImageRequestOptions()
        options.deliveryMode = .opportunistic
        options.resizeMode = .fast
        options.isNetworkAccessAllowed = true

        PHImageManager.default().requestImage(
            for: asset,
            targetSize: targetSize,
            contentMode: .aspectFill,
            options: options
        ) { nextImage, _ in
            guard let nextImage else { return }
            Task { @MainActor in
                image = nextImage
            }
        }
    }
}

@MainActor
private final class NekoPhotoLibraryStore: ObservableObject {
    @Published private(set) var authorizationStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)
    @Published private(set) var assets: [PHAsset] = []

    var canReadPhotos: Bool {
        authorizationStatus == .authorized || authorizationStatus == .limited
    }

    func requestAccessAndLoad() {
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        authorizationStatus = status

        if status == .notDetermined {
            PHPhotoLibrary.requestAuthorization(for: .readWrite) { [weak self] newStatus in
                Task { @MainActor in
                    self?.authorizationStatus = newStatus
                    self?.loadAssetsIfPossible()
                }
            }
            return
        }

        loadAssetsIfPossible()
    }

    func fullSizeImage(for asset: PHAsset) async -> UIImage? {
        await withCheckedContinuation { continuation in
            let options = PHImageRequestOptions()
            options.deliveryMode = .highQualityFormat
            options.resizeMode = .none
            options.isNetworkAccessAllowed = true
            options.version = .current

            var didResume = false
            PHImageManager.default().requestImage(
                for: asset,
                targetSize: PHImageManagerMaximumSize,
                contentMode: .aspectFit,
                options: options
            ) { image, info in
                let isDegraded = (info?[PHImageResultIsDegradedKey] as? Bool) == true
                guard !isDegraded, !didResume else { return }
                didResume = true
                continuation.resume(returning: image)
            }
        }
    }

    private func loadAssetsIfPossible() {
        guard canReadPhotos else {
            assets = []
            return
        }

        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        options.predicate = NSPredicate(format: "mediaType == %d", PHAssetMediaType.image.rawValue)
        options.fetchLimit = 300

        let result = PHAsset.fetchAssets(with: options)
        var nextAssets: [PHAsset] = []
        nextAssets.reserveCapacity(result.count)
        result.enumerateObjects { asset, _, _ in
            nextAssets.append(asset)
        }
        assets = nextAssets
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
