import CoreLocation
import Foundation
import MapKit
import UIKit
import UserNotifications

enum TravelMode: String, CaseIterable, Identifiable {
    case walk, run, cycle, drive

    var id: String { rawValue }

    var title: String {
        switch self {
        case .walk: return "Walk"
        case .run: return "Run"
        case .cycle: return "Cycle"
        case .drive: return "Drive"
        }
    }

    var icon: String {
        switch self {
        case .walk: return "figure.walk"
        case .run: return "figure.run"
        case .cycle: return "bicycle"
        case .drive: return "car.fill"
        }
    }

    /// Base meters per second before natural variation.
    var baseSpeed: CLLocationSpeed {
        switch self {
        case .walk: return 1.4
        case .run: return 3.3
        case .cycle: return 6.5
        case .drive: return 13.4
        }
    }

    var mkTransportType: MKDirectionsTransportType {
        switch self {
        case .walk, .run: return .walking
        case .cycle, .drive: return .automobile
        }
    }
}

/// Local diagnostic events only. No pairing material or identifiers are saved.
struct MovementDiagnosticEvent: Identifiable {
    let id = UUID()
    let timestamp: Date
    let action: String
    let succeeded: Bool
    let detail: String
}

enum SpoofStatus: Equatable {
    case idle
    case connecting
    case active
    case reconnecting
    case dropped(String)

    var label: String {
        switch self {
        case .idle: return "Not Spoofing"
        case .connecting: return "Starting…"
        case .active: return "Spoofing"
        case .reconnecting: return "Reconnecting…"
        case .dropped: return "Interrupted"
        }
    }

    var isDropped: Bool {
        if case .dropped = self { return true }
        return false
    }
}

@MainActor
final class SpoofSession: ObservableObject {
    @Published var status: SpoofStatus = .idle
    @Published var pin: CLLocationCoordinate2D?
    @Published var simulated: CLLocationCoordinate2D?
    @Published var travelMode: TravelMode = .walk
    @Published var mapStyleIndex: Int = 0
    @Published var lastError: String?
    @Published var isBusy = false
    @Published var joystickActive = false
    // Reports the local API result; Apple Maps is the external verification.
    @Published private(set) var lastTeleportResult = "No teleport attempted in this session"

    // v0.13: distinguish requested positions from API acknowledgements and
    // from independent CoreLocation callbacks (which are NOT proof of Apple Maps).
    @Published private(set) var lastRequestedCoordinate: CLLocationCoordinate2D?
    @Published private(set) var lastAcceptedCoordinate: CLLocationCoordinate2D?
    @Published private(set) var lastObservedCoordinate: CLLocationCoordinate2D?
    @Published private(set) var lastObservedAt: Date?
    @Published private(set) var movementAttempts = 0
    @Published private(set) var movementAccepted = 0
    @Published private(set) var movementFailed = 0
    @Published private(set) var lastMovementResult = "No movement commands attempted"
    @Published private(set) var movementEvents: [MovementDiagnosticEvent] = []
    // v0.14: foreground continuous movement, including a fixed-length hands-free
    // trial so Apple Maps can be inspected AFTER the movement has finished.
    @Published private(set) var cruiseActive = false
    @Published private(set) var cruiseSecondsRemaining = 0
    @Published private(set) var continuousAcceptedMeters = 0.0
    @Published private(set) var continuousAcceptedTicks = 0
    @Published private(set) var continuousFailedTicks = 0
    @Published private(set) var lastContinuousStatus = "No continuous movement attempted"
    // v0.15/16: lifecycle audit and recoverable foreground cruise remain unchanged.
    // v0.17 adds a separately requested, finite background experiment.
    @Published private(set) var lifecycleEvents: [String] = []
    @Published private(set) var lastLifecycleState = "Not observed"
    @Published private(set) var lastBackgroundAt: Date?
    @Published private(set) var lastForegroundAt: Date?
    @Published private(set) var pausedCruiseSeconds: TimeInterval?
    // v0.16: explicit, non-simulating handover audit. No invented background GPS updates.
    @Published private(set) var backgroundTransitions = 0
    @Published private(set) var lastAwaySeconds: TimeInterval = 0
    @Published private(set) var lastHandoverRequestedMeters: Double = 0
    @Published private(set) var lastHandoverAcceptedTicks = 0
    @Published private(set) var lastHandoverNote = "No app handover measured"
    @Published private(set) var lastMovementCommandAt: Date?
    @Published private(set) var foregroundResumeCount = 0
    @Published private(set) var lastResumeAt: Date?
    // A purely hypothetical distance at the selected speed: never sent to iOS.
    @Published private(set) var hypotheticalAwayMeters: Double = 0
    private var handoverStartMeters = 0.0
    private var handoverStartAcceptedTicks = 0
    private var backgroundCruiseSpeed: CLLocationSpeed = 0
    private var lastBackgroundStartForAudit: Date?
    // v0.18: opt-in, finite 20/30/60s experiments using the proven v0.17
    // mechanism. API acknowledgement never independently verifies Apple Maps.
    @Published private(set) var backgroundTrialStatus = "Not attempted"
    @Published private(set) var backgroundTrialAttempts = 0
    @Published private(set) var backgroundTrialAccepted = 0
    @Published private(set) var backgroundTrialFailed = 0
    @Published private(set) var backgroundTrialAcceptedMeters = 0.0
    @Published private(set) var backgroundTrialExpirations = 0
    @Published private(set) var lastBackgroundTrialCommandAt: Date?
    @Published private(set) var backgroundTrialTaskHeld = false
    @Published private(set) var backgroundTrialPlannedSeconds = 0
    @Published private(set) var backgroundTrialActualSeconds = 0.0
    @Published private(set) var backgroundTrialLongestTickGap = 0.0
    @Published private(set) var backgroundTrialLargeTickGaps = 0
    @Published private(set) var backgroundTrialEndReason = "Not attempted"
    private var backgroundTrialStartedUptime: TimeInterval?
    private var backgroundTrialLastTickUptime: TimeInterval?
    private var backgroundTrialEnabled = false
    private var actuallyInBackground = false
    private var handoverWasExperimental = false
    private var handoverInitialBgAccepted = 0
    private var handoverInitialBgAttempts = 0

