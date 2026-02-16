import SwiftUI
import CoreImage
import CoreImage.CIFilterBuiltins
import UniformTypeIdentifiers

struct ContentView: View {
    @StateObject private var viewModel = BGRemoverViewModel()
    @State private var isDragOver = false
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Image(systemName: "person.crop.rectangle.badge.minus")
                    .font(.system(size: 14, weight: .semibold))
                Text("BG Remover")
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                if viewModel.originalImage != nil {
                    Button(action: { viewModel.reset() }) {
                        Image(systemName: "arrow.counterclockwise")
                            .font(.system(size: 12))
                    }
                    .buttonStyle(.plain)
                    .help("Reset")
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(.ultraThinMaterial)
            
            Divider()
            
            if viewModel.originalImage == nil {
                // Drop zone / Paste zone
                dropZoneView
            } else {
                // Image preview & result
                resultView
            }
            
            Divider()
            
            // Footer
            footerView
        }
        .frame(width: 400, height: 460)
        .onAppear {
            NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                if event.modifierFlags.contains(.command) && event.charactersIgnoringModifiers == "v" {
                    viewModel.pasteFromClipboard()
                    return nil
                }
                return event
            }
        }
    }
    
    // MARK: - Drop Zone
    var dropZoneView: some View {
        VStack(spacing: 16) {
            Spacer()
            
            ZStack {
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(
                        isDragOver ? Color.accentColor : Color.secondary.opacity(0.3),
                        style: StrokeStyle(lineWidth: 2, dash: [8, 4])
                    )
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(isDragOver ? Color.accentColor.opacity(0.05) : Color.clear)
                    )
                
                VStack(spacing: 12) {
                    Image(systemName: "doc.on.clipboard")
                        .font(.system(size: 40, weight: .light))
                        .foregroundColor(.secondary)
                    
                    Text("Paste or Drop Image")
                        .font(.system(size: 15, weight: .medium))
                    
                    Text("⌘V to paste from clipboard")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                    
                    HStack(spacing: 8) {
                        Button("Paste Clipboard") {
                            viewModel.pasteFromClipboard()
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        
                        Button("Choose File…") {
                            viewModel.openFilePicker()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                    .padding(.top, 4)
                }
            }
            .padding(20)
            .onDrop(of: [.image, .fileURL], isTargeted: $isDragOver) { providers in
                viewModel.handleDrop(providers: providers)
                return true
            }
            
            Spacer()
        }
    }
    
    // MARK: - Result View
    var resultView: some View {
        VStack(spacing: 12) {
            // Toggle between original and result
            if viewModel.resultImage != nil {
                Picker("", selection: $viewModel.showOriginal) {
                    Text("Original").tag(true)
                    Text("No Background").tag(false)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16)
                .padding(.top, 12)
            }
            
            // Image display
            ZStack {
                // Checkerboard for transparency
                if !viewModel.showOriginal && viewModel.resultImage != nil {
                    CheckerboardView()
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                
                if viewModel.showOriginal, let original = viewModel.originalImage {
                    Image(nsImage: original)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                } else if let result = viewModel.resultImage {
                    Image(nsImage: result)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                
                if viewModel.isProcessing {
                    ZStack {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(.ultraThinMaterial)
                        VStack(spacing: 8) {
                            ProgressView()
                                .scaleEffect(0.8)
                            Text("Removing background…")
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
            .frame(maxHeight: 260)
            .padding(.horizontal, 16)
            
            // Action buttons
            if viewModel.resultImage != nil {
                HStack(spacing: 8) {
                    Button(action: { viewModel.copyResultToClipboard() }) {
                        Label("Copy", systemImage: "doc.on.doc")
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    
                    Button(action: { viewModel.saveResult() }) {
                        Label("Save PNG", systemImage: "square.and.arrow.down")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                .padding(.bottom, 8)
            }
            
            if let error = viewModel.errorMessage {
                Text(error)
                    .font(.system(size: 11))
                    .foregroundColor(.red)
                    .padding(.horizontal, 16)
            }
        }
    }
    
    // MARK: - Footer
    var footerView: some View {
        HStack {
            Image(systemName: "apple.logo")
                .font(.system(size: 10))
            Text("Uses macOS Vision AI")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
            Spacer()
            Button("Quit") {
                NSApp.terminate(nil)
            }
            .buttonStyle(.plain)
            .font(.system(size: 11))
            .foregroundColor(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial)
    }
}

// MARK: - Checkerboard (transparency indicator)
struct CheckerboardView: View {
    let size: CGFloat = 10
    
    var body: some View {
        Canvas { context, canvasSize in
            let rows = Int(canvasSize.height / size) + 1
            let cols = Int(canvasSize.width / size) + 1
            
            for row in 0..<rows {
                for col in 0..<cols {
                    let isLight = (row + col) % 2 == 0
                    let rect = CGRect(x: CGFloat(col) * size, y: CGFloat(row) * size, width: size, height: size)
                    context.fill(Path(rect), with: .color(isLight ? .white : Color(white: 0.85)))
                }
            }
        }
    }
}
