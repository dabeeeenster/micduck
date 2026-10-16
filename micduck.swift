// micduck: lower music volume while any app is using the microphone.
//
// Polls CoreAudio's "device is running somewhere" flag on the default input
// device. When the mic opens, Spotify and Apple Music are turned down to
// DUCK_TO percent; when it closes, they go back to where they were.
import AppKit
import CoreAudio
import Foundation

let duckTo = Int(CommandLine.arguments.dropFirst().first ?? "") ?? 50  // percent
let pollInterval = 0.3

let players = [
    (name: "Spotify", bundleID: "com.spotify.client"),
    (name: "Music", bundleID: "com.apple.Music"),
]

func log(_ message: String) {
    let stamp = ISO8601DateFormatter().string(from: Date())
    print("\(stamp) \(message)")
    fflush(stdout)
}

func defaultInput() -> AudioDeviceID {
    var id = AudioDeviceID(0)
    var size = UInt32(MemoryLayout<AudioDeviceID>.size)
    var addr = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDefaultInputDevice,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain)
    AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &id)
    return id
}

func micInUse() -> Bool {
    var running = UInt32(0)
    var size = UInt32(MemoryLayout<UInt32>.size)
    var addr = AudioObjectPropertyAddress(
        mSelector: kAudioDevicePropertyDeviceIsRunningSomewhere,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain)
    AudioObjectGetPropertyData(defaultInput(), &addr, 0, nil, &size, &running)
    return running != 0
}

func isRunning(_ bundleID: String) -> Bool {
    !NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty
}

// Only ever called for a running player, so AppleScript never launches it
// or asks where an uninstalled app is.
@discardableResult
func tell(_ app: String, _ command: String) -> NSAppleEventDescriptor? {
    var error: NSDictionary?
    let result = NSAppleScript(source: "tell application \"\(app)\" to \(command)")?
        .executeAndReturnError(&error)
    if let error { log("\(app): \(error[NSAppleScript.errorMessage] ?? error)") }
    return result
}

var saved: [String: Int] = [:]  // player name -> volume before ducking

func duck() {
    for p in players where isRunning(p.bundleID) {
        guard let v = tell(p.name, "get sound volume")?.int32Value, v > duckTo else { continue }
        saved[p.name] = Int(v)
        tell(p.name, "set sound volume to \(duckTo)")
        log("mic on: \(p.name) \(v) -> \(duckTo)")
    }
}

func restore() {
    for p in players {
        guard let v = saved.removeValue(forKey: p.name), isRunning(p.bundleID) else { continue }
        tell(p.name, "set sound volume to \(v)")
        log("mic off: \(p.name) -> \(v)")
    }
}

var ducked = false
let timer = Timer(timeInterval: pollInterval, repeats: true) { _ in
    let busy = micInUse()
    if busy && !ducked { duck() } else if !busy && ducked { restore() }
    ducked = busy
}
RunLoop.main.add(timer, forMode: .common)

// Put the volume back if we're stopped mid-duck.
var signalSources: [DispatchSourceSignal] = []
for sig in [SIGINT, SIGTERM, SIGHUP] {
    signal(sig, SIG_IGN)
    let source = DispatchSource.makeSignalSource(signal: sig, queue: .main)
    source.setEventHandler {
        restore()
        exit(0)
    }
    source.resume()
    signalSources.append(source)
}

log("micduck: ducking to \(duckTo)% while the mic is in use")
RunLoop.main.run()
