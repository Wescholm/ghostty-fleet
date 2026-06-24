import SwiftUI
import UniformTypeIdentifiers

// MARK: - SidebarTheme

struct SidebarTheme: Equatable {
    let background: Color
    let foreground: Color
    let secondaryText: Color
    let activeTabBackground: Color
    let attentionColor: Color

    /// Create from Ghostty terminal colors.
    static func from(background: NSColor, foreground: NSColor) -> SidebarTheme {
        let bgLuminance = background.luminance
        let sidebarBg: Color
        if bgLuminance > 0.5 {
            // Light theme: darken sidebar slightly
            sidebarBg = Color(nsColor: background.darken(by: 0.05))
        } else {
            // Dark theme: lighten sidebar slightly
            sidebarBg = Color(nsColor: background.blended(withFraction: 0.08, of: NSColor.white) ?? background)
        }

        let fg = Color(nsColor: foreground)

        return SidebarTheme(
            background: sidebarBg,
            foreground: fg,
            secondaryText: fg.opacity(0.6),
            activeTabBackground: fg.opacity(0.12),
            attentionColor: .orange
        )
    }

    /// Sensible default when no terminal colors are available yet.
    static var `default`: SidebarTheme {
        SidebarTheme(
            background: Color(nsColor: .controlBackgroundColor),
            foreground: .primary,
            secondaryText: .secondary,
            activeTabBackground: Color.accentColor.opacity(0.12),
            attentionColor: .orange
        )
    }
}

// MARK: - SidebarField

enum SidebarField: String, Hashable {
    case title
    case directory
    case gitBranch = "git-branch"
    case status

    static let defaultFields: Set<SidebarField> = [.title, .directory, .gitBranch, .status]
}

// MARK: - SidebarView

/// A vertical sidebar that displays the list of tabs for the current window group.
struct SidebarView: View {
    @ObservedObject var tabManager: SidebarTabManager
    var theme: SidebarTheme
    var fields: Set<SidebarField> = SidebarField.defaultFields

    /// Top clearance (points) the first card needs so it doesn't sit under the floating traffic
    /// lights when the window uses the hidden titlebar style. Zero for other styles, whose content
    /// already sits below a real titlebar. Set by TerminalController.sidebarTopInset(for:).
    var topInset: CGFloat = 0

    /// When true, the sidebar is hosted on a Liquid Glass pane (an `NSGlassEffectView` whose
    /// `contentView` is this view's host), so the view draws a CLEAR background and lets the glass
    /// material show through — the macOS-26 navigation layer. False (Reduce Transparency, or a
    /// pre-26 fallback) keeps the opaque solid `theme.background`. Set by TerminalController.
    var glassActive: Bool = false