    @Published var favorites: [SavedPlace] = []
    @Published var recents: [SavedPlace] = []

    // v0.9: opt-in only. Silent automatic sends obscured the cellular transition
    // experiment and could trigger teardown of a working simulation.
    private let automaticRetriesEnabled = false
    private var resendTimer: Timer?
    private var healthTimer: Timer?
    private var joystickTimer: Timer?
    private var cruiseTimer: Timer?
    private var cruiseDeadlineUptime: TimeInterval?
    private var lastMovementTickUptime: TimeInterval?
    private let movementTickInterval: TimeInterval = 0.8
    private var routeTask: Task<Void, Never>?
    private var shortCruiseTask = UIBackgroundTaskIdentifier.invalid
    private var joystickVector: CGVector = .zero
    private let locationKeeper = BackgroundKeepAlive()

    private let favoritesKey = "locus.favorites"
    private let recentsKey = "locus.recents"

    init() {
        favorites = SavedPlace.load(key: favoritesKey)
        recents = SavedPlace.load(key: recentsKey)
        locationKeeper.onLocationUpdate = { [weak self] location in
            Task { @MainActor [weak self] in
                self?.lastObservedCoordinate = location.coordinate
                self?.lastObservedAt = location.timestamp
            }
        }
    }

    var isSpoofing: Bool {
        // Even after a failed location update, a retained developer handle is
        // valuable: show Teleport and End Session instead of treating it as gone.
        if LocationEngine.isSessionActive { return true }
        if case .active = status { return true }
        if case .reconnecting = status { return true }
        return false
    }

    /// A new destination is an UPDATE to the retained simulation when one exists.
    /// Never call clear()/stop() as a prerequisite to teleportation.
    func teleport(to coordinate: CLLocationCoordinate2D, pairing: PairingStore) {
        guard pairing.hasPairingFile else {
            lastError = "Import an RPPairing file in Settings first."
            return
        }
        guard !isBusy else { return }
        pauseMovement() // prevent a route/joystick tick from overwriting the teleport
        let usedRetainedSession = LocationEngine.isSessionActive
        pin = coordinate
        let succeeded = apply(coordinate, pairing: pairing, markRecent: true)
        recordMovement(action: usedRetainedSession ? "Retained teleport" : "Initial teleport",
                       coordinate: coordinate, succeeded: succeeded)
        if succeeded {
            lastTeleportResult = usedRetainedSession
                ? "Persistent teleport sent through the retained session — verify in Apple Maps"
                : "Initial teleport sent through a new session — verify in Apple Maps"
        } else {
            lastTeleportResult = usedRetainedSession
                ? "Persistent teleport failed; session handle kept for another attempt"
                : "Initial teleport failed; no location session established"
        }
    }

    /// Stops the joystick or route without clearing Apple's simulated location.
    /// This is safe to use before switching to a new teleport target.
    func pauseMovement() {
        pausedCruiseSeconds = nil
        routeTask?.cancel()
        routeTask = nil
        stopJoystick()
        stopCruise(reason: "Movement paused; last accepted GPS coordinate retained")
    }

    private func logLifecycle(_ message: String) {
        let timestamp = ISO8601DateFormatter().string(from: Date())
        lifecycleEvents.insert("\(timestamp) | \(message)", at: 0)
        if lifecycleEvents.count > 50 { lifecycleEvents.removeLast(lifecycleEvents.count - 50) }
    }

    /// The original cruise continues to pause as before. ONLY the explicit
    /// short background trial may attempt updates in another app, and only
    /// while a finite UIApplication background task remains valid.
    func applicationEnteredBackground() {
        actuallyInBackground = true
        lastLifecycleState = "Background"
        lastBackgroundAt = Date()
        lastBackgroundStartForAudit = lastBackgroundAt
        backgroundTransitions += 1
        handoverStartMeters = continuousAcceptedMeters
        handoverStartAcceptedTicks = continuousAcceptedTicks
        backgroundCruiseSpeed = cruiseActive ? travelMode.baseSpeed : 0
        handoverWasExperimental = cruiseActive && backgroundTrialEnabled
        handoverInitialBgAccepted = backgroundTrialAccepted
        handoverInitialBgAttempts = backgroundTrialAttempts
        logLifecycle("Entered background; cruise=\(cruiseActive), experimental=\(backgroundTrialEnabled), task=\(shortCruiseTask != .invalid), session=\(LocationEngine.isSessionActive)")
        if cruiseActive {
            if backgroundTrialEnabled && shortCruiseTask != .invalid {
                backgroundTrialStatus = "Background entered; awaiting timer/API evidence"
                logLifecycle("Experimental \(backgroundTrialPlannedSeconds)s cruise requested in background; execution not guaranteed")
            } else {
                let remaining = max(0, (cruiseDeadlineUptime ?? ProcessInfo.processInfo.systemUptime) - ProcessInfo.processInfo.systemUptime)
                stopCruise(reason: "Paused in background, \(Int(ceil(remaining)))s remaining")
                pausedCruiseSeconds = remaining > 0 ? remaining : nil
                logLifecycle("Cruise paused with \(String(format: "%.1f", remaining))s remaining; no background commands")
            }
        }
        if joystickActive {
            stopJoystick()
            logLifecycle("Joystick stopped on background entry; restart manually")
        }
    }

