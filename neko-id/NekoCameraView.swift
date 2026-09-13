@preconcurrency import AVFoundation
import Combine
import ImageIO
import OSLog
import PhotosUI
import SwiftUI
import UIKit

struct NekoCameraView: View {
    let onClose: () -> Void
    let onUsePhoto: (UIImage) -> Void
    let guidanceText: String

    @StateObject private var camera = NekoCameraController()
    @State private var capturedPhoto: NekoCapturedPhoto?
    @State private var recentImage: UIImage?
    @State private var showsPhotoLibrary = false
    @State private var shutterFlashOpacity: CGFloat = 0

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

            if let capturedPhoto {
                Image(uiImage: capturedPhoto.image)
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipped()
                    .background(Color.black)
                    .ignoresSafeArea()
            } else if camera.authorizationDenied {
                cameraUnavailableView
            } else {
                NekoCameraPreview(
                    session: camera.session,
                    onViewportChanged: camera.updateCaptureViewport
                )
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
                if capturedPhoto == nil, !camera.authorizationDenied {
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

            Color.white
                .opacity(shutterFlashOpacity)
                .ignoresSafeArea()
                .allowsHitTesting(false)
        }
        // Keep the camera immersive, but restore the status bar while the system
        // photo picker is presented so its native Cancel/Add controls always sit
        // inside the correct safe area.
        .statusBarHidden(!showsPhotoLibrary)
        .onAppear {
            camera.onPhotoCaptured = { photo in
                capturedPhoto = photo
                recentImage = photo.image
            }
            camera.start()
        }
        .onDisappear {
            camera.stop()
        }
        .onChange(of: showsPhotoLibrary) { wasPresented, isPresented in
            guard wasPresented, !isPresented, capturedPhoto == nil, !camera.authorizationDenied else { return }
            camera.start()
        }
        .sheet(isPresented: $showsPhotoLibrary) {
            NekoPhotoLibraryPicker(
                onCancel: {
                    showsPhotoLibrary = false
                },
                onConfirm: { image in
                    recentImage = image
                    camera.stop()
                    showsPhotoLibrary = false
                    onUsePhoto(image)
                }
            )
            .statusBarHidden(false)
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
        }
    }