    @AppStorage("SidebarShowCardBorder") private var showCardBorder: Bool = true
    @AppStorage("SidebarDimInactiveColors") private var dimInactiveColors: Bool = false
    @State private var draggingTabID: UUID?
    @State private var dropTargetTabID: UUID?

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 4) {
                ForEach(Array(tabManager.tabs.enumerated()), id: \.element.id) { index, tab in
                    SidebarTabCard(tab: tab, theme: theme, fields: fields, showCardBorder: showCardBorder, dimInactive: dimInactiveColors, glassActive: glassActive)
                        .contentShape(Rectangle())
                        .opacity(draggingTabID == tab.id ? 0.4 : 1.0)
                        .overlay(alignment: .top) {
                            if dropTargetTabID == tab.id && draggingTabID != tab.id {
                                Rectangle()
                                    .fill(Color.accentColor)
                                    .frame(height: 2)
                                    .offset(y: -3)
                            }
                        }
                        .onTapGesture {
                            tabManager.selectTab(tab)
                        }
                        .onDrag {
                            draggingTabID = tab.id
                            return NSItemProvider(object: "\(index)" as NSString)
                        }
                        .onDrop(of: [UTType.text], delegate: TabDropDelegate(
                            tabManager: tabManager,
                            currentTab: tab,
                            currentIndex: index,
                            draggingTabID: $draggingTabID,
                            dropTargetTabID: $dropTargetTabID
                        ))
                        .contextMenu {
                            Button("Rename Tab...") {
                                tabManager.promptRenameTab(tab)
                            }

                            Divider()

                            Menu("Tab Color") {
                                ForEach(TerminalTabColor.allCases, id: \.self) { color in
                                    Button {
                                        tabManager.setTabColor(color, for: tab)
                                    } label: {
                                        Label {
                                            Text(color.localizedName)
                                        } icon: {
                                            Image(nsImage: color.swatchImage(selected: color == tab.tabColor))
                                        }
                                    }
                                }
                            }

                            Toggle("Show Tab Border", isOn: $showCardBorder)
                            Toggle("Dim Inactive Tab Colors", isOn: $dimInactiveColors)

                            Divider()

                            Button("Close Tab") {
                                tabManager.closeTab(tab)
                            }

                            Button("Close Other Tabs") {
                                tabManager.closeOtherTabs(tab)
                            }
                            .disabled(tabManager.tabs.count <= 1)

                            Button("Close Tabs to the Right") {
                                tabManager.closeTabsToTheRight(of: tab)
                            }
                            .disabled({
                                guard let idx = tabManager.tabs.firstIndex(where: { $0.id == tab.id }) else { return true }
                                return idx >= tabManager.tabs.count - 1
                            }())
                        }
                }
            }
            .padding(.horizontal, 8)
            .padding(.top, max(8, topInset))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            // On a Liquid Glass pane the glass provides the backdrop, so stay clear and let it show
            // through. Under Reduce Transparency / fallback, paint the opaque solid theme background.
            if !glassActive { theme.background }
        }
    }
}

// MARK: - TabDropDelegate

private struct TabDropDelegate: DropDelegate {
    let tabManager: SidebarTabManager
    let currentTab: SidebarTabManager.TabItem
    let currentIndex: Int
    @Binding var draggingTabID: UUID?
    @Binding var dropTargetTabID: UUID?

    func dropEntered(info: DropInfo) {
        dropTargetTabID = currentTab.id
    }

    func dropExited(info: DropInfo) {
        if dropTargetTabID == currentTab.id {
            dropTargetTabID = nil
        }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func validateDrop(info: DropInfo) -> Bool {
        draggingTabID != nil && draggingTabID != currentTab.id
    }

    func performDrop(info: DropInfo) -> Bool {
        guard let draggingTabID else { return false }
        guard let sourceIndex = tabManager.tabs.firstIndex(where: { $0.id == draggingTabID }) else { return false }

        tabManager.moveTab(from: sourceIndex, to: currentIndex)

        self.draggingTabID = nil
        self.dropTargetTabID = nil
        return true
    }
}

// MARK: - SidebarTabCard

private struct SidebarTabCard: View {
    let tab: SidebarTabManager.TabItem
    let theme: SidebarTheme
    let fields: Set<SidebarField>
    var showCardBorder: Bool = true
    var dimInactive: Bool = false

    var glassActive: Bool = false

    @State private var isHovered = false

    private static let cardRadius: CGFloat = 8

    /// Compact "↑2 ↓1" upstream divergence label.
    private static func aheadBehind(ahead: Int, behind: Int) -> String {
        var s = ""
        if ahead > 0 { s += "↑\(ahead)" }
        if behind > 0 { s += (s.isEmpty ? "" : " ") + "↓\(behind)" }
        return s
    }

    /// The fill for the SELECTED row — a bold rounded highlight in the macOS sidebar style (Notes /
    /// Finder / Xcode): the tab's own color when set, otherwise the system accent.
    private var selectionFill: Color {
        if let nsColor = tab.tabColor.displayColor { return Color(nsColor: nsColor) }
        return .accentColor
    }

