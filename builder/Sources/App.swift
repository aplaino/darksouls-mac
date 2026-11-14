// Dark Souls Builder: the window, or `Builder --headless /path/to/game`.

import AppKit
import SwiftUI
import UniformTypeIdentifiers

@main
enum Main {
  static func main() {
    let args = CommandLine.arguments
    if let i = args.firstIndex(of: "--headless"), i + 1 < args.count {
      let game = URL(fileURLWithPath: args[i + 1])
      Task { @MainActor in exit(await Builder.headless(game)) }
      dispatchMain()
    }
    BuilderApp.main()
  }
}

struct BuilderApp: App {
  @StateObject private var b = Builder()

  var body: some Scene {
    Window("Dark Souls Builder", id: "main") {
      ContentView(b: b)
        .frame(width: 560)
        .fixedSize(horizontal: false, vertical: true)
    }
    .windowResizability(.contentSize)
  }
}

struct ContentView: View {
  @ObservedObject var b: Builder
  // Plain observable state: @State is a macro the Command Line Tools cannot
  // expand (their SwiftUI has no macro plugin), and the Builder is built
  // without Xcode.
  @StateObject private var ui = UIState()

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      VStack(alignment: .leading, spacing: 4) {
        Text("Dark Souls Builder").font(.title2.bold())
        Text("Builds Dark Souls: Prepare to Die Edition for this Mac from your own copy of the game. "
             + "Nothing of the game is downloaded: its code is translated and compiled here.")
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
      }

      row("1", "Your game (version 1.0.2.0)", b.game, hint: "Drop the game's folder here, the one with DATA inside.") {
        Button("Choose…", action: choose).disabled(b.building)
      }
      row("2", "Apple's Command Line Tools", b.tools, hint: "") {
        if case .bad = b.tools, !b.tools.isBusy {
          Button("Install", action: b.installTools)
        }
      }

      Divider()

      if b.building {
        HStack {
          if b.progress < 0 { ProgressView().controlSize(.small) } else { ProgressView(value: b.progress) }
          Button("Stop", action: b.stop)
        }
        Text(b.step).font(.callout).foregroundStyle(.secondary)
      } else if let app = b.installed {
        HStack {
          Label("\(b.step). Dark Souls is in \(app.deletingLastPathComponent().path).",
                systemImage: "checkmark.circle.fill").foregroundStyle(.green)
          Spacer()
          Button("Open Dark Souls") { NSWorkspace.shared.open(app) }.keyboardShortcut(.defaultAction)
        }
      } else {
        HStack {
          Text("Takes 15 to 30 minutes and about 5 GB of space while it runs.")
            .font(.callout).foregroundStyle(.secondary)
          Spacer()
          Button("Build Dark Souls", action: b.build)
            .keyboardShortcut(.defaultAction)
            .disabled(!b.canBuild)
        }
      }
      if let f = b.failure {
        ScrollView {
          Text(f).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxHeight: 160)
        .foregroundStyle(.red)
      }

      DisclosureGroup("Log", isExpanded: $ui.showLog) {
        ScrollView {
          Text(b.log.joined(separator: "\n"))
            .font(.system(.caption, design: .monospaced))
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(height: 160)
      }
    }
    .padding(20)
    .background(ui.dropping ? Color.accentColor.opacity(0.08) : Color.clear)
    .onDrop(of: [.fileURL], isTargeted: $ui.dropping) { items in
      guard !b.building, let item = items.first else { return false }
      _ = item.loadObject(ofClass: URL.self) { url, _ in
        if let url { Task { @MainActor in await b.setGame(url) } }
      }
      return true
    }
  }

  @ViewBuilder
  private func row<Accessory: View>(_ n: String, _ title: String, _ s: Status, hint: String,
                                    @ViewBuilder accessory: () -> Accessory) -> some View {
    HStack(alignment: .top, spacing: 12) {
      Text(n).font(.headline).frame(width: 22, height: 22).background(Circle().fill(.quaternary))
      VStack(alignment: .leading, spacing: 2) {
        Text(title).font(.headline)
        switch s {
        case .none: Text(hint).foregroundStyle(.secondary)
        case .busy(let t): HStack { ProgressView().controlSize(.small); Text(t) }
        case .ok(let t): Label(t, systemImage: "checkmark.circle.fill").foregroundStyle(.green)
        case .bad(let t): Label(t, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange)
        }
      }
      .font(.callout)
      .fixedSize(horizontal: false, vertical: true)
      Spacer()
      accessory()
    }
  }

  private func choose() {
    let panel = NSOpenPanel()
    panel.canChooseDirectories = true
    panel.canChooseFiles = false
    panel.message = "Choose the Dark Souls folder, the one with DATA inside."
    if panel.runModal() == .OK, let url = panel.url {
      Task { await b.setGame(url) }
    }
  }
}

final class UIState: ObservableObject {
  @Published var dropping = false
  @Published var showLog = false
}
