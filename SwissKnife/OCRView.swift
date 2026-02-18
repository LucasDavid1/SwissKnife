import SwiftUI
import Vision
import AppKit

// MARK: - View

struct OCRView: View {
    @State private var extractedText = ""
    @State private var isProcessing = false
    @State private var errorMessage: String?
    @State private var isCopied = false

    var body: some View {
        VStack(spacing: 0) {
            // Drop zone or result
            if extractedText.isEmpty {
                dropZoneView
            } else {
                resultView
            }
        }
    }

    // MARK: - Drop Zone
    var dropZoneView: some View {
        VStack(spacing: 16) {
            Spacer()

            VStack(spacing: 12) {
                Image(systemName: "text.viewfinder")
                    .font(.system(size: 40, weight: .ultraLight))
                    .foregroundColor(.secondary)

                Text("Screenshot to Text")
                    .font(.system(size: 14, weight: .medium))

                Text("Paste or drop a screenshot")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)

                HStack(spacing: 8) {
                    Button("Paste Image") {
                        pasteAndProcess()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)

                    Button("Capture Area") {
                        captureArea()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                .padding(.top, 4)

                if let error = errorMessage {
                    Text(error)
                        .font(.system(size: 11))
                        .foregroundColor(.red)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 20)
                }
            }

            Spacer()
        }
        .frame(maxWidth: .infinity)
        .onDrop(of: [.image, .fileURL], isTargeted: nil) { providers in
            handleDrop(providers: providers)
            return true
        }
    }

    // MARK: - Result
    var resultView: some View {
        VStack(spacing: 0) {
            // Toolbar
            HStack {
                Button(action: { reset() }) {
                    Label("New", systemImage: "arrow.counterclockwise")
                        .font(.system(size: 11))
                }
                .buttonStyle(.plain)
                .foregroundColor(.secondary)

                Spacer()

                Text("\(extractedText.count) chars")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)

                Button(action: { copyText() }) {
                    Label(isCopied ? "Copied!" : "Copy", systemImage: isCopied ? "checkmark" : "doc.on.doc")
                        .font(.system(size: 11))
                        .foregroundColor(isCopied ? .green : .accentColor)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)

            Divider()

            ScrollView {
                TextEditor(text: $extractedText)
                    .font(.system(size: 12))
                    .frame(minHeight: 200)
                    .padding(10)
            }
        }
    }

    // MARK: - Actions

    func pasteAndProcess() {
        let pb = NSPasteboard.general
        if let image = NSImage(pasteboard: pb) {
            process(image: image)
        } else {
            errorMessage = "No image found in clipboard"
        }
    }

    func captureArea() {
        // Use macOS screencapture in interactive mode
        let tmpPath = "/tmp/swissknife_ocr_capture.png"
        errorMessage = nil

        DispatchQueue.global(qos: .userInitiated).async {
            let task = Process()
            task.launchPath = "/usr/sbin/screencapture"
            task.arguments = ["-i", "-s", tmpPath]  // -i interactive, -s selection
            task.launch()
            task.waitUntilExit()

            guard task.terminationStatus == 0,
                  let image = NSImage(contentsOfFile: tmpPath) else {
                DispatchQueue.main.async {
                    self.errorMessage = "Capture cancelled or failed"
                }
                return
            }
            self.process(image: image)
            try? FileManager.default.removeItem(atPath: tmpPath)
        }
    }

    func handleDrop(providers: [NSItemProvider]) {
        guard let provider = providers.first else { return }
        if provider.canLoadObject(ofClass: NSImage.self) {
            provider.loadObject(ofClass: NSImage.self) { item, _ in
                if let image = item as? NSImage {
                    self.process(image: image)
                }
            }
        }
    }

    func process(image: NSImage) {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            DispatchQueue.main.async { self.errorMessage = "Could not read image" }
            return
        }

        DispatchQueue.main.async { self.isProcessing = true }

        DispatchQueue.global(qos: .userInitiated).async {
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true

            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            do {
                try handler.perform([request])
                let results = request.results ?? []
                let text = results
                    .compactMap { $0.topCandidates(1).first?.string }
                    .joined(separator: "\n")

                DispatchQueue.main.async {
                    self.isProcessing = false
                    if text.isEmpty {
                        self.errorMessage = "No text found in image"
                    } else {
                        self.extractedText = text
                        self.errorMessage = nil
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    self.isProcessing = false
                    self.errorMessage = "OCR error: \(error.localizedDescription)"
                }
            }
        }
    }

    func copyText() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(extractedText, forType: .string)
        withAnimation { isCopied = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            withAnimation { isCopied = false }
        }
    }

    func reset() {
        extractedText = ""
        errorMessage = nil
        isCopied = false
    }
}

// MARK: - Preview Card

struct OCRPreview: View {
    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: "text.viewfinder")
                .font(.system(size: 28, weight: .ultraLight))
                .foregroundColor(.primary.opacity(0.35))
            Text("Screenshot → Text")
                .font(.system(size: 9))
                .foregroundColor(Color(nsColor: .tertiaryLabelColor))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
