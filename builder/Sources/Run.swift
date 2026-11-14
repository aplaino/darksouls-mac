// Running a tool: its output collected, awaited without blocking a thread;
// cancelling the task terminates it.

import Foundation

struct RunResult {
  let status: Int32
  let output: String
  var ok: Bool { status == 0 }
}

enum Run {
  static func run(_ exe: String, _ args: [String], cwd: String? = nil) async -> RunResult {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: exe)
    p.arguments = args
    if let cwd { p.currentDirectoryURL = URL(fileURLWithPath: cwd) }
    let pipe = Pipe()
    p.standardOutput = pipe
    p.standardError = pipe
    let output = Output()
    pipe.fileHandleForReading.readabilityHandler = { h in output.append(h.availableData) }

    let status: Int32 = await withTaskCancellationHandler {
      await withCheckedContinuation { cont in
        p.terminationHandler = { p in cont.resume(returning: p.terminationStatus) }
        do {
          try p.run()
        } catch {
          p.terminationHandler = nil
          output.append(Data("cannot start \(exe): \(error.localizedDescription)\n".utf8))
          cont.resume(returning: -1)
        }
      }
    } onCancel: {
      if p.isRunning { p.terminate() }
    }
    pipe.fileHandleForReading.readabilityHandler = nil
    output.append(pipe.fileHandleForReading.readDataToEndOfFile())
    return RunResult(status: status, output: output.text)
  }

  /// The first line a tool prints, or nil when it fails.
  static func line(_ exe: String, _ args: [String]) async -> String? {
    let r = await run(exe, args)
    guard r.ok else { return nil }
    return r.output.split(separator: "\n").first.map(String.init)
  }
}

final class Output: @unchecked Sendable {
  private let lock = NSLock()
  private var data = Data()

  func append(_ d: Data) {
    lock.lock()
    data.append(d)
    lock.unlock()
  }

  var text: String {
    lock.lock()
    defer { lock.unlock() }
    return String(decoding: data, as: UTF8.self)
  }
}
