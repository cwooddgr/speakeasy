// Dictation probe: logs changes in on-screen windows and per-process mic input
// so we can find a reliable "Dictation is active" signal.
// Run: swift probe/probe.swift   (Ctrl-C to stop)

import AppKit
import CoreAudio
import CoreGraphics

func ts() -> String {
    let f = DateFormatter()
    f.dateFormat = "HH:mm:ss.SSS"
    return f.string(from: Date())
}

// MARK: - Windows

func windowSnapshot() -> Set<String> {
    let opts: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
    guard let list = CGWindowListCopyWindowInfo(opts, kCGNullWindowID) as? [[String: Any]] else { return [] }
    var out = Set<String>()
    for w in list {
        let owner = w[kCGWindowOwnerName as String] as? String ?? "?"
        let pid = w[kCGWindowOwnerPID as String] as? Int ?? 0
        let layer = w[kCGWindowLayer as String] as? Int ?? 0
        let name = w[kCGWindowName as String] as? String ?? ""
        let b = w[kCGWindowBounds as String] as? [String: Any] ?? [:]
        let size = "\(b["Width"] ?? "?")x\(b["Height"] ?? "?")"
        out.insert("owner=\(owner) pid=\(pid) layer=\(layer) size=\(size) name=\"\(layer == 0 ? "" : name)\"")
    }
    return out
}

// MARK: - Mic input per process (macOS 14+)

func audioProperty<T>(_ obj: AudioObjectID, _ selector: AudioObjectPropertySelector, _ initial: T) -> T? {
    var addr = AudioObjectPropertyAddress(mSelector: selector,
                                          mScope: kAudioObjectPropertyScopeGlobal,
                                          mElement: kAudioObjectPropertyElementMain)
    var value = initial
    var size = UInt32(MemoryLayout<T>.size)
    let status = AudioObjectGetPropertyData(obj, &addr, 0, nil, &size, &value)
    return status == noErr ? value : nil
}

func micUsers() -> Set<String> {
    var addr = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyProcessObjectList,
                                          mScope: kAudioObjectPropertyScopeGlobal,
                                          mElement: kAudioObjectPropertyElementMain)
    var size: UInt32 = 0
    guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size) == noErr else { return [] }
    var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
    guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &ids) == noErr else { return [] }

    var out = Set<String>()
    for id in ids {
        guard let running: UInt32 = audioProperty(id, kAudioProcessPropertyIsRunningInput, 0), running != 0 else { continue }
        let pid: pid_t = audioProperty(id, kAudioProcessPropertyPID, 0) ?? -1
        var bundle = "?"
        if let cf: CFString = audioProperty(id, kAudioProcessPropertyBundleID, "" as CFString) {
            bundle = cf as String
        }
        let name = NSRunningApplication(processIdentifier: pid)?.localizedName ?? processName(pid)
        out.insert("pid=\(pid) bundle=\(bundle) name=\(name)")
    }
    return out
}

func processName(_ pid: pid_t) -> String {
    var buf = [CChar](repeating: 0, count: 4096)
    return proc_pidpath(pid, &buf, UInt32(buf.count)) > 0 ? String(cString: buf) : "?"
}

// MARK: - Loop

print("[\(ts())] probe started; toggle Dictation with the mic key a few times")
var lastWindows = windowSnapshot()
var lastMic = micUsers()
print("[\(ts())] baseline mic users: \(lastMic.sorted())")
setvbuf(stdout, nil, _IOLBF, 0)

while true {
    usleep(150_000)
    let w = windowSnapshot()
    for s in w.subtracting(lastWindows).sorted() { print("[\(ts())] WIN+ \(s)") }
    for s in lastWindows.subtracting(w).sorted() { print("[\(ts())] WIN- \(s)") }
    lastWindows = w

    let m = micUsers()
    for s in m.subtracting(lastMic).sorted() { print("[\(ts())] MIC+ \(s)") }
    for s in lastMic.subtracting(m).sorted() { print("[\(ts())] MIC- \(s)") }
    lastMic = m
}
