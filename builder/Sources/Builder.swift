// What the Builder does: checks the game and Apple's developer tools, then
// translates the player's own DATA.exe, compiles and links it against the
// kit and puts Dark Souls.app in Applications.
//
// The kit (Contents/Resources/kit, made by builder/make_builder.sh) holds
// everything that is not the game's code, already built:
//   bin/                recomp_lift (and the library it loads), upx
//   symbols/, manifest/ what the lifter reads
//   src/, include/      the port's main.cpp, the runtime's and SDL's headers
//   app/                Dark Souls.app without its executable
//   recipe.json         the compile and link commands (make_recipe.py)

import AppKit
import CryptoKit
import Foundation

enum Status: Equatable {
  case none, busy(String), ok(String), bad(String)
  var isBusy: Bool { if case .busy = self { return true } else { return false } }
}

struct Failure: LocalizedError {
  let errorDescription: String?
  init(_ s: String) { errorDescription = s }
}

struct Recipe: Decodable {
  struct Unit: Decodable {
    let src: String
    let args: [String]
  }
  let clang: Int
  let units: [Unit]
  let lifted: [String]
  let link: [String]
}

enum Kit {
  static var root: URL { Bundle.main.resourceURL!.appendingPathComponent("kit") }
  static func path(_ rel: String) -> String { root.appendingPathComponent(rel).path }
  static let appName = "DarkSouls.app"
  /// DATA.exe 1.0.2.0, the one version the port runs.
  static let exeSHA256 = "44d2dccb1d522f8a320784381ecf83aeb62643d0fc38ae2f4ddf3ca066b52b6c"
  static func recipe() throws -> Recipe {
    try JSONDecoder().decode(Recipe.self, from: Data(contentsOf: root.appendingPathComponent("recipe.json")))
  }
}

@MainActor
final class Builder: ObservableObject {
  @Published var gameFolder: URL?
  @Published var game: Status = .none
  @Published var tools: Status = .none
  @Published var building = false
  @Published var step = ""
  @Published var progress: Double = 0  // 0...1; negative: no count for this step
  @Published var installed: URL?
  @Published var failure: String?
  @Published var log: [String] = []

  // BUILDER_WORK, BUILDER_DEST: another work folder and destination (tests).
  nonisolated static let work = ProcessInfo.processInfo.environment["BUILDER_WORK"].map { URL(fileURLWithPath: $0) }
    ?? FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
      .appendingPathComponent("Dark Souls Builder")
  nonisolated static let destination = ProcessInfo.processInfo.environment["BUILDER_DEST"] ?? "/Applications"
  private var task: Task<Void, Never>?
  private var toolsTimer: Timer?
  var echo = false  // headless: the log goes to stdout too

  var canBuild: Bool {
    if building { return false }
    if case .ok = game, case .ok = tools { return true }
    return false
  }

