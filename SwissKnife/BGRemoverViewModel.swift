import SwiftUI
import Vision
import CoreImage
import CoreImage.CIFilterBuiltins
import UniformTypeIdentifiers

class BGRemoverViewModel: ObservableObject {
    @Published var originalImage: NSImage?
    @Published var resultImage: NSImage?
    @Published var isProcessing = false
    @Published var showOriginal = true
    @Published var errorMessage: String?
    
    private let ciContext = CIContext()
    
    // MARK: - Reset
    func reset() {
        originalImage = nil
        resultImage = nil
        isProcessing = false
        showOriginal = true
        errorMessage = nil
    }
    
    // MARK: - Paste from Clipboard
    func pasteFromClipboard() {
        let pasteboard = NSPasteboard.general
        
        // Try to get image data from pasteboard
        if let image = NSImage(pasteboard: pasteboard) {
            processImage(image)
            return
        }
        
        // Try file URLs
        if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: [
            .urlReadingContentsConformToTypes: [UTType.image.identifier]
        ]) as? [URL], let url = urls.first {
            if let image = NSImage(contentsOf: url) {
                processImage(image)
                return
            }
        }
        
        errorMessage = "No image found in clipboard"
    }
    
    // MARK: - File Picker
    func openFilePicker() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image, .png, .jpeg, .heic, .webP, .tiff]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        
        if panel.runModal() == .OK, let url = panel.url {
            if let image = NSImage(contentsOf: url) {
                processImage(image)
            }
        }
    }
    
    // MARK: - Handle Drop
    func handleDrop(providers: [NSItemProvider]) {
        guard let provider = providers.first else { return }
        
        if provider.canLoadObject(ofClass: NSImage.self) {
            provider.loadObject(ofClass: NSImage.self) { [weak self] item, error in
                if let image = item as? NSImage {
                    DispatchQueue.main.async {
                        self?.processImage(image)
                    }
                }
            }
        }
    }
    
    // MARK: - Process Image (Remove Background)
    func processImage(_ image: NSImage) {
        originalImage = image
        resultImage = nil
        errorMessage = nil
        showOriginal = true
        isProcessing = true
        
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.removeBackground(from: image)
        }
    }
    
    private func removeBackground(from image: NSImage) {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            DispatchQueue.main.async {
                self.errorMessage = "Failed to process image"
                self.isProcessing = false
            }
            return
        }
        
        // Use VNGenerateForegroundInstanceMaskRequest (macOS 14.0+)
        if #available(macOS 14.0, *) {
            removeBackgroundWithVision(cgImage: cgImage, originalSize: image.size)
        } else {
            // Fallback for older macOS: use subject lifting via saliency
            removeBackgroundFallback(cgImage: cgImage, originalSize: image.size)
        }
    }
    
    @available(macOS 14.0, *)
    private func removeBackgroundWithVision(cgImage: CGImage, originalSize: NSSize) {
        let request = VNGenerateForegroundInstanceMaskRequest()
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        
        do {
            try handler.perform([request])
            
            guard let result = request.results?.first else {
                DispatchQueue.main.async {
                    self.errorMessage = "No foreground subject detected"
                    self.isProcessing = false
                }
                return
            }
            
            // Generate mask for all instances
            let allInstances = result.allInstances
            let maskPixelBuffer = try result.generateScaledMaskForImage(forInstances: allInstances, from: handler)
            
            let maskCIImage = CIImage(cvPixelBuffer: maskPixelBuffer)
            let originalCIImage = CIImage(cgImage: cgImage)
            
            // Apply mask: use the mask as alpha channel
            let filter = CIFilter.blendWithMask()
            filter.inputImage = originalCIImage
            filter.backgroundImage = CIImage.empty()
            filter.maskImage = maskCIImage
            
            guard let outputCIImage = filter.outputImage else {
                DispatchQueue.main.async {
                    self.errorMessage = "Failed to apply mask"
                    self.isProcessing = false
                }
                return
            }
            
            // Render to CGImage
            guard let outputCGImage = ciContext.createCGImage(outputCIImage, from: originalCIImage.extent) else {
                DispatchQueue.main.async {
                    self.errorMessage = "Failed to render result"
                    self.isProcessing = false
                }
                return
            }
            
            let nsImage = NSImage(cgImage: outputCGImage, size: originalSize)
            
            DispatchQueue.main.async {
                self.resultImage = nsImage
                self.showOriginal = false
                self.isProcessing = false
            }
            
        } catch {
            DispatchQueue.main.async {
                self.errorMessage = "Vision error: \(error.localizedDescription)"
                self.isProcessing = false
            }
        }
    }
    
    // Fallback for macOS < 14
    private func removeBackgroundFallback(cgImage: CGImage, originalSize: NSSize) {
        let request = VNGenerateAttentionBasedSaliencyImageRequest()
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        
        do {
            try handler.perform([request])
            
            guard let result = request.results?.first else {
                DispatchQueue.main.async {
                    self.errorMessage = "Could not generate mask (requires macOS 14+ for best results)"
                    self.isProcessing = false
                }
                return
            }

            let maskCIImage = CIImage(cvPixelBuffer: result.pixelBuffer)
            let originalCIImage = CIImage(cgImage: cgImage)
            
            // Scale mask to original image size
            let scaleX = originalCIImage.extent.width / maskCIImage.extent.width
            let scaleY = originalCIImage.extent.height / maskCIImage.extent.height
            let scaledMask = maskCIImage.transformed(by: CGAffineTransform(scaleX: scaleX, y: scaleY))
            
            let filter = CIFilter.blendWithMask()
            filter.inputImage = originalCIImage
            filter.backgroundImage = CIImage.empty()
            filter.maskImage = scaledMask
            
            guard let output = filter.outputImage,
                  let outputCG = ciContext.createCGImage(output, from: originalCIImage.extent) else {
                DispatchQueue.main.async {
                    self.errorMessage = "Failed to render"
                    self.isProcessing = false
                }
                return
            }
            
            let nsImage = NSImage(cgImage: outputCG, size: originalSize)
            
            DispatchQueue.main.async {
                self.resultImage = nsImage
                self.showOriginal = false
                self.isProcessing = false
            }
        } catch {
            DispatchQueue.main.async {
                self.errorMessage = "Error: \(error.localizedDescription)"
                self.isProcessing = false
            }
        }
    }
    
    // MARK: - Copy Result to Clipboard
    func copyResultToClipboard() {
        guard let image = resultImage else { return }
        
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        
        // Write as PNG with transparency
        if let tiffData = image.tiffRepresentation,
           let bitmap = NSBitmapImageRep(data: tiffData),
           let pngData = bitmap.representation(using: .png, properties: [:]) {
            pasteboard.setData(pngData, forType: .png)
            // Also write as tiff for broader compatibility
            pasteboard.setData(tiffData, forType: .tiff)
        }
    }
    
    // MARK: - Save Result
    func saveResult() {
        guard let image = resultImage else { return }
        
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.nameFieldStringValue = "removed-bg.png"
        panel.canCreateDirectories = true
        
        if panel.runModal() == .OK, let url = panel.url {
            if let tiffData = image.tiffRepresentation,
               let bitmap = NSBitmapImageRep(data: tiffData),
               let pngData = bitmap.representation(using: .png, properties: [:]) {
                try? pngData.write(to: url)
            }
        }
    }
}