    /// Card background: the bold selection fill when selected, a faint wash on hover, otherwise clear so
    /// the sidebar material shows through.
    private var cardFill: Color {
        if tab.isSelected { return selectionFill }
        if isHovered { return Color.primary.opacity(glassActive ? 0.10 : 0.06) }
        return .clear
    }

    /// Primary (title) color — white on the filled selection for contrast, else the theme foreground.
    private var primaryColor: Color { tab.isSelected ? .white : theme.foreground }

    /// Secondary (dir / branch / status) color — a readable white on the selection, else the theme's.
    private var secondaryColor: Color { tab.isSelected ? .white.opacity(0.85) : theme.secondaryText }

    /// The left color strip, shown only for UNSELECTED colored tabs (a selected tab's fill is its color).
    private var accentStrip: Color {
        guard !tab.isSelected, let nsColor = tab.tabColor.displayColor else { return .clear }
        let base = Color(nsColor: nsColor)
        return dimInactive ? base.opacity(0.55) : base
    }

    /// The border color for the thin card border — always neutral gray.
    private var cardBorderColor: Color {
        Color(nsColor: .separatorColor).opacity(0.3)
    }

    /// Color for the lifecycle status dot, or `nil` for `.idle` (no dot). Attention reuses the theme's
    /// attention color (orange); the rest are fixed semantic colors.
    static func statusColor(_ status: SessionStatus, theme: SidebarTheme) -> Color? {
        switch status {
        case .attention: return theme.attentionColor   // bell / notify
        case .error:     return .red
        case .waiting:   return .yellow                 // agent blocked on the user
        case .running:   return .green                  // agent/CPU working
        case .done:      return .blue                   // agent finished
        case .idle:      return nil
        }
    }

    var body: some View {
        HStack(spacing: 0) {
            // Left color accent strip — uses UnevenRoundedRectangle so it
            // follows the card's left-side rounding while staying flat on the right.
            UnevenRoundedRectangle(
                topLeadingRadius: Self.cardRadius,
                bottomLeadingRadius: Self.cardRadius,
                bottomTrailingRadius: 0,
                topTrailingRadius: 0
            )
            .fill(accentStrip)
            .frame(width: 5)

            VStack(alignment: .leading, spacing: 4) {
                // Title (always shown — attention dot lives here)
                if fields.contains(.title) {
                    HStack(spacing: 6) {
                        Text(tab.displayTitle)
                            .font(.system(size: 12, weight: tab.isSelected ? .semibold : .regular))
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .foregroundColor(primaryColor)

                        Spacer()

                        // Single lifecycle status dot (color = state). `.idle` shows nothing.
                        if let statusColor = Self.statusColor(tab.status, theme: theme) {
                            Circle()
                                .fill(statusColor)
                                .frame(width: 8, height: 8)
                                .help(tab.status.rawValue)
                        }
                    }
                }

                // Directory name
                if fields.contains(.directory), let dir = tab.directoryName {
                    HStack(spacing: 4) {
                        Image(systemName: "folder")
                            .font(.system(size: 9))
                            .foregroundColor(secondaryColor)
                        Text(dir)
                            .font(.system(size: 10))
                            .foregroundColor(secondaryColor)
                            .lineLimit(1)
                    }
                }

                // Git branch (+ dirty dot and ahead/behind)
                if fields.contains(.gitBranch), let branch = tab.gitBranch {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.triangle.branch")
                            .font(.system(size: 9))
                            .foregroundColor(secondaryColor)
                        Text(branch)
                            .font(.system(size: 10))
                            .foregroundColor(secondaryColor)
                            .lineLimit(1)
                        if tab.gitDirty {
                            // Uncommitted changes
                            Circle()
                                .fill(secondaryColor)
                                .frame(width: 4, height: 4)
                        }
                        if tab.gitAhead > 0 || tab.gitBehind > 0 {
                            Text(Self.aheadBehind(ahead: tab.gitAhead, behind: tab.gitBehind))
                                .font(.system(size: 9))
                                .foregroundColor(secondaryColor)
                                .lineLimit(1)
                        }
                    }
                }

                // Status entries
                if fields.contains(.status), !tab.statusEntries.isEmpty {
                    ForEach(tab.statusEntries, id: \.key) { entry in
                        HStack(spacing: 4) {
                            if let icon = entry.icon {
                                Image(systemName: icon)
                                    .font(.system(size: 9))
                                    .foregroundColor(secondaryColor)
                            }
                            Text(entry.value)
                                .font(.system(size: 10))
                                .foregroundColor(secondaryColor)
                                .lineLimit(1)
                        }
                    }
                }
            }
            .padding(.vertical, 8)
            .padding(.leading, 8)
            .padding(.trailing, 10)
        }
        .clipShape(RoundedRectangle(cornerRadius: Self.cardRadius))
        .background(
            RoundedRectangle(cornerRadius: Self.cardRadius)
                .fill(cardFill)
                // A subtle drop shadow lifts the selected row off the sidebar material (depth/elevation).
                .shadow(color: tab.isSelected ? selectionFill.opacity(0.35) : .clear, radius: 4, y: 1)
        )
        .overlay(
            Group {
                // The hairline border competes with a filled selection and the sidebar vibrancy, so it's
                // dropped on the selected row and whenever the glass/vibrancy pane is active (the clean
                // borderless macOS sidebar look). It stays available for the Reduce-Transparency fallback.
                if showCardBorder && !tab.isSelected && !glassActive {
                    RoundedRectangle(cornerRadius: Self.cardRadius)
                        .strokeBorder(cardBorderColor, lineWidth: 1)
                }
            }
        )
        .onHover { isHovered = $0 }
        .animation(.easeOut(duration: 0.12), value: tab.isSelected)
        .animation(.easeOut(duration: 0.12), value: isHovered)
    }
}

