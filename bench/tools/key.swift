// key <pid> <keycode> [hold_ms]: one key press, held, posted to a process.
import CoreGraphics
import Foundation

let a = CommandLine.arguments
let pid = pid_t(a[1])!, code = CGKeyCode(a[2])!
let hold = a.count > 3 ? Double(a[3])! / 1000 : 0.1
let src = CGEventSource(stateID: .hidSystemState)
CGEvent(keyboardEventSource: src, virtualKey: code, keyDown: true)!.postToPid(pid)
Thread.sleep(forTimeInterval: hold)
CGEvent(keyboardEventSource: src, virtualKey: code, keyDown: false)!.postToPid(pid)