    func applicationBecameInactive() {
        lastLifecycleState = "Inactive"
        logLifecycle("Scene inactive (transition; not necessarily suspended)")
    }

    /// Resume only the uncompleted trial duration, never the elapsed time spent
    /// in Apple Maps. The retained session is reused; no new cellular pairing.
    func applicationBecameActive(pairing: PairingStore) {
        actuallyInBackground = false
        lastLifecycleState = "Active"
        lastForegroundAt = Date()
        let away = lastBackgroundStartForAudit.map { Date().timeIntervalSince($0) } ?? 0
        if lastBackgroundStartForAudit != nil {
            lastAwaySeconds = away
            hypotheticalAwayMeters = max(0, away * backgroundCruiseSpeed)
            lastHandoverRequestedMeters = max(0, continuousAcceptedMeters - handoverStartMeters)
            lastHandoverAcceptedTicks = max(0, continuousAcceptedTicks - handoverStartAcceptedTicks)
            if handoverWasExperimental {
                let bgAttempts = max(0, backgroundTrialAttempts - handoverInitialBgAttempts)
                let bgAccepted = max(0, backgroundTrialAccepted - handoverInitialBgAccepted)
                lastHandoverNote = String(format: "Away %.1fs; background API attempts %d, accepted %d; API acknowledgement is NOT Apple Maps verification", away, bgAttempts, bgAccepted)
            } else {
                lastHandoverNote = String(format: "Away %.1fs; standard cruise paused; hypothetical travel %.1fm NOT sent", away, hypotheticalAwayMeters)
            }
            logLifecycle(lastHandoverNote)
            lastBackgroundStartForAudit = nil
            handoverWasExperimental = false
        }
        logLifecycle("Returned active after \(String(format: "%.1f", away))s; retained session=\(LocationEngine.isSessionActive)")
        // Detect an extended timer gap when returning from Apple Maps even if
        // UIKit suspended the timer and the next scheduled tick never ran.
        if cruiseActive && backgroundTrialEnabled { recordBackgroundTrialTimerGap() }
        guard let remaining = pausedCruiseSeconds else { return }
        pausedCruiseSeconds = nil
        guard pairing.hasPairingFile, LocationEngine.isSessionActive, simulated != nil, !isBusy else {
            lastContinuousStatus = "Could not resume: retained session or pairing unavailable"
            logLifecycle("Resume skipped: retained session or pairing unavailable")
            return
        }
        beginNorthCruise(duration: remaining, pairing: pairing, resetCounters: false)
        foregroundResumeCount += 1
        lastResumeAt = Date()
        lastContinuousStatus = "Resumed on foreground; \(Int(ceil(remaining))) seconds remaining"
        logLifecycle("Cruise resumed on foreground with \(String(format: "%.1f", remaining))s remaining")
    }

    /// Explicit END SIMULATION only; should never be used for pause or teleport.
    func stop(pairing: PairingStore) {
        pauseMovement()
        stopResend()
        stopHealth()
        isBusy = true
        let result = LocationEngine.clear()
        isBusy = false
        switch result {
        case .success:
            simulated = nil
            lastTeleportResult = "Simulation ended; real GPS should resume"
            status = .idle
            endShortCruiseTask()
            // Keep location updates running so the map puck / locate button
            // can return to the real GPS fix (not the leftover pin).
            locationKeeper.start()
        case .failure(let error):
            lastError = error.localizedDescription
            status = .dropped(error.localizedDescription)
            postDropNotification(error.localizedDescription)
        }
    }

    /// Best-known real device coordinate (not the teleport pin).
    var realCoordinate: CLLocationCoordinate2D? {
        locationKeeper.lastKnownCoordinate
    }

    /// Start lightweight GPS updates for the map puck / locate button.
    func startLocationUpdates() {
        locationKeeper.start()
    }

    func startJoystick(pairing: PairingStore) {
        guard pairing.hasPairingFile else {
            lastError = "Import an RPPairing file in Settings first."
            return
        }
        let start = simulated ?? pin ?? locationKeeper.lastKnownCoordinate
        guard let start else {
            lastError = "Drop a pin or teleport somewhere before using the joystick."
            return
        }
        if simulated == nil {
            let opened = apply(start, pairing: pairing, markRecent: false)
            recordMovement(action: "Joystick initial location", coordinate: start, succeeded: opened)
            guard opened else { return }
        }
        stopCruise(reason: "Switched to joystick")
        stopJoystick()
        resetContinuousCounters()
        joystickActive = true
        lastMovementResult = "Joystick ready — press and drag to move"
        lastContinuousStatus = "Joystick ready (foreground only)"
        joystickTimer = Timer.scheduledTimer(withTimeInterval: movementTickInterval, repeats: true) { [weak self] _ in
            // The synchronous API call runs on the main actor; its timer will
            // not trigger concurrently with an in-flight location update.
            Task { @MainActor [weak self] in self?.tickJoystick(pairing: pairing) }
        }
    }

    func updateJoystick(vector: CGVector) {
        joystickVector = vector
        if hypot(vector.dx, vector.dy) <= 0.08 {
            // Reset elapsed-time calculation when released, so the first
            // movement after a pause doesn't leap forward.
            lastMovementTickUptime = nil
            if joystickActive { lastContinuousStatus = "Joystick released — holding last accepted coordinate" }
        }
    }

