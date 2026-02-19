import SwiftUI

// MARK: - Tool enum

enum Tool: String, CaseIterable, Identifiable {
    case worldClocks      = "World Clocks"
    case bgRemover        = "BG Remover"
    case clipboardHistory = "Clipboard History"
    case ocr              = "Screenshot to Text"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .worldClocks:      return "clock"
        case .bgRemover:        return "scissors"
        case .clipboardHistory: return "clipboard"
        case .ocr:              return "text.viewfinder"
        }
    }

    var popoverSize: NSSize {
        switch self {
        case .worldClocks:      return NSSize(width: 450, height: 400)
        case .bgRemover:        return NSSize(width: 400, height: 460)
        case .clipboardHistory: return NSSize(width: 360, height: 420)
        case .ocr:              return NSSize(width: 400, height: 420)
        }
    }

    static var homeSize: NSSize { NSSize(width: 340, height: 460) }
}

// MARK: - Tool Order Store

class ToolOrderStore: ObservableObject {
    @Published var order: [String] {
        didSet { save() }
    }

    private let key = "toolOrder"

    init() {
        if let saved = UserDefaults.standard.stringArray(forKey: "toolOrder") {
            // Merge: keep saved order, append any new tools not yet saved
            let allIds = Tool.allCases.map(\.rawValue)
            let merged = saved.filter { allIds.contains($0) } + allIds.filter { !saved.contains($0) }
            self.order = merged
        } else {
            self.order = Tool.allCases.map(\.rawValue)
        }
    }

    var tools: [Tool] {
        order.compactMap { id in Tool.allCases.first { $0.rawValue == id } }
    }

    private func save() {
        UserDefaults.standard.set(order, forKey: key)
    }
}

// MARK: - Main View

struct MainView: View {
    @State private var activeTool: Tool?
    @State private var searchExpanded = false
    @State private var searchText = ""
    @StateObject private var toolOrder = ToolOrderStore()
    var popover: NSPopover?

    var filteredTools: [Tool] {
        if searchText.isEmpty { return toolOrder.tools }
        return toolOrder.tools.filter {
            $0.rawValue.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        Group {
            if let tool = activeTool {
                toolView(for: tool)
            } else {
                homeView
            }
        }
        .animation(.easeInOut(duration: 0.2), value: activeTool)
        .onChange(of: activeTool) { _, newTool in
            popover?.contentSize = newTool?.popoverSize ?? Tool.homeSize
        }
    }

    // MARK: - Home

    var homeView: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                Spacer()
                SearchPill(expanded: $searchExpanded, text: $searchText)
            }
            .padding(.horizontal, 14)
            .padding(.top, 10)
            .padding(.bottom, 4)

            ScrollView(showsIndicators: false) {
                VStack(spacing: 12) {
                    if searchText.isEmpty {
                        // Drag-to-reorder list
                        ForEach(toolOrder.tools) { tool in
                            ToolCard(tool: tool) { activeTool = tool }
                                .onDrag {
                                    NSItemProvider(object: tool.rawValue as NSString)
                                }
                                .onDrop(of: [.text], delegate: ToolDropDelegate(
                                    tool: tool,
                                    store: toolOrder
                                ))
                        }
                    } else {
                        // Search results — no reorder
                        ForEach(filteredTools) { tool in
                            ToolCard(tool: tool) { activeTool = tool }
                        }
                        if filteredTools.isEmpty {
                            Text("No tools found")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                                .frame(height: 80)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
            }

            HStack {
                Text("Hold & drag to reorder")
                    .font(.system(size: 9))
                    .foregroundColor(Color(nsColor: .quaternaryLabelColor))
                Spacer()
                Button(action: { NSApp.terminate(nil) }) {
                    Text("Quit")
                        .font(.system(size: 10))
                        .foregroundColor(Color(nsColor: .tertiaryLabelColor))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 10)
        }
        .frame(width: Tool.homeSize.width, height: Tool.homeSize.height)
    }

    // MARK: - Tool View

    @ViewBuilder
    func toolView(for tool: Tool) -> some View {
        VStack(spacing: 0) {
            HStack {
                Button(action: { activeTool = nil }) {
                    HStack(spacing: 3) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 10, weight: .medium))
                        Text("Back")
                            .font(.system(size: 11))
                    }
                    .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)

                Spacer()

                Text(tool.rawValue)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)

            Divider()

            switch tool {
            case .worldClocks:
                WorldClocksView()
                Spacer(minLength: 0)
            case .bgRemover:
                BGRemoverView()
            case .clipboardHistory:
                ClipboardHistoryView()
            case .ocr:
                OCRView()
            }
        }
        .frame(width: tool.popoverSize.width, height: tool.popoverSize.height, alignment: .top)
    }
}

// MARK: - Drag & Drop Delegate

struct ToolDropDelegate: DropDelegate {
    let tool: Tool
    let store: ToolOrderStore

