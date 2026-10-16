// micduck: lower music volume while any app is using the microphone.
//
// Listens for CoreAudio's "device is running somewhere" flag on the default
// input device. When the mic opens, Spotify and Apple Music fade down to
// DUCK_TO percent; when it closes, they fade back to where they were.
// Nothing polls: between mic changes the process sleeps.
import AppKit
import CoreAudio
import Foundation

let duckTo = Int(CommandLine.arguments.dropFirst().first ?? "") ?? 50  // percent
let fadeDuration = 0.2  // seconds
let fadeSteps = 10

let players = [
    (name: "Spotify", bundleID: "com.spotify.client"),
    (name: "Music", bundleID: "com.apple.Music"),
]

func log(_ message: String) {
    let stamp = ISO8601DateFormatter().string(from: Date())
    print("\(stamp) \(message)")
    fflush(stdout)
}

// MARK: - Microphone

var runningAddr = AudioObjectPropertyAddress(
    mSelector: kAudioDevicePropertyDeviceIsRunningSomewhere,
    mScope: kAudioObjectPropertyScopeGlobal,
    mElement: kAudioObjectPropertyElementMain)
var defaultInputAddr = AudioObjectPropertyAddress(
    mSelector: kAudioHardwarePropertyDefaultInputDevice,
    mScope: kAudioObjectPropertyScopeGlobal,
    mElement: kAudioObjectPropertyElementMain)

func defaultInput() -> AudioDeviceID {
    var id = AudioDeviceID(0)
    var size = UInt32(MemoryLayout<AudioDeviceID>.size)
    AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &defaultInputAddr, 0, nil, &size, &id)
    return id
}

func micInUse(_ device: AudioDeviceID) -> Bool {
    var running = UInt32(0)
    var size = UInt32(MemoryLayout<UInt32>.size)
    AudioObjectGetPropertyData(device, &runningAddr, 0, nil, &size, &running)
    return running != 0
}

// MARK: - Players

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
var fades: [String: Timer] = [:]

// Step the volume from wherever it is now to target, replacing any fade
// already running on that player so a quick on/off/on just turns around.
func fade(_ app: String, to target: Int, then done: (() -> Void)? = nil) {
    fades[app]?.invalidate()
    guard let current = tell(app, "get sound volume") else { return }
    let start = Int(current.int32Value)
    var step = 0
    let timer = Timer(timeInterval: fadeDuration / Double(fadeSteps), repeats: true) { t in
        step += 1
        tell(app, "set sound volume to \(start + (target - start) * step / fadeSteps)")
        if step == fadeSteps {
            t.invalidate()
            fades[app] = nil
            done?()
        }
    }
    RunLoop.main.add(timer, forMode: .common)
    fades[app] = timer
}

func duck() {
    for p in players where isRunning(p.bundleID) {
        if saved[p.name] == nil {
            guard let v = tell(p.name, "get sound volume")?.int32Value, v > duckTo else { continue }
            saved[p.name] = Int(v)
        }
        log("mic on: \(p.name) \(saved[p.name]!) -> \(duckTo)")
        fade(p.name, to: duckTo)
    }
}

func restore() {
    for (name, v) in saved {
        guard let p = players.first(where: { $0.name == name }), isRunning(p.bundleID) else {
            saved[name] = nil
            continue
        }
        log("mic off: \(name) -> \(v)")
        fade(name, to: v) { saved[name] = nil }
    }
}

// On exit there's no time to fade: jump straight back.
func restoreNow() {
    fades.values.forEach { $0.invalidate() }
    for (name, v) in saved {
        if let p = players.first(where: { $0.name == name }), isRunning(p.bundleID) {
            tell(name, "set sound volume to \(v)")
        }
    }
}

// MARK: - Main

var watched = AudioDeviceID(0)
var ducked = false

func update() {
    let busy = micInUse(watched)
    guard busy != ducked else { return }
    ducked = busy
    busy ? duck() : restore()
}

let runningListener: AudioObjectPropertyListenerBlock = { _, _ in update() }

// (Re)attach to the default input, e.g. when AirPods connect.
func watchDefaultInput() {
    if watched != 0 {
        AudioObjectRemovePropertyListenerBlock(watched, &runningAddr, .main, runningListener)
    }
    watched = defaultInput()
    AudioObjectAddPropertyListenerBlock(watched, &runningAddr, .main, runningListener)
    update()
}

AudioObjectAddPropertyListenerBlock(
    AudioObjectID(kAudioObjectSystemObject), &defaultInputAddr, .main
) { _, _ in watchDefaultInput() }

var signalSources: [DispatchSourceSignal] = []
for sig in [SIGINT, SIGTERM, SIGHUP] {
    signal(sig, SIG_IGN)
    let source = DispatchSource.makeSignalSource(signal: sig, queue: .main)
    source.setEventHandler {
        restoreNow()
        exit(0)
    }
    source.resume()
    signalSources.append(source)
}

log("micduck: ducking to \(duckTo)% while the mic is in use")
watchDefaultInput()
RunLoop.main.run()
