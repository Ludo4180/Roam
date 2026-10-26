import SwiftUI
import NetworkExtension

// Roam v0.5: a branded interface over the original, unchanged GPS engine.
struct RootView: View {
    @EnvironmentObject private var session: SpoofSession
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
        if !tunnelConnected { return "LocalDevVPN not detected — tap to open" }
        if isActive { return "Virtual movement enabled while the session remains active" }
        return "VPN detected • developer tunnel not verified"
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

    private var speedCaption: String {
        String(format: "%.0f km/h preset", session.travelMode.baseSpeed * 3.6)
    }

    var body: some View {
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
                    JoystickPad { vector in session.updateJoystick(vector: vector) }
                        .frame(width: 150, height: 150)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                }
                .padding(13)
                .roamSurface(cornerRadius: 22)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            VStack(alignment: .leading, spacing: 13) {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("MOVEMENT MODE")
                            .font(.system(size: 10, weight: .bold))
                            .tracking(2)
                            .foregroundStyle(RoamPalette.muted)
                        Text("Choose your pace")
                            .font(.system(size: 16, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white)
                    }
                    Spacer()
                    Text(speedCaption)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(RoamPalette.turquoise)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(RoamPalette.turquoise.opacity(0.11), in: Capsule())
                }

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

                    if session.isSpoofing {
                        Button {
                            session.stop(pairing: pairing)
                        } label: {
                            Label("Stop", systemImage: "stop.fill")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(.white)
                                .frame(minWidth: 98, minHeight: 46)
                                .background(Capsule().fill(LocusTheme.danger))
                        }
                        .buttonStyle(.plain)
                    } else {
                        Button {
                            guard let pin = session.pin else {
                                session.lastError = "Choose a destination on the map first."
                                return
                            }
                            session.teleport(to: pin, pairing: pairing)
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "location.north.fill")
                                    .font(.system(size: 12))
                                Text("Teleport")
                            }
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(RoamPalette.background)
                            .frame(minWidth: 106, minHeight: 46)
                            .background(RoamPalette.primaryGradient, in: Capsule())
                            .shadow(color: RoamPalette.electricBlue.opacity(0.26), radius: 8, y: 4)
                        }
                        .buttonStyle(.plain)
                        .disabled(session.isBusy)
                        .opacity(session.isBusy ? 0.65 : 1)
                    }
                }
            }
            .padding(15)
            .roamSurface(cornerRadius: 25)
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