    func performDrop(info: DropInfo) -> Bool {
        guard let item = info.itemProviders(for: [.text]).first else { return false }
        item.loadObject(ofClass: NSString.self) { reading, _ in
            guard let draggedId = reading as? String,
                  let from = store.order.firstIndex(of: draggedId),
                  let to   = store.order.firstIndex(of: tool.rawValue),
                  from != to else { return }
            DispatchQueue.main.async {
                withAnimation(.easeInOut(duration: 0.2)) {
                    store.order.move(fromOffsets: IndexSet(integer: from), toOffset: to > from ? to + 1 : to)
                }
            }
        }
        return true
    }

    func dropEntered(info: DropInfo) {
        guard let item = info.itemProviders(for: [.text]).first else { return }
        item.loadObject(ofClass: NSString.self) { reading, _ in
            guard let draggedId = reading as? String,
                  let from = store.order.firstIndex(of: draggedId),
                  let to   = store.order.firstIndex(of: tool.rawValue),
                  from != to else { return }
            DispatchQueue.main.async {
                withAnimation(.easeInOut(duration: 0.2)) {
                    store.order.move(fromOffsets: IndexSet(integer: from), toOffset: to > from ? to + 1 : to)
                }
            }
        }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }
}

// MARK: - Search Pill

struct SearchPill: View {
    @Binding var expanded: Bool
    @Binding var text: String
    @State private var isHovered = false
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.secondary)

            if expanded {
                TextField("Search…", text: $text)
                    .textFieldStyle(.plain)
                    .font(.system(size: 11))
                    .focused($isFocused)
                    .onExitCommand { close() }

                if !text.isEmpty {
                    Button(action: { text = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 9))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.horizontal, expanded ? 10 : 6)
        .padding(.vertical, 5)
        .background(Capsule().fill(Color.primary.opacity(isHovered || expanded ? 0.06 : 0.0)))
        .overlay(Capsule().strokeBorder(Color.primary.opacity(expanded ? 0.1 : 0.0), lineWidth: 0.5))
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.15)) { isHovered = hovering }
        }
        .onTapGesture {
            if !expanded {
                withAnimation(.easeOut(duration: 0.2)) { expanded = true }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { isFocused = true }
            }
        }
        .onChange(of: isFocused) { _, focused in
            if !focused && expanded { close() }
        }
        .frame(width: expanded ? 160 : nil)
        .animation(.easeOut(duration: 0.2), value: expanded)
    }

    private func close() {
        withAnimation(.easeOut(duration: 0.2)) {
            text = ""
            expanded = false
            isFocused = false
        }
    }
}

// MARK: - Tool Card

struct ToolCard: View {
    let tool: Tool
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 0) {
                toolPreview
                    .frame(maxWidth: .infinity)
                    .frame(height: 80)
                    .clipped()

                HStack(spacing: 6) {
                    Image(systemName: tool.icon)
                        .font(.system(size: 10, weight: .medium))
                    Text(tool.rawValue)
                        .font(.system(size: 11, weight: .medium))
                    Spacer()
                    Image(systemName: "arrow.right")
                        .font(.system(size: 9, weight: .medium))
                }
                .foregroundColor(.secondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .opacity(isHovered ? 1 : 0)
                .frame(height: isHovered ? nil : 0, alignment: .top)
                .clipped()
            }
            .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(isHovered ? 0.06 : 0.03)))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.primary.opacity(isHovered ? 0.1 : 0.04), lineWidth: 0.5))
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.2)) { isHovered = hovering }
        }
    }

    @ViewBuilder
    var toolPreview: some View {
        switch tool {
        case .worldClocks:      WorldClocksPreview()
        case .bgRemover:        BGRemoverPreview()
        case .clipboardHistory: ClipboardHistoryPreview()
        case .ocr:              OCRPreview()
        }
    }
}

// MARK: - Previews

struct WorldClocksPreview: View {
    @StateObject private var store = TimeZoneStore()
    @State private var now = Date()
    let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        HStack(spacing: 20) {
            ForEach(store.timeZones.prefix(3)) { tz in
                VStack(spacing: 4) {
                    Text(tz.name)
                        .font(.system(size: 8, weight: .medium))
                        .foregroundColor(Color(nsColor: .tertiaryLabelColor))
                        .tracking(1.5)
                    Text(formatted(tz))
                        .font(.system(size: 22, weight: .light, design: .rounded))
                        .monospacedDigit()
                        .foregroundColor(.primary.opacity(0.7))
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onReceive(timer) { _ in now = Date() }
    }

    func formatted(_ tz: WorldTimeZone) -> String {
        let f = DateFormatter()
        if tz.isCustomGMT, let offset = tz.gmtOffset {
            f.timeZone = Foundation.TimeZone(secondsFromGMT: offset)
        } else {
            f.timeZone = Foundation.TimeZone(identifier: tz.identifier)
        }
        f.dateFormat = "HH:mm"
        return f.string(from: now)
    }
}

struct BGRemoverPreview: View {
    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: "rectangle.dashed")
                .font(.system(size: 28, weight: .ultraLight))
                .foregroundColor(.primary.opacity(0.35))
            Text("Drop or paste image")
                .font(.system(size: 9))
                .foregroundColor(Color(nsColor: .tertiaryLabelColor))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
