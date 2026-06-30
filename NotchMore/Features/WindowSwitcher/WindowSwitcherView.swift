import SwiftUI

struct WindowSwitcherView: View {
    @ObservedObject var manager = WindowSwitcherManager.shared

    private var maxSwitcherWidth: CGFloat {
        WindowSwitcherLayout.maxWidth
    }

    private var switcherWidth: CGFloat {
        let columns = CGFloat(columnCount)
        let contentWidth = (columns * WindowSwitcherLayout.cardWidth)
            + (max(columns - 1, 0) * WindowSwitcherLayout.gridSpacing)
        return min(maxSwitcherWidth, contentWidth + (WindowSwitcherLayout.sidePadding * 2))
    }

    private var switcherHeight: CGFloat {
        WindowSwitcherLayout.height
    }

    private var maxColumnCount: Int {
        let availableContentWidth = maxSwitcherWidth - (WindowSwitcherLayout.sidePadding * 2)
        let fittedColumns = Int(
            (availableContentWidth + WindowSwitcherLayout.gridSpacing)
                / (WindowSwitcherLayout.cardWidth + WindowSwitcherLayout.gridSpacing)
        )
        return max(1, fittedColumns)
    }

    private var columnCount: Int {
        max(1, min(manager.windows.count, maxColumnCount))
    }

    private var gridColumns: [GridItem] {
        Array(
            repeating: GridItem(
                .fixed(WindowSwitcherLayout.cardWidth),
                spacing: WindowSwitcherLayout.gridSpacing,
                alignment: .top
            ),
            count: columnCount
        )
    }

    private var selectedWindowID: CGWindowID? {
        guard manager.windows.indices.contains(manager.selectedIndex) else { return nil }
        return manager.windows[manager.selectedIndex].id
    }
    
    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                LazyVGrid(
                    columns: gridColumns,
                    alignment: .center,
                    spacing: WindowSwitcherLayout.gridSpacing
                ) {
                    ForEach(manager.windows, id: \.id) { window in
                        VStack {
                            if let image = window.snapshot {
                                Image(nsImage: image)
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .frame(height: 120)
                                    .cornerRadius(8)
                                    .shadow(radius: 4)
                            } else if let icon = window.appIcon {
                                Image(nsImage: icon)
                                    .resizable()
                                    .frame(width: 64, height: 64)
                            } else {
                                Image(systemName: "app.window")
                                    .resizable()
                                    .frame(width: 64, height: 64)
                                    .foregroundColor(.gray)
                            }
                            
                            HStack {
                                if let icon = window.appIcon {
                                    Image(nsImage: icon)
                                        .resizable()
                                        .frame(width: 16, height: 16)
                                }
                                Text(window.appName)
                                    .font(.caption)
                                    .fontWeight(.semibold)
                                    .lineLimit(1)
                            }
                            .padding(.top, 4)
                        }
                        .padding()
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(selectedWindowID == window.id ? Color.accentColor.opacity(0.2) : Color.clear)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(selectedWindowID == window.id ? Color.accentColor : Color.clear, lineWidth: 3)
                        )
                        .frame(width: WindowSwitcherLayout.cardWidth)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            if let tappedIndex = manager.windows.firstIndex(where: { $0.id == window.id }) {
                                let selectedWindow = manager.windows[tappedIndex]
                                manager.selectedIndex = tappedIndex
                                manager.activateWindowInfo(selectedWindow)
                            }
                        }
                        .id(window.id)
                    }
                }
                .padding(.horizontal, WindowSwitcherLayout.sidePadding)
                .padding(.vertical, 30)
            }
            .frame(width: switcherWidth)
            .frame(maxHeight: switcherHeight)
            .onChange(of: manager.selectedIndex) { _, _ in
                if manager.windows.indices.contains(manager.selectedIndex) {
                    proxy.scrollTo(manager.windows[manager.selectedIndex].id, anchor: .center)
                }
            }
        }
        .background(
            VisualEffectView(material: .hudWindow, blendingMode: .behindWindow)
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        )
        .shadow(radius: 20)
    }
}

enum WindowSwitcherLayout {
    static let cardWidth: CGFloat = 200
    static let gridSpacing: CGFloat = 20
    static let sidePadding: CGFloat = 28

    static var maxWidth: CGFloat {
        let screenWidth = NSScreen.main?.visibleFrame.width ?? 1200
        return min(screenWidth * 0.88, 1280)
    }

    static var height: CGFloat {
        let screenHeight = NSScreen.main?.visibleFrame.height ?? 900
        return min(screenHeight * 0.72, 760)
    }

    static func width(forWindowCount count: Int) -> CGFloat {
        let availableContentWidth = maxWidth - (sidePadding * 2)
        let fittedColumns = Int((availableContentWidth + gridSpacing) / (cardWidth + gridSpacing))
        let columns = CGFloat(max(1, min(count, max(1, fittedColumns))))
        let contentWidth = (columns * cardWidth) + (max(columns - 1, 0) * gridSpacing)
        return min(maxWidth, contentWidth + (sidePadding * 2))
    }
}


struct VisualEffectView: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blendingMode: NSVisualEffectView.BlendingMode
    
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        return view
    }
    
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
    }
}