    @ViewBuilder
    private var bottomControls: some View {
        if let capturedPhoto {
            HStack(spacing: 12) {
                Button {
                    self.capturedPhoto = nil
                    camera.start()
                } label: {
                    Text("重拍")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(NekoCameraSecondaryButtonStyle())

                Button {
                    onUsePhoto(capturedPhoto.image)
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
                    openPhotoLibrary()
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
                    triggerShutterFeedback()
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
            Text("请在系统设置中允许相机访问，或从照片图库选择猫咪照片。")
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
                openPhotoLibrary()
            }
            .foregroundStyle(NekoTheme.soulViolet)
        }
        .padding(28)
        .background(NekoTheme.backgroundGradient, in: RoundedRectangle(cornerRadius: 30, style: .continuous))
        .padding(24)
    }

    private func openPhotoLibrary() {
        camera.stop()
        showsPhotoLibrary = true
    }

    private func triggerShutterFeedback() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        withAnimation(.easeOut(duration: 0.04)) {
            shutterFlashOpacity = 0.20
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.07) {
            withAnimation(.easeOut(duration: 0.16)) {
                shutterFlashOpacity = 0
            }
        }
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
    let onViewportChanged: (CGSize) -> Void

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        view.onViewportChanged = onViewportChanged
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {
        uiView.previewLayer.session = session
        uiView.onViewportChanged = onViewportChanged
    }

    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
        var onViewportChanged: ((CGSize) -> Void)?
        private var lastReportedSize: CGSize = .zero

        override func layoutSubviews() {
            super.layoutSubviews()

            let nextSize = bounds.size
            guard nextSize.width > 1,
                  nextSize.height > 1,
                  abs(nextSize.width - lastReportedSize.width) > 0.5 ||
                    abs(nextSize.height - lastReportedSize.height) > 0.5 else {
                return
            }

            lastReportedSize = nextSize
            onViewportChanged?(nextSize)
        }
    }
}

private nonisolated struct NekoCapturedPhoto {
    let image: UIImage
    let metrics: NekoCameraCaptureMetrics
}

private nonisolated struct NekoCameraCaptureContext {
    let requestedAt: CFTimeInterval
    let viewportSize: CGSize
    let viewportAspectRatio: CGFloat
    let deviceSummaryBeforeCapture: String
    let zoomFactorBeforeCapture: CGFloat
    let formatSummaryBeforeCapture: String
    var capturePhotoCallDuration: CFTimeInterval = 0
}

private nonisolated struct NekoCameraCaptureMetrics {
    let viewportSize: CGSize
    let viewportAspectRatio: CGFloat
    let rawPixelSize: CGSize
    let rawAspectRatio: CGFloat
    let croppedPixelSize: CGSize
    let capturePhotoCallDuration: CFTimeInterval
    let delegateWaitDuration: CFTimeInterval
    let fileDataDuration: CFTimeInterval
    let metadataDuration: CFTimeInterval
    let decodeOrientResizeDuration: CFTimeInterval
    let cropDuration: CFTimeInterval
    let totalToConfirmationDuration: CFTimeInterval
    let deviceSummaryBeforeCapture: String
    let deviceSummaryAfterCapture: String
    let zoomFactorBeforeCapture: CGFloat
    let zoomFactorAfterCapture: CGFloat
    let formatSummaryBeforeCapture: String
    let formatSummaryAfterCapture: String

    var logSummary: String {
        let lensChanged = deviceSummaryBeforeCapture == deviceSummaryAfterCapture ? "no" : "yes"
        let zoomChanged = abs(zoomFactorBeforeCapture - zoomFactorAfterCapture) < 0.001 ? "no" : "yes"
        let formatChanged = formatSummaryBeforeCapture == formatSummaryAfterCapture ? "no" : "yes"
        return """
        Camera capture metrics | viewport=\(format(size: viewportSize)) aspect=\(format(viewportAspectRatio)) | raw=\(format(size: rawPixelSize)) aspect=\(format(rawAspectRatio)) | cropped=\(format(size: croppedPixelSize)) | capturePhotoCall=\(format(ms: capturePhotoCallDuration)) | didFinishProcessingPhotoWait=\(format(ms: delegateWaitDuration)) | fileDataRepresentation=\(format(ms: fileDataDuration)) | metadata=\(format(ms: metadataDuration)) | decode+orientation+resize=\(format(ms: decodeOrientResizeDuration)) | crop=\(format(ms: cropDuration)) | fileWrite/photosSave/base64/upload=0ms before confirmation | totalShutterToConfirmation=\(format(ms: totalToConfirmationDuration)) | lensChanged=\(lensChanged) zoomChanged=\(zoomChanged) formatChanged=\(formatChanged) | before=[\(deviceSummaryBeforeCapture), zoom=\(format(zoomFactorBeforeCapture)), format=\(formatSummaryBeforeCapture)] after=[\(deviceSummaryAfterCapture), zoom=\(format(zoomFactorAfterCapture)), format=\(formatSummaryAfterCapture)]
        """
    }

    private func format(ms duration: CFTimeInterval) -> String {
        String(format: "%.1fms", duration * 1000)
    }

    private func format(_ value: CGFloat) -> String {
        String(format: "%.3f", value)
    }

    private func format(size: CGSize) -> String {
        "\(Int(size.width.rounded()))x\(Int(size.height.rounded()))"
    }
}

private nonisolated final class NekoCameraController: NSObject, ObservableObject, AVCapturePhotoCaptureDelegate, @unchecked Sendable {
    let session = AVCaptureSession()
    @MainActor @Published private(set) var isReady = false
    @MainActor @Published private(set) var isCapturing = false
    @MainActor @Published private(set) var authorizationDenied = false
    var onPhotoCaptured: ((NekoCapturedPhoto) -> Void)?

    private static let logger = Logger(subsystem: "uk.nekoid.app", category: "camera")
    private static let previewMaxPixelDimension = 1600
    private static let minimumUsefulPhotoLongEdge: Int32 = 2048
    private let sessionQueue = DispatchQueue(label: "uk.nekoid.camera.session", qos: .userInitiated)
    private let photoOutput = AVCapturePhotoOutput()
    private var currentPosition: AVCaptureDevice.Position = .back
    private var isConfigured = false
    private var activeDevice: AVCaptureDevice?
    private var configuredPhotoDimensions: CMVideoDimensions?
    private var captureViewportSize = CGSize(width: 3, height: 4)
    private var activeCaptureContext: NekoCameraCaptureContext?

    @MainActor
    func start() {
        Task { @MainActor in
            let granted = await requestCameraAccess()
            guard granted else {
                authorizationDenied = true
                return
            }
            authorizationDenied = false
            configureAndStartSession()
        }
    }

    func updateCaptureViewport(_ size: CGSize) {
        guard size.width > 1, size.height > 1 else { return }
        sessionQueue.async { [weak self] in
            self?.captureViewportSize = size
        }
    }

    func stop() {
        sessionQueue.async { [session] in
            if session.isRunning { session.stopRunning() }
        }
    }

    @MainActor
    func capturePhoto() {
        guard isReady, !isCapturing else { return }
        isCapturing = true
        let requestedAt = CACurrentMediaTime()

        sessionQueue.async { [weak self] in
            guard let self else { return }
            let viewportSize = self.captureViewportSize
            let viewportAspectRatio = max(viewportSize.width, 1) / max(viewportSize.height, 1)
            let device = self.activeDevice
            let context = NekoCameraCaptureContext(
                requestedAt: requestedAt,
                viewportSize: viewportSize,
                viewportAspectRatio: viewportAspectRatio,
                deviceSummaryBeforeCapture: self.deviceSummary(device),
                zoomFactorBeforeCapture: device?.videoZoomFactor ?? 0,
                formatSummaryBeforeCapture: self.formatSummary(device?.activeFormat)
            )

            let settings = AVCapturePhotoSettings()
            settings.flashMode = .off
            settings.photoQualityPrioritization = .balanced
            settings.isAutoVirtualDeviceFusionEnabled = false
            if let configuredPhotoDimensions = self.configuredPhotoDimensions {
                settings.maxPhotoDimensions = configuredPhotoDimensions
            }

            let capturePhotoCallStartedAt = CACurrentMediaTime()
            self.activeCaptureContext = context
            self.photoOutput.capturePhoto(with: settings, delegate: self)
            self.activeCaptureContext?.capturePhotoCallDuration = CACurrentMediaTime() - capturePhotoCallStartedAt
        }
    }

    @MainActor
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
                    self.configurePhotoOutput(for: self.activeDevice)
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
        configureDevice(device)
        session.addInput(input)
        activeDevice = device
        configurePhotoOutput(for: device)
    }

