import SwiftUI
import CoreLocation
import NetworkExtension

// Roam v0.5: a branded interface over the original, unchanged GPS engine.
struct RootView: View {
    @EnvironmentObject private var session: SpoofSession
    @EnvironmentObject private var pairing: PairingStore
    @Environment(\.scenePhase) private var scenePhase
    @State private var showSettings = false
    @State private var showPlaces = false

    var body: some View {
        ZStack(alignment: .bottom) {
            RoamPalette.background.ignoresSafeArea()
            MapHomeView()

            BottomControlsView(
                showSettings: $showSettings,
                showPlaces: $showPlaces
            )
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
        }
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showSettings) { SettingsView() }
        .sheet(isPresented: $showPlaces) { PlacesView() }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .background: session.applicationEnteredBackground()
            case .inactive: session.applicationBecameInactive()
            case .active: session.applicationBecameActive(pairing: pairing)
            @unknown default: break
            }
        }
        .alert("Roam", isPresented: Binding(
            get: { session.lastError != nil },
            set: { if !$0 { session.lastError = nil } }
        )) {
            Button("OK", role: .cancel) { session.lastError = nil }
        } message: {
            Text(session.lastError ?? "")
        }
    }
}

/// Lightweight on-map logo. The official brand image is used for the app icon.
struct RoamBrandMark: View {
    var size: CGFloat = 46

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                .fill(RoamPalette.midnight)
                .overlay {
                    RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                        .stroke(RoamPalette.electricBlue.opacity(0.55), lineWidth: 1)
                }
            Circle()
                .stroke(RoamPalette.turquoise.opacity(0.62), lineWidth: 1.6)
                .frame(width: size * 0.74, height: size * 0.25)
                .rotationEffect(.degrees(-25))
                .offset(y: size * 0.12)
            Image(systemName: "mappin.circle.fill")
                .font(.system(size: size * 0.53, weight: .bold))
                .foregroundStyle(RoamPalette.primaryGradient)
                .shadow(color: RoamPalette.turquoise.opacity(0.26), radius: 6)
                .offset(y: -size * 0.06)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

struct StatusBarView: View {
    @EnvironmentObject private var session: SpoofSession
    @Environment(\.scenePhase) private var scenePhase
    @State private var tunnelConnected = LocalDevVPN.isConnected

    private var isActive: Bool {
        if case .active = session.status { return true }
        return false
    }

    private var statusColor: Color {
        switch session.status {
        case .active: return LocusTheme.statusGood
        case .connecting, .reconnecting: return LocusTheme.statusWarn
        case .dropped: return LocusTheme.statusBad
        case .idle: return tunnelConnected ? RoamPalette.turquoise : LocusTheme.statusWarn
        }
    }

    private var sessionLabel: String {
        switch session.status {
        case .idle: return "READY TO EXPLORE"
        case .connecting: return "STARTING LOCATION"
        case .active: return "LOCATION ACTIVE"
        case .reconnecting: return "RECONNECTING"
        case .dropped: return "SESSION INTERRUPTED"
        }
    }

    private var detailText: String {
        if !tunnelConnected { return "VPN interface not observed — tap to check LocalDevVPN" }
        if isActive { return "Virtual movement enabled while the session remains active" }
        return "VPN-like interface seen • developer tunnel NOT verified"
    }

