import SwiftUI
import Vision
import CoreImage
import CoreImage.CIFilterBuiltins
import UniformTypeIdentifiers

enum BGMethod: String, CaseIterable {
    case threshold = "Color"
    case vision    = "Vision AI"
}

class BGRemoverViewModel: ObservableObject {
    @Published var originalImage: NSImage?
    @Published var resultImage: NSImage?
    @Published var isProcessing = false
    @Published var showOriginal = true
    @Published var errorMessage: String?

    // Threshold controls (only used in .threshold mode)
    @Published var tolerance: Double = 30          // 0–100
    @Published var selectedMethod: BGMethod = .threshold

    private let ciContext = CIContext()
    private var originalCGImage: CGImage?
    private var originalNSSize: NSSize = .zero

    // MARK: - Reset
    func reset() {
        originalImage = nil
        resultImage = nil
        isProcessing = false
        showOriginal = true
        errorMessage = nil
        originalCGImage = nil
    }

    // MARK: - Input
    func pasteFromClipboard() {
        let pasteboard = NSPasteboard.general
        if let image = NSImage(pasteboard: pasteboard) { processImage(image); return }
        if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: [
            .urlReadingContentsConformToTypes: [UTType.image.identifier]
        ]) as? [URL], let url = urls.first, let image = NSImage(contentsOf: url) {
            processImage(image); return
        }
        errorMessage = "No image found in clipboard"
    }

    func openFilePicker() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image, .png, .jpeg, .heic, .webP, .tiff]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        if panel.runModal() == .OK, let url = panel.url, let image = NSImage(contentsOf: url) {
            processImage(image)
        }
    }

    func handleDrop(providers: [NSItemProvider]) {
        guard let provider = providers.first else { return }
        if provider.canLoadObject(ofClass: NSImage.self) {
            provider.loadObject(ofClass: NSImage.self) { [weak self] item, _ in
                if let image = item as? NSImage {
                    DispatchQueue.main.async { self?.processImage(image) }
                }
            }
        }
    }

    // MARK: - Process
    func processImage(_ image: NSImage) {
        originalImage = image
        resultImage = nil
        errorMessage = nil
        showOriginal = true
        isProcessing = true

        guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            errorMessage = "Failed to read image"
            isProcessing = false
            return
        }
        originalCGImage = cg
        originalNSSize = image.size

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.runRemoval()
        }
    }

    /// Re-run removal with current settings (called when slider changes)
    func reprocess() {
        guard originalCGImage != nil else { return }
        isProcessing = true
        resultImage = nil
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.runRemoval()
        }
    }

    private func runRemoval() {
        switch selectedMethod {
        case .threshold: removeByThreshold()
        case .vision:    removeByVision()
        }
    }

    // MARK: - Color Threshold
    // Removes pixels whose luminance/color is close to the corner-sampled background color.
    private func removeByThreshold() {
        guard let cgImage = originalCGImage else { return }

        let w = cgImage.width
        let h = cgImage.height
        let bpc = 8
        let bpp = 4
        let bpr = w * bpp
        var pixels = [UInt8](repeating: 0, count: h * bpr)

        guard let ctx = CGContext(
            data: &pixels,
            width: w, height: h,
            bitsPerComponent: bpc,
            bytesPerRow: bpr,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return }

        ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: w, height: h))

        // Sample background color from corners (average of 4 corners)
        func pixelAt(_ x: Int, _ y: Int) -> (r: Float, g: Float, b: Float) {
            let i = y * bpr + x * bpp
            return (Float(pixels[i]), Float(pixels[i+1]), Float(pixels[i+2]))
        }
        let corners = [pixelAt(0,0), pixelAt(w-1,0), pixelAt(0,h-1), pixelAt(w-1,h-1)]
        let bgR = corners.map(\.r).reduce(0,+) / 4
        let bgG = corners.map(\.g).reduce(0,+) / 4
        let bgB = corners.map(\.b).reduce(0,+) / 4

        let thresh = Float(tolerance) * 2.55   // 0–100 → 0–255

        for y in 0..<h {
            for x in 0..<w {
                let i = y * bpr + x * bpp
                let r = Float(pixels[i])
                let g = Float(pixels[i+1])
                let b = Float(pixels[i+2])

                let dist = sqrt((r-bgR)*(r-bgR) + (g-bgG)*(g-bgG) + (b-bgB)*(b-bgB))
                if dist <= thresh {
                    pixels[i]   = 0
                    pixels[i+1] = 0
                    pixels[i+2] = 0
                    pixels[i+3] = 0   // transparent
                }
            }
        }

        guard let outCtx = CGContext(
            data: &pixels,
            width: w, height: h,
            bitsPerComponent: bpc,
            bytesPerRow: bpr,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ), let outCG = outCtx.makeImage() else { return }

        let result = NSImage(cgImage: outCG, size: originalNSSize)
        DispatchQueue.main.async {
            self.resultImage = result
            self.showOriginal = false
            self.isProcessing = false
        }
    }

    // MARK: - Vision AI
    private func removeByVision() {
        guard let cgImage = originalCGImage else { return }

        if #available(macOS 14.0, *) {
            let request = VNGenerateForegroundInstanceMaskRequest()
            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            do {
                try handler.perform([request])
                guard let result = request.results?.first else {
                    DispatchQueue.main.async {
                        self.errorMessage = "No subject detected"
                        self.isProcessing = false
                    }
                    return
                }
                let maskBuffer = try result.generateScaledMaskForImage(forInstances: result.allInstances, from: handler)
                let maskCI = CIImage(cvPixelBuffer: maskBuffer)
                let origCI = CIImage(cgImage: cgImage)
                let blend = CIFilter.blendWithMask()
                blend.inputImage = origCI
                blend.backgroundImage = CIImage.empty()
                blend.maskImage = maskCI
                guard let out = blend.outputImage,
                      let outCG = ciContext.createCGImage(out, from: origCI.extent) else { return }
                let result2 = NSImage(cgImage: outCG, size: originalNSSize)
                DispatchQueue.main.async {
                    self.resultImage = result2
                    self.showOriginal = false
                    self.isProcessing = false
                }
            } catch {
                DispatchQueue.main.async {
                    self.errorMessage = "Vision error: \(error.localizedDescription)"
                    self.isProcessing = false
                }
            }
        } else {
            DispatchQueue.main.async {
                self.errorMessage = "Vision AI requires macOS 14+"
                self.isProcessing = false
            }
        }
    }

    // MARK: - Copy / Save
    func copyResultToClipboard() {
        guard let image = resultImage else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        if let tiff = image.tiffRepresentation,
           let bmp = NSBitmapImageRep(data: tiff),
           let png = bmp.representation(using: .png, properties: [:]) {
            pasteboard.setData(png, forType: .png)
            pasteboard.setData(tiff, forType: .tiff)
        }
    }

    func saveResult() {
        guard let image = resultImage else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.nameFieldStringValue = "removed-bg.png"
        panel.canCreateDirectories = true
        if panel.runModal() == .OK, let url = panel.url {
            if let tiff = image.tiffRepresentation,
               let bmp = NSBitmapImageRep(data: tiff),
               let png = bmp.representation(using: .png, properties: [:]) {
                try? png.write(to: url)
            }
        }
    }
}