    func photoOutput(
        _ output: AVCapturePhotoOutput,
        didFinishProcessingPhoto photo: AVCapturePhoto,
        error: Error?
    ) {
        guard error == nil else {
            Task { @MainActor in self.isCapturing = false }
            return
        }

        let callbackAt = CACurrentMediaTime()
        let context = activeCaptureContext
        activeCaptureContext = nil

        let fileDataStartedAt = CACurrentMediaTime()
        guard let data = photo.fileDataRepresentation() else {
            Task { @MainActor in self.isCapturing = false }
            return
        }
        let fileDataDuration = CACurrentMediaTime() - fileDataStartedAt

        do {
            let processed = try makeConfirmationPhoto(
                from: data,
                viewportAspectRatio: context?.viewportAspectRatio ?? currentViewportAspectRatio(),
                viewportSize: context?.viewportSize ?? captureViewportSize
            )
            let metrics = NekoCameraCaptureMetrics(
                viewportSize: context?.viewportSize ?? captureViewportSize,
                viewportAspectRatio: context?.viewportAspectRatio ?? currentViewportAspectRatio(),
                rawPixelSize: processed.rawPixelSize,
                rawAspectRatio: processed.rawAspectRatio,
                croppedPixelSize: processed.image.size,
                capturePhotoCallDuration: context?.capturePhotoCallDuration ?? 0,
                delegateWaitDuration: callbackAt - (context?.requestedAt ?? callbackAt),
                fileDataDuration: fileDataDuration,
                metadataDuration: processed.metadataDuration,
                decodeOrientResizeDuration: processed.decodeOrientResizeDuration,
                cropDuration: processed.cropDuration,
                totalToConfirmationDuration: CACurrentMediaTime() - (context?.requestedAt ?? callbackAt),
                deviceSummaryBeforeCapture: context?.deviceSummaryBeforeCapture ?? "unknown",
                deviceSummaryAfterCapture: deviceSummary(activeDevice),
                zoomFactorBeforeCapture: context?.zoomFactorBeforeCapture ?? 0,
                zoomFactorAfterCapture: activeDevice?.videoZoomFactor ?? 0,
                formatSummaryBeforeCapture: context?.formatSummaryBeforeCapture ?? "unknown",
                formatSummaryAfterCapture: formatSummary(activeDevice?.activeFormat)
            )
            let capturedPhoto = NekoCapturedPhoto(image: processed.image, metrics: metrics)
            Self.logger.info("\(metrics.logSummary, privacy: .public)")
            #if DEBUG
            print(metrics.logSummary)
            #endif
            sessionQueue.async { [session] in
                if session.isRunning { session.stopRunning() }
            }
            Task { @MainActor in
                self.isCapturing = false
                self.onPhotoCaptured?(capturedPhoto)
            }
        } catch {
            Self.logger.error("Failed to prepare captured photo: \(error.localizedDescription, privacy: .public)")
            Task { @MainActor in self.isCapturing = false }
        }
    }

