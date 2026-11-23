import SwiftUI
import UIKit.UIGestureRecognizerSubclass

/// One page of the app, in the order the pages sit side by side.
struct Screen<ID: Hashable>: Identifiable {
    let id: ID
    let title: String
    var icon: String? = nil
}

/// The pages side by side: drag left and right to move between them. Give every page its own NavigationStack
/// with an inline title (a large title loses its left margin here).
struct Screens<ID: Hashable, Content: View>: View {
    let pages: [Screen<ID>]
    /// The default page: the app opens on it and the menu marks it with a star.
    let home: ID
    @Binding var current: ID
    @ViewBuilder let content: (ID) -> Content

    var body: some View {
        // Every page stays alive side by side (HStack, not a lazy pager): a page-style TabView builds pages on
        // the way and, on iOS 27.0 (23 Nov 2026), lost navigation bars on far jumps and crashed in UINavigationBar.
        //
        // Pages take their size from the GeometryReader, not from containerRelativeFrame: after the keyboard had
        // been up once (an inline field, an alert's field, a sheet's), containerRelativeFrame kept a page at its
        // squeezed height, title pushed down and bottom button pulled up, until relaunch (iOS 27.0, 23 Nov 2026).
        GeometryReader { room in
            ScrollViewReader { proxy in
                ScrollView(.horizontal) {
                    HStack(spacing: 0) {
                        ForEach(pages) { page in
                            content(page.id)
                                .environment(\.screenMenu, menu(on: page.id))
                                .frame(width: room.size.width, height: room.size.height)
                                .id(page.id)
                        }
                    }
                    .scrollTargetLayout()
                    .background(RowSwipesFirst())
                }
                .scrollTargetBehavior(.paging)
                .scrollPosition(id: Binding(get: { current }, set: { if let page = $0 { current = page } }))
                .scrollIndicators(.hidden)
                .onAppear {
                    // Open on the current page, not on the first one.
                    proxy.scrollTo(current, anchor: .leading)
                }
                // A page added or removed before the current one shifts it: stay on the current page.
                .onChange(of: pages.map(\.id)) {
                    DispatchQueue.main.async { proxy.scrollTo(current, anchor: .leading) }
                }
            }
        }
        .ignoresSafeArea(.container)
    }

    private func menu(on page: ID) -> ScreenMenuModel {
        ScreenMenuModel(
            rows: pages.map { .init(id: AnyHashable($0.id), title: $0.title, icon: $0.icon) },
            home: AnyHashable(home),
            current: AnyHashable(current),
            page: AnyHashable(page),
            go: { id in
                guard let id = id.base as? ID else { return }
                withAnimation { current = id }
            }
        )
    }
}

/// Row swipes (archive, delete on a list row) and the swipe back go first: the page swipe waits until they fail,
/// which they do at once on a row without actions for that direction, outside a row, and on a first screen. Without this the pager takes
/// every horizontal drag and the row actions never open (iOS 27.0, 23 Nov 2026).
private struct RowSwipesFirst: UIViewRepresentable {
    func makeUIView(context: Context) -> Probe { Probe() }
    func updateUIView(_ view: Probe, context: Context) {}

    /// Sits inside the pager, finds its scroll view and puts the gate on it.
    final class Probe: UIView {
        private weak var pager: UIScrollView?

        override func didMoveToWindow() {
            super.didMoveToWindow()
            guard window != nil, pager == nil else { return }
            var view = superview
            while let candidate = view, !(candidate is UIScrollView) { view = candidate.superview }
            guard let scroll = view as? UIScrollView else { return }
            pager = scroll
            let gate = Gate(target: nil, action: nil)
            gate.pager = scroll
            gate.cancelsTouchesInView = false
            gate.delaysTouchesEnded = false
            scroll.addGestureRecognizer(gate)
        }
    }

    /// Never recognises anything. On each touch it looks at what is under the finger and makes the page swipe
    /// wait for the row-swipe recognisers found there. Lists come and go, so this is done per touch.
    final class Gate: UIGestureRecognizer {
        weak var pager: UIScrollView?
        private let waitingFor = NSHashTable<UIGestureRecognizer>.weakObjects()