    var body: some View {
        Group {
            if !tunnelConnected {
                Button(action: LocalDevVPN.openOrInstall) { content }
                    .buttonStyle(.plain)
            } else {
                content
            }
        }
        .onAppear(perform: refreshTunnel)
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { refreshTunnel() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .NEVPNStatusDidChange)) { _ in
            refreshTunnel()
        }
        .task(id: scenePhase) {
            guard scenePhase == .active else { return }
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                if Task.isCancelled { break }
                refreshTunnel()
            }
        }
    }

    private var content: some View {
        HStack(spacing: 11) {
            ZStack {
                Circle().fill(statusColor.opacity(0.13)).frame(width: 32, height: 32)
                Circle().fill(statusColor).frame(width: 8, height: 8)
                    .shadow(color: statusColor.opacity(0.8), radius: 5)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(sessionLabel)
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .tracking(1.45)
                    .foregroundStyle(.white)
                Text(detailText)
                    .font(.system(size: 11))
                    .foregroundStyle(RoamPalette.muted)
                    .lineLimit(2)
            }
            Spacer(minLength: 4)
            Image(systemName: tunnelConnected ? "shield.lefthalf.filled" : "arrow.up.right")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(tunnelConnected ? RoamPalette.turquoise : LocusTheme.statusWarn)
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 10)
        .roamSurface(cornerRadius: 17)
        .accessibilityElement(children: .combine)
    }

    private func refreshTunnel() { tunnelConnected = LocalDevVPN.isConnected }
}

struct BottomControlsView: View {
    @EnvironmentObject private var session: SpoofSession
    @EnvironmentObject private var pairing: PairingStore
    @Binding var showSettings: Bool
    @Binding var showPlaces: Bool
    @State private var confirmEndSimulation = false
    @State private var showMovementDiagnostics = false
    @State private var controlsMinimized = false
    @State private var joystickOnRight = false

    private var speedCaption: String {
        String(format: "%.0f mph preset", session.travelMode.baseSpeed * 2.2369362921)
    }