    private func configureDevice(_ device: AVCaptureDevice) {
        do {
            try device.lockForConfiguration()
            let stableZoom = min(max(1, device.minAvailableVideoZoomFactor), device.maxAvailableVideoZoomFactor)
            device.videoZoomFactor = stableZoom
            if device.isFocusModeSupported(.continuousAutoFocus) {
                device.focusMode = .continuousAutoFocus
            }
            if device.isExposureModeSupported(.continuousAutoExposure) {
                device.exposureMode = .continuousAutoExposure
            }
            device.unlockForConfiguration()
        } catch {
            Self.logger.error("Failed to lock camera configuration: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func configurePhotoOutput(for device: AVCaptureDevice? = nil) {
        photoOutput.maxPhotoQualityPrioritization = .balanced
        photoOutput.isVirtualDeviceConstituentPhotoDeliveryEnabled = false

        if photoOutput.isZeroShutterLagSupported {
            photoOutput.isZeroShutterLagEnabled = true
        }
        if photoOutput.isResponsiveCaptureSupported {
            photoOutput.isResponsiveCaptureEnabled = true
        }
        if photoOutput.isFastCapturePrioritizationSupported {
            photoOutput.isFastCapturePrioritizationEnabled = true
        }

        guard let device else { return }
        if let preferredDimensions = preferredPhotoDimensions(for: device.activeFormat) {
            configuredPhotoDimensions = preferredDimensions
            photoOutput.maxPhotoDimensions = preferredDimensions
        }
    }

    private func preferredPhotoDimensions(for format: AVCaptureDevice.Format) -> CMVideoDimensions? {
        let sortedDimensions = format.supportedMaxPhotoDimensions.sorted {
            photoPixelCount($0) < photoPixelCount($1)
        }
        return sortedDimensions.first {
            max($0.width, $0.height) >= Self.minimumUsefulPhotoLongEdge
        } ?? sortedDimensions.first
    }

    private func photoPixelCount(_ dimensions: CMVideoDimensions) -> Int64 {
        Int64(dimensions.width) * Int64(dimensions.height)
    }

    private func makeConfirmationPhoto(
        from data: Data,
        viewportAspectRatio: CGFloat,
        viewportSize: CGSize
    ) throws -> (
        image: UIImage,
        rawPixelSize: CGSize,
        rawAspectRatio: CGFloat,
        metadataDuration: CFTimeInterval,
        decodeOrientResizeDuration: CFTimeInterval,
        cropDuration: CFTimeInterval
    ) {
        let metadataStartedAt = CACurrentMediaTime()
        guard let source = CGImageSourceCreateWithData(data as CFData, [
            kCGImageSourceShouldCache: false
        ] as CFDictionary) else {
            throw NekoCameraError.unsupportedPhotoData
        }
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        let rawWidth = properties?[kCGImagePropertyPixelWidth] as? CGFloat ?? 0
        let rawHeight = properties?[kCGImagePropertyPixelHeight] as? CGFloat ?? 0
        let orientation = properties?[kCGImagePropertyOrientation] as? Int ?? 1
        let isRotated = [5, 6, 7, 8].contains(orientation)
        let rawPixelSize = CGSize(
            width: isRotated ? rawHeight : rawWidth,
            height: isRotated ? rawWidth : rawHeight
        )
        let metadataDuration = CACurrentMediaTime() - metadataStartedAt

        let decodeStartedAt = CACurrentMediaTime()
        let thumbnailOptions: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: Self.previewMaxPixelDimension
        ]
        guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbnailOptions as CFDictionary) else {
            throw NekoCameraError.unsupportedPhotoData
        }
        let decodeOrientResizeDuration = CACurrentMediaTime() - decodeStartedAt

        let cropStartedAt = CACurrentMediaTime()
        let cropAspectRatio = viewportAspectRatio > 0 ? viewportAspectRatio : max(viewportSize.width, 1) / max(viewportSize.height, 1)
        guard let cropped = thumbnail.centerCropped(toAspectRatio: cropAspectRatio) else {
            throw NekoCameraError.unsupportedPhotoData
        }
        let cropDuration = CACurrentMediaTime() - cropStartedAt

        let image = UIImage(cgImage: cropped, scale: 1, orientation: .up)
        let rawAspectRatio = rawPixelSize.width / max(rawPixelSize.height, 1)
        return (
            image,
            rawPixelSize,
            rawAspectRatio,
            metadataDuration,
            decodeOrientResizeDuration,
            cropDuration
        )
    }

