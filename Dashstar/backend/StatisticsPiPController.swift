import AVFoundation
import AVKit
import CoreMedia
import Observation
import SwiftUI
import UIKit

@MainActor
@Observable
final class StatisticsPiPController: NSObject {
    private(set) var isActive = false
    private(set) var isPossible = AVPictureInPictureController.isPictureInPictureSupported()
    var lastError: String?

    let displayLayer = AVSampleBufferDisplayLayer()
    private var pictureInPictureController: AVPictureInPictureController?
    private var updateTask: Task<Void, Never>?
    private var points: [PiPTrafficPoint] = []
    private var previousTotals: TunnelTrafficTotals?
    private var previousDate: Date?

    override init() {
        super.init()
        displayLayer.videoGravity = .resizeAspect
        displayLayer.backgroundColor = UIColor.black.cgColor
        if AVPictureInPictureController.isPictureInPictureSupported() {
            let source = AVPictureInPictureController.ContentSource(
                sampleBufferDisplayLayer: displayLayer,
                playbackDelegate: self
            )
            let controller = AVPictureInPictureController(contentSource: source)
            controller.delegate = self
            controller.canStartPictureInPictureAutomaticallyFromInline = true
            pictureInPictureController = controller
        }
    }

    func start(tunnel: TunnelController) {
        guard tunnel.isConnected else {
            lastError = "Connect VPN before enabling Picture in Picture."
            return
        }
        guard let controller = pictureInPictureController else {
            lastError = "Picture in Picture is not supported on this device."
            return
        }
        isActive = true
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, options: [.mixWithOthers])
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            lastError = error.localizedDescription
            return
        }

        lastError = nil
        updateTask?.cancel()
        updateTask = Task { [weak self] in
            await self?.updateLoop(tunnel: tunnel)
        }
        renderFrame(connectedAt: nil, now: Date())
        // Give AVSampleBufferDisplayLayer one run-loop pass to present the
        // first frame before PiP snapshots its content source.
        Task { [weak self, weak controller] in
            try? await Task.sleep(for: .milliseconds(180))
            guard self?.isActive == true else { return }
            guard let controller, controller.isPictureInPicturePossible else {
                self?.isActive = false
                self?.updateTask?.cancel()
                self?.updateTask = nil
                self?.lastError = "Picture in Picture is not ready. Keep Statistics visible and try again."
                return
            }
            controller.startPictureInPicture()
        }
    }

    func stop() {
        updateTask?.cancel()
        updateTask = nil
        pictureInPictureController?.stopPictureInPicture()
        isActive = false
        previousTotals = nil
        previousDate = nil
        points.removeAll()
    }

    private func updateLoop(tunnel: TunnelController) async {
        while !Task.isCancelled {
            let now = Date()
            guard tunnel.isConnected else {
                stop()
                return
            }
            if let totals = try? await tunnel.trafficTotals() {
                if let previousTotals, let previousDate {
                    let interval = max(now.timeIntervalSince(previousDate), 0.1)
                    func rate(_ current: Int64, _ previous: Int64) -> Double {
                        Double(max(0, current - previous)) / interval
                    }
                    points.append(PiPTrafficPoint(
                        direct: rate(totals.directUpload + totals.directDownload, previousTotals.directUpload + previousTotals.directDownload),
                        proxy: rate(totals.proxyUpload + totals.proxyDownload, previousTotals.proxyUpload + previousTotals.proxyDownload),
                        total: rate(totals.upload + totals.download, previousTotals.upload + previousTotals.download)
                    ))
                    if points.count > 60 { points.removeFirst(points.count - 60) }
                }
                self.previousTotals = totals
                self.previousDate = now
                renderFrame(connectedAt: totals.connectedAt, now: now)
            }
            try? await Task.sleep(for: .seconds(1))
        }
    }

    private func renderFrame(connectedAt: Date?, now: Date) {
        let width = 640
        let height = 360
        var pixelBuffer: CVPixelBuffer?
        let attributes: [CFString: Any] = [
            kCVPixelBufferCGImageCompatibilityKey: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey: true,
            kCVPixelBufferIOSurfacePropertiesKey: [:],
        ]
        guard CVPixelBufferCreate(
            kCFAllocatorDefault, width, height, kCVPixelFormatType_32BGRA,
            attributes as CFDictionary, &pixelBuffer
        ) == kCVReturnSuccess, let pixelBuffer else { return }
        CVPixelBufferLockBaseAddress(pixelBuffer, [])
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, []) }
        guard let context = CGContext(
            data: CVPixelBufferGetBaseAddress(pixelBuffer),
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(pixelBuffer),
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        ) else { return }

        context.setFillColor(UIColor(red: 0.035, green: 0.04, blue: 0.055, alpha: 1).cgColor)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        drawText("Dashstar · Live Traffic", at: CGPoint(x: 28, y: 315), size: 22, color: .white, context: context)
        drawText(durationText(from: connectedAt, to: now), at: CGPoint(x: 485, y: 315), size: 18, color: .lightGray, context: context)

        let plot = CGRect(x: 42, y: 66, width: 570, height: 220)
        context.setStrokeColor(UIColor.white.withAlphaComponent(0.12).cgColor)
        context.setLineWidth(1)
        for index in 0...4 {
            let y = plot.minY + plot.height * CGFloat(index) / 4
            context.move(to: CGPoint(x: plot.minX, y: y))
            context.addLine(to: CGPoint(x: plot.maxX, y: y))
        }
        context.strokePath()

        let maximum = max(1_024, points.map(\.total).max() ?? 0)
        drawLine(values: points.map(\.direct), color: .systemGreen, maximum: maximum, plot: plot, context: context)
        drawLine(values: points.map(\.proxy), color: .systemPink, maximum: maximum, plot: plot, context: context)
        drawLine(values: points.map(\.total), color: .systemOrange, maximum: maximum, plot: plot, context: context, width: 4)
        drawText("Direct", at: CGPoint(x: 45, y: 28), size: 16, color: .systemGreen, context: context)
        drawText("Proxy", at: CGPoint(x: 145, y: 28), size: 16, color: .systemPink, context: context)
        drawText("Total", at: CGPoint(x: 235, y: 28), size: 16, color: .systemOrange, context: context)

        var format: CMVideoFormatDescription?
        guard CMVideoFormatDescriptionCreateForImageBuffer(
            allocator: kCFAllocatorDefault, imageBuffer: pixelBuffer, formatDescriptionOut: &format
        ) == noErr, let format else { return }
        var timing = CMSampleTimingInfo(
            duration: CMTime(value: 1, timescale: 1),
            presentationTimeStamp: CMClockGetTime(CMClockGetHostTimeClock()),
            decodeTimeStamp: .invalid
        )
        var sampleBuffer: CMSampleBuffer?
        guard CMSampleBufferCreateReadyWithImageBuffer(
            allocator: kCFAllocatorDefault, imageBuffer: pixelBuffer,
            formatDescription: format, sampleTiming: &timing, sampleBufferOut: &sampleBuffer
        ) == noErr, let sampleBuffer else { return }
        CMSetAttachment(
            sampleBuffer,
            key: kCMSampleAttachmentKey_DisplayImmediately,
            value: kCFBooleanTrue,
            attachmentMode: kCMAttachmentMode_ShouldNotPropagate
        )
        if displayLayer.sampleBufferRenderer.status == .failed {
            displayLayer.sampleBufferRenderer.flush()
        }
        displayLayer.sampleBufferRenderer.enqueue(sampleBuffer)
    }

    private func drawLine(values: [Double], color: UIColor, maximum: Double, plot: CGRect, context: CGContext, width: CGFloat = 3) {
        guard values.count > 1 else { return }
        context.setStrokeColor(color.cgColor)
        context.setLineWidth(width)
        context.setLineJoin(.round)
        for (index, value) in values.enumerated() {
            let x = plot.minX + plot.width * CGFloat(index) / CGFloat(max(values.count - 1, 1))
            let y = plot.minY + plot.height * CGFloat(min(max(value / maximum, 0), 1))
            if index == 0 { context.move(to: CGPoint(x: x, y: y)) }
            else { context.addLine(to: CGPoint(x: x, y: y)) }
        }
        context.strokePath()
    }

    private func drawText(_ text: String, at point: CGPoint, size: CGFloat, color: UIColor, context: CGContext) {
        context.saveGState()
        // CVPixelBuffer/CoreGraphics uses a bottom-left origin while UIKit's
        // NSString drawing assumes a top-left origin. Flip around the text's
        // own vertical center so the glyphs become upright without moving.
        context.translateBy(x: 0, y: point.y * 2 + size)
        context.scaleBy(x: 1, y: -1)
        UIGraphicsPushContext(context)
        text.draw(at: point, withAttributes: [.font: UIFont.systemFont(ofSize: size, weight: .semibold), .foregroundColor: color])
        UIGraphicsPopContext()
        context.restoreGState()
    }

    private func durationText(from start: Date?, to end: Date) -> String {
        guard let start else { return "00:00:00" }
        let seconds = max(0, Int(end.timeIntervalSince(start)))
        return String(format: "%02d:%02d:%02d", seconds / 3600, (seconds % 3600) / 60, seconds % 60)
    }
}