// MARK: - Preview

#if DEBUG
private func previewTab(
    _ title: String,
    dir: String,
    branch: String?,
    dirty: Bool = false,
    ahead: Int = 0,
    behind: Int = 0,
    selected: Bool = false,
    state: SessionStatus = .idle,
    color: TerminalTabColor = .none,
    status: [TabMetadataStore.StatusEntry] = []
) -> SidebarTabManager.TabItem {
    return SidebarTabManager.TabItem(
        id: UUID(),
        title: title,
        pwd: "/Users/me/\(dir)",
        gitBranch: branch,
        gitDirty: dirty,
        gitAhead: ahead,
        gitBehind: behind,
        surfaceId: UUID(),
        statusEntries: status,
        isSelected: selected,
        status: state,
        tabColor: color
    )
}

#Preview("Sidebar — states") {
    SidebarView(
        tabManager: SidebarTabManager(previewTabs: [
            previewTab("api-server", dir: "api", branch: "main", dirty: true, selected: true, state: .running),
            previewTab("Claude: refactor auth flow", dir: "webapp", branch: "feature/auth",
                       ahead: 2, state: .waiting, color: .blue),
            previewTab("npm test — watch", dir: "webapp-wt", branch: "fix/flaky-spec",
                       behind: 1, state: .running, color: .green),
            previewTab("deploy", dir: "infra", branch: "release/v2", dirty: true, ahead: 1, behind: 3,
                       state: .error, status: [.init(key: "port", value: ":3000", icon: "network")]),
            previewTab("build core", dir: "core", branch: "main", state: .done),
            previewTab("bell rang", dir: "logs", branch: nil, state: .attention),
            previewTab("idle shell", dir: "dotfiles", branch: "main"),
        ]),
        theme: .default
    )
    .frame(width: 250, height: 460)
}
#endif