    private func currentViewportAspectRatio() -> CGFloat {
        max(captureViewportSize.width, 1) / max(captureViewportSize.height, 1)
    }

    private func deviceSummary(_ device: AVCaptureDevice?) -> String {
        guard let device else { return "unknown" }
        return "\(device.localizedName) \(device.deviceType.rawValue) \(device.uniqueID)"
    }

    private func formatSummary(_ format: AVCaptureDevice.Format?) -> String {
        guard let format else { return "unknown" }
        let dimensions = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
        return "\(dimensions.width)x\(dimensions.height)"
    }
}

private nonisolated enum NekoCameraError: Error {
    case unsupportedPhotoData
}

private nonisolated extension CGImage {
    func centerCropped(toAspectRatio targetAspectRatio: CGFloat) -> CGImage? {
        guard targetAspectRatio > 0 else { return nil }
        let sourceWidth = CGFloat(width)
        let sourceHeight = CGFloat(height)
        let sourceAspectRatio = sourceWidth / max(sourceHeight, 1)

        let cropRect: CGRect
        if sourceAspectRatio > targetAspectRatio {
            let targetWidth = sourceHeight * targetAspectRatio
            cropRect = CGRect(
                x: (sourceWidth - targetWidth) / 2,
                y: 0,
                width: targetWidth,
                height: sourceHeight
            )
        } else {
            let targetHeight = sourceWidth / targetAspectRatio
            cropRect = CGRect(
                x: 0,
                y: (sourceHeight - targetHeight) / 2,
                width: sourceWidth,
                height: targetHeight
            )
        }

        let integralRect = CGRect(
            x: max(0, floor(cropRect.origin.x)),
            y: max(0, floor(cropRect.origin.y)),
            width: min(sourceWidth, floor(cropRect.width)),
            height: min(sourceHeight, floor(cropRect.height))
        )
        return cropping(to: integralRect)
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