  init() {
    if let saved = UserDefaults.standard.string(forKey: "GameFolder") {
      Task { await setGame(URL(fileURLWithPath: saved)) }
    }
    Task { await checkTools() }
    NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification, object: nil,
                                           queue: .main) { [weak self] _ in
      MainActor.assumeIsolated { self?.task?.cancel() }
    }
  }

  func say(_ line: String) {
    if echo { print(line) }
    log.append(line)
    if log.count > 500 { log.removeFirst(log.count - 500) }
  }

  // MARK: The game

  /// The dropped or chosen folder: the one with DATA/, DATA/ itself or DATA.exe.
  func setGame(_ url: URL) async {
    let fm = FileManager.default
    var folder = url
    if url.lastPathComponent.lowercased() == "data.exe" { folder = url.deletingLastPathComponent() }
    if folder.lastPathComponent.uppercased() == "DATA" { folder = folder.deletingLastPathComponent() }
    let data = folder.appendingPathComponent("DATA")
    let exe = data.appendingPathComponent("DATA.exe")
    guard fm.fileExists(atPath: exe.path) else {
      game = .bad("No DATA/DATA.exe here. Drop the folder Dark Souls is installed in (the one with DATA inside).")
      return
    }
    for f in ["fmodex.dll", "fmod_event.dll"] where !fm.fileExists(atPath: data.appendingPathComponent(f).path) {
      game = .bad("DATA/\(f) is missing: drop the whole installed game.")
      return
    }
    gameFolder = folder
    game = .busy("Checking DATA.exe…")
    let hash = await Task.detached { Builder.sha256(exe) }.value
    guard gameFolder == folder else { return }
    if hash == Kit.exeSHA256 {
      game = .ok("DATA.exe 1.0.2.0: \(folder.path)")
      UserDefaults.standard.set(folder.path, forKey: "GameFolder")
    } else {
      game = .bad("This DATA.exe is not version 1.0.2.0, the Games for Windows LIVE build the port runs. "
                  + "The current Steam version has a different executable and is not supported yet.")
    }
  }

  nonisolated static func sha256(_ url: URL) -> String {
    guard let h = try? FileHandle(forReadingFrom: url) else { return "" }
    defer { try? h.close() }
    var hasher = SHA256()
    while let chunk = try? h.read(upToCount: 1 << 22), !chunk.isEmpty { hasher.update(data: chunk) }
    return hasher.finalize().map { String(format: "%02x", $0) }.joined()
  }

  // MARK: Apple's developer tools

  func checkTools() async {
    // xcode-select -p never opens Apple's installer; xcrun would.
    guard await Run.line("/usr/bin/xcode-select", ["-p"]) != nil,
          let sdk = await Run.line("/usr/bin/xcrun", ["--show-sdk-path"]) else {
      if !tools.isBusy {
        tools = .bad("Apple's Command Line Tools are needed to compile the game (free, about 1 GB).")
      }
      return
    }
    toolsTimer?.invalidate()
    toolsTimer = nil
    let want = (try? Kit.recipe().clang) ?? 0
    let version = await Run.run("/usr/bin/xcrun", ["clang++", "--version"]).output
    let have = version.range(of: #"clang version \d+"#, options: .regularExpression)
      .flatMap { Int(version[$0].split(separator: " ").last ?? "") } ?? 0
    if have < want {
      tools = .bad("These Command Line Tools are too old (clang \(have), \(want) or newer needed). "
                   + "Update them in System Settings › General › Software Update.")
      return
    }
    tools = .ok("Command Line Tools ready (\(URL(fileURLWithPath: sdk).lastPathComponent))")
  }

  func installTools() {
    tools = .busy("Installing Apple's Command Line Tools: follow the window that opened…")
    Task { _ = await Run.run("/usr/bin/xcode-select", ["--install"]) }
    toolsTimer?.invalidate()
    toolsTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
      Task { @MainActor in await self?.checkTools() }
    }
  }

  // MARK: The build

  func build() {
    guard canBuild, let folder = gameFolder else { return }
    building = true
    failure = nil
    installed = nil
    log.removeAll()
    task = Task {
      let start = Date()
      do {
        installed = try await runBuild(game: folder)
        step = "Done in \(Int(Date().timeIntervalSince(start) / 60)) minutes"
        progress = 1
      } catch is CancellationError {
        step = "Stopped"
      } catch {
        failure = error.localizedDescription
        step = "Stopped"
      }
      building = false
    }
  }

  func stop() { task?.cancel() }

  private func runBuild(game: URL) async throws -> URL {
    let fm = FileManager.default
    let work = Builder.work
    let lift = work.appendingPathComponent("lift")
    let gen = work.appendingPathComponent("generated")
    let obj = work.appendingPathComponent("obj")
    try? fm.removeItem(at: gen)
    for d in [lift, gen, obj] { try fm.createDirectory(at: d, withIntermediateDirectories: true) }
    if let free = try? work.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
      .volumeAvailableCapacityForImportantUsage, free < 5_000_000_000 {
      throw Failure("About 5 GB of free space is needed to build; \(free / 1_000_000_000) GB is free.")
    }
    guard let sdk = await Run.line("/usr/bin/xcrun", ["--show-sdk-path"]) else {
      throw Failure("Apple's Command Line Tools are not ready.")
    }
    let recipe = try Kit.recipe()
    func fill(_ a: String, src: String = "", obj: String = "") -> String {
      a.replacingOccurrences(of: "@KIT@", with: Kit.root.path)
        .replacingOccurrences(of: "@WORK@", with: work.path)
        .replacingOccurrences(of: "@SDK@", with: sdk)
        .replacingOccurrences(of: "@SRC@", with: src)
        .replacingOccurrences(of: "@OBJ@", with: obj)
    }

    // 1. The lifter reads the game's modules by name from its working
    // folder. fmodex.dll ships UPX-packed; the lifted code and the game
    // both need it unpacked, so the app gets the unpacked copy.
    step = "Preparing the game's files"
    progress = -1
    let data = game.appendingPathComponent("DATA")
    for f in ["DATA.exe", "fmod_event.dll", "fmodex.dll"] {
      try? fm.removeItem(at: lift.appendingPathComponent(f))
    }
    try fm.createSymbolicLink(at: lift.appendingPathComponent("DATA.exe"),
                              withDestinationURL: data.appendingPathComponent("DATA.exe"))
    try fm.createSymbolicLink(at: lift.appendingPathComponent("fmod_event.dll"),
                              withDestinationURL: data.appendingPathComponent("fmod_event.dll"))
    let fmodex = lift.appendingPathComponent("fmodex.dll")
    try fm.copyItem(at: data.appendingPathComponent("fmodex.dll"), to: fmodex)
    if let bytes = try? Data(contentsOf: fmodex), bytes.range(of: Data("UPX0".utf8)) != nil {
      let r = await Run.run(Kit.path("bin/upx"), ["-d", "-q", fmodex.path])
      guard r.ok else { throw Failure("Unpacking fmodex.dll failed:\n" + r.output.suffix(1500)) }
    }

    // 2. The game's code, translated from x86 to C++.
    step = "Translating the game's code (about 5 minutes)"
    say("== translating DATA.exe")
    let sym = Kit.path("symbols"), man = Kit.path("manifest")
    let r = await Run.run(Kit.path("bin/recomp_lift"), [
      "--exe", "DATA.exe", "--symbols", "\(sym)/darksouls", "--manifest", "\(man)/darksouls.manifest",
      "--out", gen.path, "--optnone-x87-over", "4000",
      "--module", "fmodex.dll", "--symbols", "\(sym)/fmodex", "--manifest", "\(man)/fmodex.manifest",
      "--module", "fmod_event.dll", "--symbols", "\(sym)/fmod_event", "--manifest", "\(man)/fmod_event.manifest",
      "--base", "11000000",
    ], cwd: lift.path)
    try Task.checkCancellation()
    r.output.split(separator: "\n").filter { !$0.hasPrefix("warning") }.suffix(8).forEach { say(String($0)) }
    guard r.ok else { throw Failure("Translating the game's code failed:\n" + r.output.suffix(2000)) }

    // 3. Compiled with the Mac's own clang, the largest files first: they
    // take the longest, and started last they would be all that is left.
    var jobs: [(src: String, obj: String, args: [String])] = []
    for (i, u) in recipe.units.enumerated() {
      let src = fill(u.src), o = obj.appendingPathComponent("unit\(i).o").path
      jobs.append((src, o, u.args.map { fill($0, src: src, obj: o) }))
    }
    let lifted = try fm.contentsOfDirectory(at: gen, includingPropertiesForKeys: [.fileSizeKey])
      .filter { $0.pathExtension == "cpp" }
      .sorted { (try? $0.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0) ?? 0
                > (try? $1.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0) ?? 0 }
    for f in lifted {
      let o = obj.appendingPathComponent(f.deletingPathExtension().lastPathComponent + ".o").path
      jobs.append((f.path, o, recipe.lifted.map { fill($0, src: f.path, obj: o) }))
    }
    say("== compiling \(jobs.count) files")
    try await parallel(jobs, label: "Compiling") { j in
      let r = await Run.run("/usr/bin/xcrun", ["clang++"] + j.args)
      return r.ok ? nil : "\((j.src as NSString).lastPathComponent):\n\(r.output.suffix(1500))"
    }

    // 4. Linked against the kit's runtime (ThinLTO: most of the code
    // generation happens here).
    step = "Linking"
    progress = -1
    say("== linking")
    let linkArgs = recipe.link.flatMap { $0 == "@OBJECTS@" ? jobs.map(\.obj) : [fill($0)] }
    let link = await Run.run("/usr/bin/xcrun", ["clang++"] + linkArgs)
    try Task.checkCancellation()
    guard link.ok else { throw Failure("Linking failed:\n" + link.output.suffix(2000)) }

    // 5. The app: the kit's bundle with this executable, the unpacked
    // fmodex.dll and the game folder, signed for this Mac.
    step = "Putting the app together"
    let staged = work.appendingPathComponent(Kit.appName)
    try await Task.detached {
      try? fm.removeItem(at: staged)
      try fm.copyItem(at: Kit.root.appendingPathComponent("app/\(Kit.appName)"), to: staged)
      try fm.copyItem(at: work.appendingPathComponent("game"), to: staged.appendingPathComponent("Contents/MacOS/game"))
      let res = staged.appendingPathComponent("Contents/Resources")
      try fm.copyItem(at: fmodex, to: res.appendingPathComponent("fmodex.dll"))
      try game.path.write(to: res.appendingPathComponent("game-dir"), atomically: true, encoding: .utf8)
    }.value
    _ = await Run.run("/usr/bin/xattr", ["-dr", "com.apple.quarantine", staged.path])
    let sign = await Run.run("/usr/bin/codesign", ["--force", "--deep", "--sign", "-", staged.path])
    guard sign.ok else { throw Failure("Signing the app failed:\n" + sign.output) }

    // 6. Into Applications (the user's own if the shared one is not
    // writable); the work folder (about 4 GB) is removed.
    let dest = try await Task.detached { () -> URL in
      var dir = URL(fileURLWithPath: Builder.destination)
      if !fm.isWritableFile(atPath: dir.path) {
        dir = fm.homeDirectoryForCurrentUser.appendingPathComponent("Applications")
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
      }
      let dest = dir.appendingPathComponent(Kit.appName)
      if fm.fileExists(atPath: dest.path) { try fm.removeItem(at: dest) }
      try fm.moveItem(at: staged, to: dest)
      try? fm.removeItem(at: work)
      return dest
    }.value
    say("== installed \(dest.path)")
    return dest
  }

  /// `body` over `items`, as many at once as the Mac has cores; a non-nil
  /// result is a failure and stops the rest.
  private func parallel<T: Sendable>(_ items: [T], label: String,
                                     _ body: @escaping @Sendable (T) async -> String?) async throws {
    let width = max(2, ProcessInfo.processInfo.activeProcessorCount)
    var done = 0, next = 0
    var failed: String?
    step = label
    progress = 0
    await withTaskGroup(of: String?.self) { group in
      func add() {
        guard next < items.count else { return }
        let item = items[next]
        next += 1
        group.addTask { await body(item) }
      }
      for _ in 0..<min(width, items.count) { add() }
      for await result in group {
        done += 1
        progress = Double(done) / Double(items.count)
        step = "\(label) (\(done) of \(items.count))"
        if let result, failed == nil {
          failed = result
          group.cancelAll()
        }
        if failed == nil, !Task.isCancelled { add() }
      }
    }
    try Task.checkCancellation()
    if let failed { throw Failure("\(label) failed:\n\(failed)") }
  }

  /// Without the window (builder --headless DIR): checks, builds, prints.
  static func headless(_ game: URL) async -> Int32 {
    let b = Builder()
    b.echo = true
    await b.setGame(game)
    await b.checkTools()
    guard b.canBuild else {
      print("not ready: game \(b.game), tools \(b.tools)")
      return 2
    }
    b.build()
    var last = ""
    while b.building {
      // While compiling, every tenth of the way.
      let shown = b.step.hasPrefix("Compiling (") ? "Compiling \(Int(b.progress * 10) * 10)%" : b.step
      if shown != last {
        last = shown
        print("step: \(shown)")
      }
      try? await Task.sleep(nanoseconds: 2_000_000_000)
    }
    if let f = b.failure { print("FAILED: \(f)"); return 1 }
    print("\(b.step): \(b.installed?.path ?? "?")")
    return 0
  }
}
