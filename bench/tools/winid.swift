// winid <pid>: the CGWindowID of that process's largest on-screen window.
import CoreGraphics
import Foundation

let pid = Int(CommandLine.arguments[1])!
let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as! [[String: Any]]
var best: (Int, Double)? = nil
for w in list where (w["kCGWindowOwnerPID"] as? Int) == pid && (w["kCGWindowLayer"] as? Int) == 0 {
  let b = w["kCGWindowBounds"] as! [String: Double]
  let area = b["Width"]! * b["Height"]!
  if best == nil || area > best!.1 { best = (w["kCGWindowNumber"] as! Int, area) }
}
if let b = best { print(b.0) } else { exit(1) }
