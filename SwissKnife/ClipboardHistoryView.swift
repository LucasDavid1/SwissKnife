import SwiftUI
import AppKit

// MARK: - Model

enum ClipboardContent: Equatable {
    case text(String)
    case image(NSImage)

    static func == (lhs: ClipboardContent, rhs: ClipboardContent) -> Bool {
        switch (lhs, rhs) {
        case (.text(let a), .text(let b)): return a == b
        case (.image(let a), .image(let b)): return a === b
        default: return false
        }
    }
}

struct ClipboardItem: Identifiable, Equatable {
    let id = UUID()
    let content: ClipboardContent
    let date: Date

    var isImage: Bool {
        if case .image = content { return true }
        return false
    }

    var textValue: String? {
        if case .text(let t) = content { return t }
        return nil
    }

    var imageValue: NSImage? {
        if case .image(let img) = content { return img }
        return nil
    }

    var searchText: String {
        textValue ?? "[image]"
    }
}

// MARK: - Store

class ClipboardStore: ObservableObject {
    @Published var items: [ClipboardItem] = []

    private let maxItems = 50
    private var lastChangeCount = -1
    private var timer: Timer?

    init() {
        captureCurrentClipboard()
        startPolling()
    }

    deinit { timer?.invalidate() }

    private func startPolling() {
        let t = Timer(timeInterval: 0.8, repeats: true) { [weak self] _ in
            self?.checkClipboard()
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func captureCurrentClipboard() {
        let pb = NSPasteboard.general
        lastChangeCount = pb.changeCount
        if let item = readItem(from: pb) {
            items.append(item)
        }
    }

    private func checkClipboard() {
        let pb = NSPasteboard.general
        guard pb.changeCount != lastChangeCount else { return }
        lastChangeCount = pb.changeCount

        guard let item = readItem(from: pb) else { return }

        // Deduplicate
        if let last = items.first {
            if case .text(let newText) = item.content, case .text(let lastText) = last.content, newText == lastText { return }
        }

        items.insert(item, at: 0)
        if items.count > maxItems { items = Array(items.prefix(maxItems)) }
    }

    private func readItem(from pb: NSPasteboard) -> ClipboardItem? {
        // Prefer image
        if let image = NSImage(pasteboard: pb), image.size != .zero {
            return ClipboardItem(content: .image(image), date: Date())
        }
        // Fallback to text
        if let text = pb.string(forType: .string), !text.isEmpty {
            return ClipboardItem(content: .text(text), date: Date())
        }
        return nil
    }

    func copy(_ item: ClipboardItem) {
        let pb = NSPasteboard.general
        pb.clearContents()
        switch item.content {
        case .text(let t):
            pb.setString(t, forType: .string)
        case .image(let img):
            pb.writeObjects([img])
        }
        lastChangeCount = pb.changeCount
    }

    func remove(_ item: ClipboardItem) {
        items.removeAll { $0.id == item.id }
    }

    func clear() { items.removeAll() }
}

// MARK: - View

struct ClipboardHistoryView: View {
    @EnvironmentObject private var store: ClipboardStore
    @State private var copiedId: UUID?
    @State private var searchText = ""

    var filtered: [ClipboardItem] {
        if searchText.isEmpty { return store.items }
        return store.items.filter { $0.searchText.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                TextField("Search…", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                if !store.items.isEmpty {
                    Button(action: { store.clear() }) {
                        Text("Clear all")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)

            Divider()

            if store.items.isEmpty {
                VStack(spacing: 8) {
                    Spacer()
                    Image(systemName: "clipboard")
                        .font(.system(size: 28, weight: .ultraLight))
                        .foregroundColor(.secondary.opacity(0.5))
                    Text("Nothing copied yet")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(filtered) { item in
                            ClipboardRowView(
                                item: item,
                                isCopied: copiedId == item.id,
                                onCopy: {
                                    store.copy(item)
                                    withAnimation { copiedId = item.id }
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                                        withAnimation { copiedId = nil }
                                    }
                                },
                                onDelete: { store.remove(item) }
                            )
                            Divider().padding(.leading, 14)
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Row

struct ClipboardRowView: View {
    let item: ClipboardItem
    let isCopied: Bool
    let onCopy: () -> Void
    let onDelete: () -> Void

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 10) {
            // Content
            if let img = item.imageValue {
                Image(nsImage: img)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 48, height: 36)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                    .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5))

                VStack(alignment: .leading, spacing: 2) {
                    Text("Image")
                        .font(.system(size: 12))
                        .foregroundColor(.primary)
                    Text("\(Int(img.size.width))×\(Int(img.size.height))")
                        .font(.system(size: 9))
                        .foregroundColor(.secondary)
                    Text(item.date, style: .relative)
                        .font(.system(size: 9))
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

            } else if let text = item.textValue {
                VStack(alignment: .leading, spacing: 2) {
                    Text(text.trimmingCharacters(in: .whitespacesAndNewlines))
                        .font(.system(size: 12))
                        .lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text(item.date, style: .relative)
                        .font(.system(size: 9))
                        .foregroundColor(.secondary)
                }
            }

            Spacer(minLength: 4)

            // Actions
            if isHovered {
                HStack(spacing: 6) {
                    Button(action: onDelete) {
                        Image(systemName: "trash")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)

                    Button(action: onCopy) {
                        Image(systemName: isCopied ? "checkmark" : "doc.on.doc")
                            .font(.system(size: 10))
                            .foregroundColor(isCopied ? .green : .accentColor)
                    }
                    .buttonStyle(.plain)
                }
                .transition(.opacity)
            } else if isCopied {
                Image(systemName: "checkmark")
                    .font(.system(size: 10))
                    .foregroundColor(.green)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(isHovered ? Color.primary.opacity(0.04) : Color.clear)
        .contentShape(Rectangle())
        .onTapGesture { onCopy() }
        .onHover { isHovered = $0 }
        .animation(.easeOut(duration: 0.15), value: isHovered)
    }
}

// MARK: - Preview Card

struct ClipboardHistoryPreview: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            ForEach(["Hello world", "https://example.com", "Some copied text..."], id: \.self) { text in
                HStack(spacing: 6) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.primary.opacity(0.08))
                        .frame(width: 4, height: 14)
                    Text(text)
                        .font(.system(size: 9))
                        .foregroundColor(.primary.opacity(0.5))
                        .lineLimit(1)
                }
            }
        }
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }
}