private struct PiPTrafficPoint {
    let direct: Double
    let proxy: Double
    let total: Double
}

extension StatisticsPiPController: AVPictureInPictureControllerDelegate {
    nonisolated func pictureInPictureControllerDidStartPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        Task { @MainActor in isActive = true }
    }

    nonisolated func pictureInPictureControllerDidStopPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        Task { @MainActor in
            updateTask?.cancel()
            updateTask = nil
            isActive = false
        }
    }

    nonisolated func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController, failedToStartPictureInPictureWithError error: Error) {
        Task { @MainActor in
            updateTask?.cancel()
            updateTask = nil
            isActive = false
            lastError = error.localizedDescription
        }
    }
}

extension StatisticsPiPController: AVPictureInPictureSampleBufferPlaybackDelegate {
    nonisolated func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController, setPlaying playing: Bool) {}
    nonisolated func pictureInPictureControllerTimeRangeForPlayback(_ pictureInPictureController: AVPictureInPictureController) -> CMTimeRange {
        CMTimeRange(start: .zero, duration: CMTime(seconds: 86_400, preferredTimescale: 1))
    }
    nonisolated func pictureInPictureControllerIsPlaybackPaused(_ pictureInPictureController: AVPictureInPictureController) -> Bool { false }
    nonisolated func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController, didTransitionToRenderSize newRenderSize: CMVideoDimensions) {}
    nonisolated func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController, skipByInterval skipInterval: CMTime, completion: @escaping () -> Void) { completion() }
}

struct PiPSampleBufferHost: UIViewRepresentable {
    let controller: StatisticsPiPController
    func makeUIView(context: Context) -> PiPLayerView { PiPLayerView(layer: controller.displayLayer) }
    func updateUIView(_ uiView: PiPLayerView, context: Context) {}
}

final class PiPLayerView: UIView {
    private let sampleLayer: AVSampleBufferDisplayLayer
    init(layer: AVSampleBufferDisplayLayer) {
        sampleLayer = layer
        super.init(frame: .zero)
        self.layer.addSublayer(layer)
    }
    required init?(coder: NSCoder) { nil }
    override func layoutSubviews() { super.layoutSubviews(); sampleLayer.frame = bounds }
}