        override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
            if let pager {
                var view = touches.first?.view
                while let current = view, current !== pager {
                    for recognizer in current.gestureRecognizers ?? [] where recognizer is UIPanGestureRecognizer {
                        let name = NSStringFromClass(type(of: recognizer))
                        guard Self.first.contains(where: name.contains), !waitingFor.contains(recognizer) else { continue }
                        pager.panGestureRecognizer.require(toFail: recognizer)
                        waitingFor.add(recognizer)
                    }
                    view = current.superview
                }
            }
            state = .failed
        }

        /// Seen under the finger on iOS 27.0: `_UISwipeActionPanGestureRecognizer` (row actions) on the list and
        /// `_UIParallaxTransitionPanGestureRecognizer` (swipe back) on a navigation stack. A name that no longer
        /// matches only means that swipe loses to the page swipe again.
        static let first = ["SwipeAction", "ParallaxTransition"]
    }
}

/// What the menu button on a page needs to know. `Screens` hands it to every page.
struct ScreenMenuModel {
    struct Row: Identifiable {
        let id: AnyHashable
        let title: String
        let icon: String?
    }
    var rows: [Row]
    var home: AnyHashable
    var current: AnyHashable
    /// The page this copy was handed to.
    var page: AnyHashable
    var go: (AnyHashable) -> Void
}

private struct ScreenMenuKey: EnvironmentKey {
    static let defaultValue: ScreenMenuModel? = nil
}

extension EnvironmentValues {
    var screenMenu: ScreenMenuModel? {
        get { self[ScreenMenuKey.self] }
        set { self[ScreenMenuKey.self] = newValue }
    }
}

/// The menu button. Put it last in the top right of every page.
struct ScreenMenuButton: View {
    @Environment(\.screenMenu) private var menu
    @State private var open = false

    var body: some View {
        if let menu {
            Button { open = true } label: { Image(systemName: "line.3.horizontal") }
                .accessibilityLabel("Screens")
                .accessibilityIdentifier("screen-menu")
                .popover(isPresented: $open, arrowEdge: .top) {
                    ScreenMenu(menu: menu) { open = false }
                        .presentationCompactAdaptation(.popover)
                }
        }
    }
}

/// Every page in app order: a star on the default one, the current one highlighted, search, tap to jump.
struct ScreenMenu: View {
    let menu: ScreenMenuModel
    let close: () -> Void
    @State private var query = ""
    private let rowHeight: CGFloat = 42

    private var rows: [ScreenMenuModel.Row] {
        let words = query.trimmingCharacters(in: .whitespaces)
        return words.isEmpty ? menu.rows : menu.rows.filter { $0.title.localizedCaseInsensitiveContains(words) }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search", text: $query)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.go)
                    .onSubmit { if let first = rows.first { jump(first.id) } }
                    .accessibilityIdentifier("screen-search")
            }
            .font(.subheadline)
            .padding(.horizontal, 14)
            .frame(height: rowHeight)
            Divider()
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(rows) { row in line(row).id(row.id) }
                        if rows.isEmpty {
                            Text("No screen").font(.subheadline).foregroundStyle(.secondary).frame(height: rowHeight)
                        }
                    }
                }
                .onAppear { proxy.scrollTo(menu.current, anchor: .center) }
            }
            // The full list sets the height, so the menu does not jump while typing.
            .frame(height: min(CGFloat(menu.rows.count) * rowHeight, 420))
        }
        .frame(width: 250)
    }

    private func line(_ row: ScreenMenuModel.Row) -> some View {
        let current = row.id == menu.current
        let home = row.id == menu.home
        return Button { jump(row.id) } label: {
            HStack(spacing: 10) {
                if menu.rows.contains(where: { $0.icon != nil }) {
                    Image(systemName: row.icon ?? "circle").opacity(row.icon == nil ? 0 : 1).frame(width: 22)
                }
                Text(row.title).lineLimit(1).fontWeight(current ? .semibold : .regular)
                Spacer(minLength: 8)
                if home {
                    Image(systemName: "star.fill").font(.footnote).foregroundStyle(.yellow)
                }
            }
            .padding(.horizontal, 14)
            .frame(height: rowHeight)
            .foregroundStyle(current ? AnyShapeStyle(.tint) : AnyShapeStyle(.primary))
            .background(current ? AnyShapeStyle(.tint.opacity(0.16)) : AnyShapeStyle(.clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(home ? "\(row.title), default" : row.title)
        .accessibilityIdentifier("screen-\(row.title)")
        .accessibilityAddTraits(current ? .isSelected : [])
    }

    private func jump(_ id: AnyHashable) {
        close()
        menu.go(id)
    }
}