    func stopJoystick() {
        joystickActive = false
        joystickVector = .zero
        lastMovementTickUptime = nil
        joystickTimer?.invalidate()
        joystickTimer = nil
    }

    /// A reproducible 20-second North movement, using the identical
    /// LocationEngine.set/apply path as the successful 200m GPS step.
    /// Only an ALREADY retained developer session may be used.
    func startNorthCruise20(pairing: PairingStore) {
        guard canStartRetainedCruise(pairing: pairing) else { return }
        pauseMovement()
        pausedCruiseSeconds = nil
        beginNorthCruise(duration: 20, pairing: pairing, resetCounters: true)
    }

    /// v0.18: identical v0.17 path, now selectable for 20, 30, or 60 seconds.
    /// This is ONLY a finite, user-started experiment with an already retained
    /// developer session. It does not request unlimited background operation.
    func startBackgroundCruise(duration: Int, pairing: PairingStore) {
        guard [20, 30, 60].contains(duration) else { return }
        guard canStartRetainedCruise(pairing: pairing) else { return }
        pauseMovement()
        pausedCruiseSeconds = nil
        backgroundTrialAttempts = 0
        backgroundTrialAccepted = 0
        backgroundTrialFailed = 0
        backgroundTrialAcceptedMeters = 0
        backgroundTrialExpirations = 0
        lastBackgroundTrialCommandAt = nil
        backgroundTrialPlannedSeconds = duration
        backgroundTrialActualSeconds = 0
        backgroundTrialLongestTickGap = 0
        backgroundTrialLargeTickGaps = 0
        backgroundTrialEndReason = "Running"
        backgroundTrialLastTickUptime = nil
        backgroundTrialStartedUptime = ProcessInfo.processInfo.systemUptime
        backgroundTrialStatus = "Requesting finite iOS background task for \(duration)s"
        guard beginShortCruiseTask(duration: duration) else {
            backgroundTrialEndReason = "No iOS background task granted"
            backgroundTrialStatus = "iOS did not grant the background task; no experimental cruise started"
            backgroundTrialStartedUptime = nil
            logLifecycle(backgroundTrialStatus)
            return
        }
        backgroundTrialEnabled = true
        beginNorthCruise(duration: TimeInterval(duration), pairing: pairing, resetCounters: true)
        backgroundTrialStatus = "\(duration)s experimental cruise started; switch to Apple Maps"
        logLifecycle("Experimental \(duration)s background cruise started in foreground")
    }

    // Preserve the v0.17 20-second entry point, so existing callers remain valid.
    func startBackgroundCruise20(pairing: PairingStore) {
        startBackgroundCruise(duration: 20, pairing: pairing)
    }

    private func canStartRetainedCruise(pairing: PairingStore) -> Bool {
        guard !isBusy, pairing.hasPairingFile,
              LocationEngine.isSessionActive, simulated != nil else {
            lastMovementResult = "Cruise blocked: establish an initial Wi-Fi teleport first"
            lastError = "A retained simulation is required. Start a successful teleport on Wi-Fi before the 4G movement trial."
            return false
        }
        return true
    }