    // v0.21: keep the map tappable after a teleport. Hiding controls is a
    // presentation change only: it must never end or clear the GPS session.
    private var compactControls: some View {
        VStack(spacing: 7) {
        HStack(spacing: 9) {
            Button {
                withAnimation(.easeInOut(duration: 0.22)) {
                    controlsMinimized = false
                }
            } label: {
                Label("Expand", systemImage: "chevron.up")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(minHeight: 42)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Expand movement controls")

            Button {
                showMovementDiagnostics = true
            } label: {
                Image(systemName: "waveform.path.ecg")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(RoamPalette.turquoise)
                    .frame(width: 40, height: 42)
                    .background(Color.white.opacity(0.06), in: Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Open GPS movement diagnostics")

            Spacer(minLength: 0)

            Button {
                guard let pin = session.pin else {
                    session.lastError = "Choose a destination on the map first."
                    return
                }
                session.teleport(to: pin, pairing: pairing)
            } label: {
                Label(session.isSpoofing ? "Re-teleport" : "Teleport", systemImage: "location.north.fill")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(RoamPalette.background)
                    .padding(.horizontal, 13)
                    .frame(minHeight: 42)
                    .background(RoamPalette.primaryGradient, in: Capsule())
            }
            .buttonStyle(.plain)
            .disabled(session.isBusy)
            .opacity(session.isBusy ? 0.65 : 1)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .roamSurface(cornerRadius: 22)
        if session.cruiseActive {
            HStack {
                Text("Cruise in progress")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white)
                Spacer()
                Button {
                    session.stopCruise()
                } label: {
                    Label("Stop movement", systemImage: "stop.fill")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white)
                }
                .buttonStyle(.bordered)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
            .roamSurface(cornerRadius: 16)
        }
        }
    }

    // The larger controls live in a separate view expression so the compact map
    // presentation does not make SwiftUI type-check the entire screen at once.
    private var expandedControls: some View {
        VStack(spacing: 12) {
            if session.joystickActive {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 7) {
                        Image(systemName: "hand.draw.fill")
                            .foregroundStyle(RoamPalette.turquoise)
                        Text("DRAG TO MOVE")
                            .tracking(1.2)
                            .foregroundStyle(.white)
                        Spacer()
                        Text(speedCaption)
                            .foregroundStyle(RoamPalette.muted)
                    }
                    .font(.system(size: 11, weight: .bold))
                    HStack(spacing: 12) {
                        if joystickOnRight { Spacer(minLength: 4) }
                        JoystickPad { vector in session.updateJoystick(vector: vector) }
                            .frame(width: 102, height: 102)
                        VStack(alignment: .leading, spacing: 8) {
                            Button {
                                joystickOnRight.toggle()
                            } label: {
                                Label(joystickOnRight ? "Move left" : "Move right", systemImage: "arrow.left.arrow.right")
                                    .font(.system(size: 11, weight: .semibold))
                            }
                            .buttonStyle(.bordered)
                            Text(session.lastContinuousStatus)
                                .font(.system(size: 10))
                                .foregroundStyle(RoamPalette.muted)
                                .lineLimit(4)
                        }
                        if !joystickOnRight { Spacer(minLength: 4) }
                    }
                    .padding(.vertical, 2)
                }
                .padding(13)
                .roamSurface(cornerRadius: 22)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            VStack(alignment: .leading, spacing: 13) {
                HStack(spacing: 7) {
                    ForEach(TravelMode.allCases) { mode in
                        modeButton(mode)
                    }
                }

                Rectangle()
                    .fill(RoamPalette.border)
                    .frame(height: 1)

                HStack(spacing: 9) {
                    smallButton("star.fill", accessibility: "Saved places") { showPlaces = true }
                    smallButton("gearshape.fill", accessibility: "Settings") { showSettings = true }

                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            if session.joystickActive {
                                session.stopJoystick()
                            } else {
                                session.startJoystick(pairing: pairing)
                            }
                        }
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "circle.grid.cross")
                            Text(session.joystickActive ? "Close" : "Move")
                        }
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(session.joystickActive ? RoamPalette.turquoise : .white)
                        .frame(maxWidth: .infinity, minHeight: 46)
                        .background(
                            Capsule().fill(RoamPalette.electricBlue.opacity(0.17))
                        )
                        .overlay(Capsule().stroke(RoamPalette.electricBlue.opacity(0.5), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(session.joystickActive ? "Close joystick" : "Open joystick")

                    // v0.11: Teleport stays visible even with an active simulation.
                    // This calls location_simulation_set on the RETAINED handle.
                    Button {
                        guard let pin = session.pin else {
                            session.lastError = "Choose a destination on the map first."
                            return
                        }
                        session.teleport(to: pin, pairing: pairing)
                        withAnimation(.easeInOut(duration: 0.22)) {
                            controlsMinimized = true
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "location.north.fill")
                                .font(.system(size: 12))
                            Text(session.isSpoofing ? "Re-teleport" : "Teleport")
                        }
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(RoamPalette.background)
                        .frame(minWidth: 106, minHeight: 46)
                        .background(RoamPalette.primaryGradient, in: Capsule())
                        .shadow(color: RoamPalette.electricBlue.opacity(0.26), radius: 8, y: 4)
                    }
                    .buttonStyle(.plain)
                    .disabled(session.isBusy)
                    .opacity(session.isBusy ? 0.65 : 1)
                }

                if session.isSpoofing {
                    // v0.13: deterministic single movement using the retained GPS handle.
                    HStack(spacing: 8) {
                        Button {
                            session.stepNorth200(pairing: pairing)
                        } label: {
                            Label("Step 200 m N", systemImage: "arrow.up")
                                .font(.system(size: 11, weight: .bold))
                                .frame(maxWidth: .infinity, minHeight: 38)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(RoamPalette.electricBlue)
                        .disabled(session.isBusy)

                        Button {
                            session.holdPosition()
                        } label: {
                            Label("Hold position", systemImage: "hand.raised.fill")
                                .font(.system(size: 11, weight: .semibold))
                                .frame(maxWidth: .infinity, minHeight: 38)
                        }
                        .buttonStyle(.bordered)
                        .disabled(session.isBusy)
                    }
                    // v0.14: a measurable continuous movement trial which ends
                    // on its own before inspecting Apple Maps. Never clears GPS.
                    HStack(spacing: 8) {
                        if session.cruiseActive {
                            Button {
                                session.stopCruise()
                            } label: {
                                Label("Stop moving (\(session.cruiseSecondsRemaining)s)", systemImage: "stop.circle")
                                    .font(.system(size: 11, weight: .semibold))
                                    .frame(maxWidth: .infinity, minHeight: 38)
                            }
                            .buttonStyle(.bordered)
                        } else {
                            Button {
                                session.startNorthCruise20(pairing: pairing)
                            } label: {
                                Label("Move north for 20s", systemImage: "arrow.up.forward")
                                    .font(.system(size: 11, weight: .semibold))
                                    .frame(maxWidth: .infinity, minHeight: 38)
                            }
                            .buttonStyle(.bordered)
                            .disabled(session.isBusy)
                        }
                        Text(String(format: "%.1f m API accepted", session.continuousAcceptedMeters))
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(RoamPalette.turquoise)
                            .frame(maxWidth: .infinity)
                    }
                    if !session.cruiseActive {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("BACKGROUND CRUISE — LIMITED EXPERIMENT")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(RoamPalette.turquoise)
                            HStack(spacing: 8) {
                                ForEach([20, 30, 60], id: \.self) { duration in
                                    Button {
                                        session.startBackgroundCruise(duration: duration, pairing: pairing)
                                    } label: {
                                        Text("\(duration)s")
                                            .font(.system(size: 12, weight: .bold))
                                            .frame(maxWidth: .infinity, minHeight: 40)
                                    }
                                    .buttonStyle(.borderedProminent)
                                    .tint(RoamPalette.turquoise)
                                    .disabled(session.isBusy)
                                }
                            }
                            Text("LONGER-DURATION EXPERIMENTS — MAY END EARLY")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(RoamPalette.muted)
                            HStack(spacing: 8) {
                                ForEach([90, 120, 300], id: \.self) { duration in
                                    Button {
                                        session.startBackgroundCruise(duration: duration, pairing: pairing)
                                    } label: {
                                        Text(duration == 90 ? "90s" : duration == 120 ? "2m" : "5m")
                                            .font(.system(size: 12, weight: .bold))
                                            .frame(maxWidth: .infinity, minHeight: 40)
                                    }
                                    .buttonStyle(.bordered)
                                    .disabled(session.isBusy)
                                }
                            }
                        }
                    }
                    Text("v0.22: The control header stays visible while you scroll. Tap Minimise to select a new map destination; Expand for joystick and 20/30/60/90/120/300s trials. Background execution can end early.")
                        .font(.system(size: 10))
                        .foregroundStyle(RoamPalette.muted)
                }

                Button {
                    showMovementDiagnostics = true
                } label: {
                    HStack {
                        Label("GPS movement diagnostics", systemImage: "waveform.path.ecg")
                        Spacer()
                        Text("\(session.movementAccepted)/\(session.movementAttempts) API accepted")
                        Image(systemName: "chevron.right")
                    }
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(RoamPalette.turquoise)
                }
                .buttonStyle(.plain)

                if session.isSpoofing {
                    HStack(spacing: 10) {
                        Button {
                            session.pauseMovement()
                        } label: {
                            Label("Pause movement", systemImage: "pause.fill")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity, minHeight: 38)
                                .background(RoamPalette.electricBlue.opacity(0.17), in: Capsule())
                        }
                        .buttonStyle(.plain)

                        Button {
                            confirmEndSimulation = true
                        } label: {
                            Label("End simulation", systemImage: "stop.fill")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity, minHeight: 38)
                                .background(LocusTheme.danger.opacity(0.92), in: Capsule())
                        }
                        .buttonStyle(.plain)
                        .disabled(session.isBusy)
                    }
                }
                Text(session.lastTeleportResult)
                    .font(.system(size: 10))
                    .foregroundStyle(RoamPalette.muted)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityLabel(session.lastTeleportResult)
            }
            // The outer panel owns the surface and rounded clipping; the
            // scrollable contents must not draw a second card that gets cut off.
        }
    }

    // v0.21: Keep the title, current speed and minimise control fixed. Only
    // the movement options scroll within the rounded card below this header.
    // This prevents the top of the controls appearing chopped off on scroll.
    private var expandedControlsHeader: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text("MOVEMENT MODE")
                    .font(.system(size: 10, weight: .bold))
                    .tracking(2)
                    .foregroundStyle(RoamPalette.muted)
                Spacer()
                Button {
                    if session.joystickActive { session.stopJoystick() }
                    withAnimation(.easeInOut(duration: 0.22)) {
                        controlsMinimized = true
                    }
                } label: {
                    Label("Minimise", systemImage: "chevron.down")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(RoamPalette.turquoise)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Minimise controls to use the map")
            }
            HStack(spacing: 8) {
                Text("Choose your pace")
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                Spacer(minLength: 4)
                Text(speedCaption)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(RoamPalette.turquoise)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(RoamPalette.turquoise.opacity(0.11), in: Capsule())
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 15)
        .padding(.bottom, 12)
    }

    var body: some View {
        VStack(spacing: 10) {
            if controlsMinimized {
                compactControls
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            } else {
                VStack(spacing: 0) {
                    expandedControlsHeader
                    Rectangle()
                        .fill(RoamPalette.border)
                        .frame(height: 1)
                        .padding(.horizontal, 16)
                    ScrollView(.vertical) {
                        expandedControls
                            .padding(.horizontal, 16)
                            .padding(.top, 14)
                            .padding(.bottom, 18)
                    }
                    .scrollIndicators(.automatic)
                    .scrollBounceBehavior(.basedOnSize)
                    .frame(maxHeight: 350)
                    .clipped()
                }
                .roamSurface(cornerRadius: 25)
                .clipShape(RoundedRectangle(cornerRadius: 25, style: .continuous))
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .onChange(of: session.isSpoofing) { _, active in
            if active {
                withAnimation(.easeInOut(duration: 0.22)) {
                    controlsMinimized = true
                }
            }
        }
        .sheet(isPresented: $showMovementDiagnostics) {
            MovementDiagnosticsView(onMinimise: {
                withAnimation(.easeInOut(duration: 0.22)) {
                    controlsMinimized = true
                }
            })
                .environmentObject(session)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .confirmationDialog(
            "End GPS simulation?",
            isPresented: $confirmEndSimulation,
            titleVisibility: .visible
        ) {
            Button("End Simulation", role: .destructive) {
                session.stop(pairing: pairing)
            }
            Button("Keep Simulation", role: .cancel) { }
        } message: {
            Text("This clears the simulated GPS position. On cellular, you may need Wi-Fi again to start a new session.")
        }
    }

    private func modeButton(_ mode: TravelMode) -> some View {
        let selected = session.travelMode == mode
        return Button {
            session.travelMode = mode
        } label: {
            VStack(spacing: 6) {
                Image(systemName: mode.icon)
                    .font(.system(size: 18, weight: .medium))
                    .frame(height: 20)
                Text(mode.title)
                    .font(.system(size: 11, weight: .semibold))
            }
            .foregroundStyle(selected ? RoamPalette.background : RoamPalette.muted)
            .frame(maxWidth: .infinity, minHeight: 56)
            .background {
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .fill(selected ? RoamPalette.turquoise : Color.white.opacity(0.045))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .stroke(selected ? RoamPalette.turquoise : RoamPalette.border, lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func smallButton(_ icon: String, accessibility: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(RoamPalette.muted)
                .frame(width: 41, height: 46)
                .background(Color.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 13))
                .overlay {
                    RoundedRectangle(cornerRadius: 13).stroke(RoamPalette.border, lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibility)
    }
}

// Retained for other screens that may use the original helper.
struct IconButton: View {
    let systemName: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.body.weight(.semibold))
                .frame(width: 44, height: 44)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .locusGlass(.interactive, in: Circle())
        .foregroundStyle(.primary)
    }
}

// Roam v0.13: developer-API acknowledgements are explicitly labelled. The
// Roam CLLocation observation can be stale or simulated, so Apple Maps remains
// the separate check for system-wide movement.
private struct MovementDiagnosticsView: View {
    let onMinimise: () -> Void
    @EnvironmentObject private var session: SpoofSession
    @Environment(\.dismiss) private var dismiss

    private func coordinateText(_ c: CLLocationCoordinate2D?) -> String {
        guard let c else { return "Not available" }
        return String(format: "%.7f, %.7f", c.latitude, c.longitude)
    }

    var body: some View {
        NavigationStack {
            List {
                Section("Movement commands") {
                    LabeledContent("Attempted", value: String(session.movementAttempts))
                    LabeledContent("API accepted", value: String(session.movementAccepted))
                    LabeledContent("API failed", value: String(session.movementFailed))
                    Text(session.lastMovementResult)
                        .font(.footnote)
                }
                Section("Continuous movement (v0.22)") {
                    LabeledContent("Accepted movement updates", value: String(session.continuousAcceptedTicks))
                    LabeledContent("Failed movement updates", value: String(session.continuousFailedTicks))
                    LabeledContent("Distance accepted by API", value: String(format: "%.1f metres", session.continuousAcceptedMeters))
                    LabeledContent("Cruise running", value: session.cruiseActive ? "Yes" : "No")
                    Text(session.lastContinuousStatus).font(.footnote)
                    Text("The standard cruise pauses on background entry. Only a separately started experimental 20/30/60/90/120/300s trial attempts location updates while Roam is backgrounded, and only while the finite iOS task is allowed to run.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Section("Extended background cruise (v0.22)") {
                    LabeledContent("Planned trial duration", value: "\(session.backgroundTrialPlannedSeconds) seconds")
                    LabeledContent("Measured trial elapsed", value: String(format: "%.1f seconds", session.backgroundTrialActualSeconds))
                    LabeledContent("Observed background time", value: String(format: "%.1f seconds", session.backgroundTrialObservedBackgroundSeconds))
                    LabeledContent("Lowest background allowance", value: session.backgroundTrialMinimumBudgetSeconds.map { String(format: "%.1f seconds", $0) } ?? "Not available")
                    LabeledContent("Safe budget stops", value: String(session.backgroundTrialBudgetStops))
                    LabeledContent("End reason", value: session.backgroundTrialEndReason)
                    LabeledContent("Longest command gap", value: String(format: "%.2f seconds", session.backgroundTrialLongestTickGap))
                    LabeledContent("Gaps over 2.5s", value: String(session.backgroundTrialLargeTickGaps))
                    LabeledContent("Background task held", value: session.backgroundTrialTaskHeld ? "Yes" : "No")
                    LabeledContent("Background commands attempted", value: String(session.backgroundTrialAttempts))
                    LabeledContent("Background API accepted", value: String(session.backgroundTrialAccepted))
                    LabeledContent("Background API failed", value: String(session.backgroundTrialFailed))
                    LabeledContent("Background API-accepted distance", value: String(format: "%.1f metres", session.backgroundTrialAcceptedMeters))
                    LabeledContent("Task expirations", value: String(session.backgroundTrialExpirations))
                    if let when = session.lastBackgroundTrialCommandAt {
                        LabeledContent("Last background command", value: when.formatted(date: .omitted, time: .standard))
                    }
                    Text(session.backgroundTrialStatus).font(.footnote)
                    if !session.backgroundTrialHistory.isEmpty {
                        Text("Recent trial summaries").font(.subheadline.weight(.semibold))
                        ForEach(session.backgroundTrialHistory, id: \.self) { summary in
                            Text(summary).font(.caption2).textSelection(.enabled)
                        }
                    }
                    Text("These are API acknowledgements, not Apple Maps verification. Gaps over 2.5s indicate delayed updates. A 5-minute request does NOT guarantee 5 minutes of execution; iOS may suspend, expire, or terminate the app earlier.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section("App lifecycle (v0.22)") {
                    LabeledContent("Scene", value: session.lastLifecycleState)
                    LabeledContent("Paused cruise", value: session.pausedCruiseSeconds.map { "\(Int(ceil($0))) seconds remaining" } ?? "None")
                    LabeledContent("Background entries", value: String(session.backgroundTransitions))
                    LabeledContent("Last time away", value: String(format: "%.1f seconds", session.lastAwaySeconds))
                    LabeledContent("Foreground recoveries", value: String(session.foregroundResumeCount))
                    if let when = session.lastMovementCommandAt {
                        LabeledContent("Last accepted command", value: when.formatted(date: .omitted, time: .standard))
                    }
                    Text(session.lastHandoverNote).font(.footnote)
                    LabeledContent("Hypothetical distance while away", value: String(format: "%.1f m (not sent)", session.hypotheticalAwayMeters))
                    Text("Hypothetical distance is an estimate, never transmitted as a catch-up command. During the separately selected experiment, individual GPS updates MAY be attempted in the background. See the background-command counters above.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if let when = session.lastBackgroundAt {
                        LabeledContent("Last backgrounded", value: when.formatted(date: .abbreviated, time: .standard))
                    }
                    if let when = session.lastForegroundAt {
                        LabeledContent("Last foregrounded", value: when.formatted(date: .abbreviated, time: .standard))
                    }
                    ForEach(session.lifecycleEvents.prefix(12), id: \.self) { event in
                        Text(event).font(.caption2).textSelection(.enabled)
                    }
                }
                Section("Coordinates") {
                    LabeledContent("Last requested", value: coordinateText(session.lastRequestedCoordinate))
                    LabeledContent("Last API-accepted", value: coordinateText(session.lastAcceptedCoordinate))
                    LabeledContent("Roam CoreLocation callback", value: coordinateText(session.lastObservedCoordinate))
                    if let when = session.lastObservedAt {
                        LabeledContent("Callback timestamp", value: when.formatted(date: .omitted, time: .standard))
                    }
                    Text("The requested location is not a measurement. An API success means the developer-service call returned successfully; neither it nor Roam's CoreLocation callback proves Apple Maps moved. Check Apple Maps after the 200 m step.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Section("Retained session") {
                    LabeledContent("Location handle", value: LocationEngine.isSessionActive ? "Present (unverified)" : "Absent")
                    LabeledContent("Last engine stage", value: LocationEngine.lastStage)
                    if LocationEngine.lastFailure != "none" {
                        Text(LocationEngine.lastFailure)
                            .font(.caption)
                            .textSelection(.enabled)
                    }
                }
                Section("Recent movements") {
                    if session.movementEvents.isEmpty {
                        Text("No movement commands recorded").foregroundStyle(.secondary)
                    }
                    ForEach(session.movementEvents) { event in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(event.action).font(.subheadline.weight(.semibold))
                                Spacer()
                                Text(event.succeeded ? "API accepted" : "Failed")
                                    .foregroundStyle(event.succeeded ? .green : .red)
                                    .font(.caption)
                            }
                            Text(event.timestamp.formatted(date: .omitted, time: .standard))
                                .font(.caption2).foregroundStyle(.secondary)
                            Text(event.detail).font(.caption).foregroundStyle(.secondary)
                                .textSelection(.enabled)
                        }
                    }
                }
                Section {
                    Button {
                        UIPasteboard.general.string = session.movementDiagnosticReport()
                    } label: {
                        Label("Copy diagnostic report", systemImage: "doc.on.doc")
                    }
                    Button("Clear local diagnostic history", role: .destructive) {
                        session.clearMovementDiagnostics()
                    }
                } footer: {
                    Text("Copying includes coordinates and connection errors. Review the report before sharing. Clearing diagnostics does not end a location session.")
                }
            }
            .navigationTitle("Movement diagnostics")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Minimise") {
                        onMinimise()
                        dismiss()
                    }
                }
            }
        }
    }
}