    private func beginNorthCruise(duration: TimeInterval, pairing: PairingStore, resetCounters: Bool) {
        if resetCounters { resetContinuousCounters() }
        lastMovementTickUptime = nil // never count background time as movement
        cruiseActive = true
        cruiseSecondsRemaining = Int(ceil(duration))
        lastContinuousStatus = "Moving north for \(Int(ceil(duration))) seconds at \(travelMode.title) preset"
        cruiseDeadlineUptime = ProcessInfo.processInfo.systemUptime + duration
        cruiseTimer = Timer.scheduledTimer(withTimeInterval: movementTickInterval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.tickCruise(pairing: pairing) }
        }
    }

    func stopCruise(reason: String = "Cruise stopped — last accepted position held") {
        let wasExperimental = backgroundTrialEnabled
        guard cruiseActive || cruiseTimer != nil else {
            pausedCruiseSeconds = nil
            backgroundTrialEnabled = false
            endShortCruiseTask()
            return
        }
        cruiseActive = false
        cruiseTimer?.invalidate()
        cruiseTimer = nil
        cruiseDeadlineUptime = nil
        lastMovementTickUptime = nil
        cruiseSecondsRemaining = 0
        lastContinuousStatus = reason
        backgroundTrialEnabled = false
        endShortCruiseTask()
        if wasExperimental {
            if let start = backgroundTrialStartedUptime {
                backgroundTrialActualSeconds = max(0, ProcessInfo.processInfo.systemUptime - start)
            }
            backgroundTrialEndReason = reason
            backgroundTrialStatus = "Trial stopped: \(reason); background API accepted \(backgroundTrialAccepted)/\(backgroundTrialAttempts)"
            logLifecycle(backgroundTrialStatus)
            backgroundTrialStartedUptime = nil
            backgroundTrialLastTickUptime = nil
        }
    }

    private func resetContinuousCounters() {
        continuousAcceptedMeters = 0
        continuousAcceptedTicks = 0
        continuousFailedTicks = 0
        lastMovementTickUptime = nil
    }

    /// Keep the last successfully sent position; do NOT clear GPS or reconnect.
    func holdPosition() {
        pauseMovement()
        lastMovementResult = "Hold: movement stopped; the last accepted location was not cleared"
        lastContinuousStatus = "Hold position selected; developer session not cleared"
    }

    /// Single deterministic movement, so Apple Maps can be checked after
    /// leaving Roam. Requires an existing session; never opens a fresh tunnel.
    func stepNorth200(pairing: PairingStore) {
        guard !isBusy, LocationEngine.isSessionActive, let current = simulated else {
            lastMovementResult = "Step blocked: establish a working teleport session first"
            lastError = "Start a working teleport on Wi-Fi, then retry the 200 m step using the retained session."
            return
        }
        pauseMovement()
        let next = offset(coordinate: current, eastMeters: 0, northMeters: 200)
        let succeeded = apply(next, pairing: pairing, markRecent: false)
        recordMovement(action: "Step north 200 m", coordinate: next, succeeded: succeeded)
    }

    func clearMovementDiagnostics() {
        movementAttempts = 0
        movementAccepted = 0
        movementFailed = 0
        movementEvents.removeAll()
        resetContinuousCounters()
        lastMovementResult = "Diagnostics reset; simulation unchanged"
        lastContinuousStatus = "Continuous counters reset; simulation unchanged"
        if !cruiseActive {
            backgroundTrialAttempts = 0
            backgroundTrialAccepted = 0
            backgroundTrialFailed = 0
            backgroundTrialAcceptedMeters = 0
            backgroundTrialExpirations = 0
            lastBackgroundTrialCommandAt = nil
            backgroundTrialStatus = "Diagnostic counters reset; location simulation unchanged"
            backgroundTrialPlannedSeconds = 0
            backgroundTrialActualSeconds = 0
            backgroundTrialLongestTickGap = 0
            backgroundTrialLargeTickGaps = 0
            backgroundTrialEndReason = "Reset"
        }
    }

    /// For copying into troubleshooting notes; coordinates are included only
    /// by explicit user action. Pairing files and secrets are never included.
    func movementDiagnosticReport() -> String {
        let fmt = ISO8601DateFormatter()
        let coordinate: (CLLocationCoordinate2D?) -> String = { c in
            guard let c else { return "none" }
            return String(format: "%.7f, %.7f", c.latitude, c.longitude)
        }
        let observedTime = lastObservedAt.map { fmt.string(from: $0) } ?? "none"
        let rows = movementEvents.map {
            "\(fmt.string(from: $0.timestamp)) | \($0.action) | \($0.succeeded ? "API accepted" : "API failed") | \($0.detail)"
        }.joined(separator: "\n")
        return """
        Roam v0.18 movement and lifecycle diagnostics
        Status: \(status.label)
        Retained location handle: \(LocationEngine.isSessionActive ? "present (not independently validated)" : "absent")
        Attempts: \(movementAttempts), accepted: \(movementAccepted), failed: \(movementFailed)
        Continuous trial: \(lastContinuousStatus)
        v0.18 finite background trial: \(backgroundTrialStatus)
        Planned trial duration: \(backgroundTrialPlannedSeconds) s
        Recorded trial wall-clock time: \(String(format: "%.1f", backgroundTrialActualSeconds)) s (does not prove continuous execution)
        End reason: \(backgroundTrialEndReason)
        Longest observed tick gap: \(String(format: "%.2f", backgroundTrialLongestTickGap)) s; gaps >2.5s: \(backgroundTrialLargeTickGaps)
        Short background task currently held: \(backgroundTrialTaskHeld)
        Background-location API attempts: \(backgroundTrialAttempts), accepted: \(backgroundTrialAccepted), failed: \(backgroundTrialFailed)
        Background requested meters acknowledged by API: \(String(format: "%.1f", backgroundTrialAcceptedMeters)) m (not independently verified)
        Background task expirations: \(backgroundTrialExpirations)
        Last background GPS command: \(lastBackgroundTrialCommandAt.map { fmt.string(from: $0) } ?? "none")
        Lifecycle: \(lastLifecycleState)
        Background cruise remainder: \(pausedCruiseSeconds.map { String(format: "%.1fs", $0) } ?? "none")
        Background entries: \(backgroundTransitions)
        Last time away: \(String(format: "%.1fs", lastAwaySeconds))
        Foreground cruise resumes: \(foregroundResumeCount)
        Latest return audit: \(lastHandoverNote)
        Hypothetical background travel (NOT SENT): \(String(format: "%.1fm", hypotheticalAwayMeters))
        Last accepted movement command time: \(lastMovementCommandAt.map { fmt.string(from: $0) } ?? "none")
        Lifecycle history:\n\(lifecycleEvents.isEmpty ? "none" : lifecycleEvents.joined(separator: "\n"))
        Continuous API-accepted distance: \(String(format: "%.1f", continuousAcceptedMeters)) m
        Continuous ticks: \(continuousAcceptedTicks) accepted, \(continuousFailedTicks) failed
        Cruise active: \(cruiseActive), remaining seconds: \(cruiseSecondsRemaining)
        Update interval target: \(movementTickInterval) s (actual elapsed time measured and capped)
        Last requested: \(coordinate(lastRequestedCoordinate))
        Last API-accepted: \(coordinate(lastAcceptedCoordinate))
        Latest Roam CoreLocation callback: \(coordinate(lastObservedCoordinate)) at \(observedTime)
        CoreLocation callbacks are not independent verification by Apple Maps.
        Engine stage: \(LocationEngine.lastStage)
        Engine failure: \(LocationEngine.lastFailure)
        Recent events:
        \(rows.isEmpty ? "none" : rows)
        """
    }

    private func recordMovement(action: String, coordinate: CLLocationCoordinate2D, succeeded: Bool, extra: String = "") {
        movementAttempts += 1
        if succeeded { lastMovementCommandAt = Date() }
        lastRequestedCoordinate = coordinate
        if succeeded {
            movementAccepted += 1
            lastAcceptedCoordinate = coordinate
        } else {
            movementFailed += 1
        }
        let baseDetail = succeeded
            ? "location_simulation_set returned success (not independently verified)"
            : "\(LocationEngine.lastStage): \(LocationEngine.lastFailure)"
        let detail = extra.isEmpty ? baseDetail : "\(baseDetail); \(extra)"
        lastMovementResult = "\(action): \(succeeded ? "API accepted" : "API failed")"
        movementEvents.insert(MovementDiagnosticEvent(
            timestamp: Date(), action: action, succeeded: succeeded, detail: detail
        ), at: 0)
        if movementEvents.count > 60 { movementEvents.removeLast(movementEvents.count - 60) }
    }

    func followRoute(_ coordinates: [CLLocationCoordinate2D], pairing: PairingStore) {
        guard pairing.hasPairingFile, coordinates.count >= 2 else { return }
        routeTask?.cancel()
        stopJoystick()
        stopCruise(reason: "Switched to route playback")
        let mode = travelMode
        routeTask = Task { [weak self] in
            guard let self else { return }
            var previous = coordinates[0]
            await MainActor.run {
                self.apply(previous, pairing: pairing, markRecent: true)
            }
            for next in coordinates.dropFirst() {
                if Task.isCancelled { break }
                let distance = CLLocation(latitude: previous.latitude, longitude: previous.longitude)
                    .distance(from: CLLocation(latitude: next.latitude, longitude: next.longitude))
                var speed = mode.baseSpeed * Double.random(in: 0.88...1.12)
                speed = max(0.8, speed)
                let stepMeters: CLLocationDistance = min(12, max(4, speed * 0.5))
                let steps = max(1, Int(ceil(distance / stepMeters)))
                for i in 1...steps {
                    if Task.isCancelled { break }
                    let t = Double(i) / Double(steps)
                    let coord = CLLocationCoordinate2D(
                        latitude: previous.latitude + (next.latitude - previous.latitude) * t,
                        longitude: previous.longitude + (next.longitude - previous.longitude) * t
                    )
                    let delay = stepMeters / speed
                    try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                    await MainActor.run {
                        self.apply(coord, pairing: pairing, markRecent: false)
                    }
                }
                previous = next
            }
        }
    }

    func addFavorite(name: String, coordinate: CLLocationCoordinate2D) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let place = SavedPlace(
            name: trimmed.isEmpty ? Self.coordinateLabel(coordinate) : trimmed,
            latitude: coordinate.latitude,
            longitude: coordinate.longitude
        )
        // Don't let a generic star overwrite a named favorite for the same spot.
        if let existing = favorites.first(where: { $0.id == place.id }),
           Self.isGenericFavoriteName(place.name),
           !Self.isGenericFavoriteName(existing.name) {
            return
        }
        favorites.removeAll { $0.id == place.id }
        favorites.insert(place, at: 0)
        SavedPlace.save(favorites, key: favoritesKey)
    }

    func renameFavorite(_ place: SavedPlace, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let index = favorites.firstIndex(where: { $0.id == place.id }) else { return }
        favorites[index].name = trimmed
        SavedPlace.save(favorites, key: favoritesKey)
    }

    func removeFavorite(_ place: SavedPlace) {
        favorites.removeAll { $0.id == place.id }
        SavedPlace.save(favorites, key: favoritesKey)
    }

    func removeRecent(_ place: SavedPlace) {
        recents.removeAll { $0.id == place.id }
        SavedPlace.save(recents, key: recentsKey)
    }

    /// Best display name for starring the current pin (search title, matching recent, etc.).
    func suggestedFavoriteName(for coordinate: CLLocationCoordinate2D, fallback: String? = nil) -> String {
        if let fallback, !fallback.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return fallback.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let favorite = favorites.first(where: { $0.id == SavedPlace(name: "", latitude: coordinate.latitude, longitude: coordinate.longitude).id }),
           !Self.isGenericFavoriteName(favorite.name) {
            return favorite.name
        }
        if let recent = recents.first(where: {
            abs($0.latitude - coordinate.latitude) < 0.00015 && abs($0.longitude - coordinate.longitude) < 0.00015
        }), !Self.isGenericFavoriteName(recent.name) {
            return recent.name
        }
        return Self.coordinateLabel(coordinate)
    }

    private static func coordinateLabel(_ coordinate: CLLocationCoordinate2D) -> String {
        String(format: "%.5f, %.5f", coordinate.latitude, coordinate.longitude)
    }

    private static func isGenericFavoriteName(_ name: String) -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || trimmed == "Favorite" { return true }
        // Coordinate-looking labels from older teleports.
        let parts = trimmed.split(separator: ",")
        if parts.count == 2,
           Double(parts[0].trimmingCharacters(in: .whitespaces)) != nil,
           Double(parts[1].trimmingCharacters(in: .whitespaces)) != nil {
            return true
        }
        return false
    }

    @discardableResult
    private func apply(_ coordinate: CLLocationCoordinate2D, pairing: PairingStore, markRecent: Bool) -> Bool {
        if status == .idle || status.isDropped {
            status = .connecting
        }
        isBusy = true
        let result = LocationEngine.set(
            latitude: coordinate.latitude,
            longitude: coordinate.longitude,
            pairingPath: pairing.pairingPath,
            deviceIP: TunnelConfig.targetIP
        )
        isBusy = false
        switch result {
        case .success:
            simulated = coordinate
            pin = coordinate
            status = .active
            lastError = nil
            // Do not hold an unlimited UIApplication background assertion for
            // the entire simulation. The v0.17 trial has its OWN finite task.
            locationKeeper.start()
            if automaticRetriesEnabled {
                startResend(pairing: pairing)
                startHealth(pairing: pairing)
            }
            if markRecent {
                pushRecent(coordinate)
            }
            return true
        case .failure(let error):
            lastError = error.localizedDescription
            if simulated != nil {
                stopJoystick()
                stopCruise(reason: "Movement stopped after location API failure")
                routeTask?.cancel()
                stopResend()
                stopHealth()
                status = .dropped(error.localizedDescription)
                postDropNotification(error.localizedDescription)
            } else {
                status = .idle
            }
            return false
        }
    }

    private func tickJoystick(pairing: PairingStore) {
        guard joystickActive else { return }
        let vector = joystickVector
        guard hypot(vector.dx, vector.dy) > 0.08 else {
            lastMovementTickUptime = nil
            return
        }
        sendContinuousMovement(vector: vector, label: "Joystick \(travelMode.title)", pairing: pairing)
    }

    private func tickCruise(pairing: PairingStore) {
        guard cruiseActive, let deadline = cruiseDeadlineUptime else { return }
        let remaining = deadline - ProcessInfo.processInfo.systemUptime
        if backgroundTrialEnabled { recordBackgroundTrialTimerGap() }
        if remaining <= 0 {
            let label = backgroundTrialEnabled ? "\(backgroundTrialPlannedSeconds)s scheduling window elapsed" : "20-second trial completed"
            let caveat = backgroundTrialEnabled && backgroundTrialLargeTickGaps > 0
                ? "; detected \(backgroundTrialLargeTickGaps) delayed timer gap(s)"
                : ""
            stopCruise(reason: "\(label)\(caveat); last API-accepted coordinate held")
            return
        }
        // A background timer firing is NOT permission to continue unless the
        // specifically scoped experiment still has a valid UIKit assertion.
        if actuallyInBackground && (!backgroundTrialEnabled || shortCruiseTask == .invalid) {
            stopCruise(reason: "Background assertion unavailable; trial paused")
            pausedCruiseSeconds = remaining
            return
        }
        cruiseSecondsRemaining = Int(ceil(remaining))
        sendContinuousMovement(vector: CGVector(dx: 0, dy: -1),
                               label: "Cruise north \(travelMode.title)", pairing: pairing)
        if cruiseActive && ProcessInfo.processInfo.systemUptime >= deadline {
            let label = backgroundTrialEnabled ? "\(backgroundTrialPlannedSeconds)s scheduling window elapsed" : "20-second trial completed"
            let caveat = backgroundTrialEnabled && backgroundTrialLargeTickGaps > 0
                ? "; detected \(backgroundTrialLargeTickGaps) delayed timer gap(s)"
                : ""
            stopCruise(reason: "\(label)\(caveat); last API-accepted coordinate held")
        }
    }

    /// Measures scheduling gaps only; a successful API call cannot prove the
    /// blue dot moved continuously while another app was in the foreground.
    private func recordBackgroundTrialTimerGap() {
        let now = ProcessInfo.processInfo.systemUptime
        let prior = backgroundTrialLastTickUptime ?? backgroundTrialStartedUptime ?? now
        let gap = max(0, now - prior)
        backgroundTrialLongestTickGap = max(backgroundTrialLongestTickGap, gap)
        if gap > 2.5 {
            backgroundTrialLargeTickGaps += 1
            logLifecycle("Experimental cruise timer gap \(String(format: "%.2f", gap))s; possible suspension/interruption")
        }
        backgroundTrialLastTickUptime = now
    }

    /// Both joystick and timed trial use this same location-simulation API.
    /// Monotonic elapsed time prevents an 0.8-second tick from accidentally
    /// implying the same distance after a stalled network call. We cap long
    /// scheduling gaps so foreground suspension doesn't cause a location jump.
    private func sendContinuousMovement(vector: CGVector, label: String, pairing: PairingStore) {
        guard let current = simulated, LocationEngine.isSessionActive, !isBusy else {
            lastContinuousStatus = "No valid retained session for movement"
            stopContinuousMovementAfterFailure()
            return
        }
        let magnitude = hypot(vector.dx, vector.dy)
        guard magnitude > 0.08 else { return }
        let now = ProcessInfo.processInfo.systemUptime
        let elapsed = lastMovementTickUptime.map { now - $0 } ?? movementTickInterval
        lastMovementTickUptime = now
        let dt = max(0.1, min(elapsed, 1.2))
        let speed = travelMode.baseSpeed * min(1.0, magnitude)
        let meters = speed * dt
        let next = offset(coordinate: current,
                          eastMeters: vector.dx / magnitude * meters,
                          northMeters: -vector.dy / magnitude * meters)
        let wasBackgroundTrialTick = actuallyInBackground && backgroundTrialEnabled
        let succeeded = apply(next, pairing: pairing, markRecent: false)
        let actionLabel = wasBackgroundTrialTick ? "BACKGROUND \(label)" : label
        recordMovement(action: actionLabel, coordinate: next, succeeded: succeeded,
                       extra: String(format: "dt %.2f s, requested %.2f m; scene background=%@", dt, meters, wasBackgroundTrialTick ? "yes" : "no"))
        if wasBackgroundTrialTick {
            backgroundTrialAttempts += 1
            lastBackgroundTrialCommandAt = Date()
            if succeeded {
                backgroundTrialAccepted += 1
                backgroundTrialAcceptedMeters += meters
            } else {
                backgroundTrialFailed += 1
            }
            backgroundTrialStatus = "Background location API \(succeeded ? "accepted" : "failed") at \(lastBackgroundTrialCommandAt?.formatted(date: .omitted, time: .standard) ?? "unknown")"
            logLifecycle("Background GPS command \(succeeded ? "accepted" : "FAILED"); requested \(String(format: "%.2f", meters))m")
        }
        if succeeded {
            continuousAcceptedTicks += 1
            continuousAcceptedMeters += meters
            lastContinuousStatus = String(format: "%@: accepted %d updates, %.1f m requested/accepted by API", actionLabel, continuousAcceptedTicks, continuousAcceptedMeters)
        } else {
            continuousFailedTicks += 1
            lastContinuousStatus = "\(label): API failed — movement stopped; session handle not cleared"
            stopContinuousMovementAfterFailure()
        }
    }

    private func stopContinuousMovementAfterFailure() {
        // Do not call LocationEngine.clear, and do not retry opening a tunnel
        // over 4G. Keep the existing handle for diagnostics and a manual step.
        stopJoystick()
        if cruiseActive { stopCruise(reason: "Movement halted after API failure; session handle retained") }
    }

    private func startResend(pairing: PairingStore) {
        resendTimer?.invalidate()
        resendTimer = Timer.scheduledTimer(withTimeInterval: 8, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, let sim = self.simulated else { return }
                _ = LocationEngine.set(
                    latitude: sim.latitude,
                    longitude: sim.longitude,
                    pairingPath: pairing.pairingPath,
                    deviceIP: TunnelConfig.targetIP
                )
            }
        }
    }

    private func stopResend() {
        resendTimer?.invalidate()
        resendTimer = nil
    }

    private func startHealth(pairing: PairingStore) {
        healthTimer?.invalidate()
        healthTimer = Timer.scheduledTimer(withTimeInterval: 12, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, let sim = self.simulated else { return }
                if case .dropped = self.status {
                    self.status = .reconnecting
                    self.apply(sim, pairing: pairing, markRecent: false)
                } else if !LocationEngine.isSessionActive, self.isSpoofing {
                    self.status = .reconnecting
                    self.apply(sim, pairing: pairing, markRecent: false)
                }
            }
        }
    }

    private func stopHealth() {
        healthTimer?.invalidate()
        healthTimer = nil
    }

    private func pushRecent(_ coordinate: CLLocationCoordinate2D) {
        pushNamedRecent(
            name: Self.coordinateLabel(coordinate),
            coordinate: coordinate
        )
    }

    func pushNamedRecent(name: String, coordinate: CLLocationCoordinate2D) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let place = SavedPlace(
            name: trimmed.isEmpty ? Self.coordinateLabel(coordinate) : trimmed,
            latitude: coordinate.latitude,
            longitude: coordinate.longitude
        )
        recents.removeAll {
            abs($0.latitude - place.latitude) < 0.00015 && abs($0.longitude - place.longitude) < 0.00015
        }
        recents.insert(place, at: 0)
        if recents.count > 20 { recents = Array(recents.prefix(20)) }
        SavedPlace.save(recents, key: recentsKey)
    }

    /// User-started, finite UIKit assertion for just one 20/30/60s trial.
    /// UIKit may expire it before the desired duration. The expiration handler
    /// must stop the trial and release the assertion, NOT schedule a new one.
    private func beginShortCruiseTask(duration: Int) -> Bool {
        guard shortCruiseTask == .invalid else { return true }
        let identifier = UIApplication.shared.beginBackgroundTask(withName: "Roam \(duration)s finite cruise") { [weak self] in
            guard let self else { return }
            self.backgroundTrialExpirations += 1
            let remaining = max(0, (self.cruiseDeadlineUptime ?? ProcessInfo.processInfo.systemUptime) - ProcessInfo.processInfo.systemUptime)
            self.logLifecycle("iOS background task expired; stopping trial with \(String(format: "%.1f", remaining))s scheduled remaining")
            self.stopCruise(reason: "iOS background task expired with \(String(format: "%.1f", remaining))s remaining; no new background task requested")
            // An expired EXPERIMENT must not silently resume as a standard
            // cruise, which would distort the 30/60s background test result.
            self.pausedCruiseSeconds = nil
        }
        guard identifier != .invalid else {
            backgroundTrialTaskHeld = false
            return false
        }
        shortCruiseTask = identifier
        backgroundTrialTaskHeld = true
        logLifecycle("Finite \(duration)s background assertion requested while foreground")
        return true
    }

    private func endShortCruiseTask() {
        guard shortCruiseTask != .invalid else { return }
        let identifier = shortCruiseTask
        shortCruiseTask = .invalid
        backgroundTrialTaskHeld = false
        UIApplication.shared.endBackgroundTask(identifier)
    }

    private func postDropNotification(_ message: String) {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
        let content = UNMutableNotificationContent()
        content.title = "Roam location session interrupted"
        content.body = message
        content.sound = .default
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    private func offset(coordinate: CLLocationCoordinate2D, eastMeters: Double, northMeters: Double) -> CLLocationCoordinate2D {
        let earth = 6378137.0
        let dLat = northMeters / earth * (180 / .pi)
        let dLon = eastMeters / (earth * cos(coordinate.latitude * .pi / 180)) * (180 / .pi)
        return CLLocationCoordinate2D(latitude: coordinate.latitude + dLat, longitude: coordinate.longitude + dLon)
    }
}
