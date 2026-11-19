#if DEBUG
import SwiftUI
#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif

/// Runs the probe's steps strictly one at a time, a second apart, only when
/// the user taps Run. 16 requests at most; see `ProbePlan`.
@MainActor
@Observable
final class NetworkProbeRunner {
    struct Track: Equatable {
        var trackId: String
        var showId: String?
        var title: String
        var artist: String
    }

    private(set) var results: [ProbeResult] = []
    private(set) var isRunning = false
    private(set) var activeStep: ProbeStep?
    private(set) var completed = 0
    private(set) var cdnTarget: ProbeResult?
    /// Set when the CDN group was skipped or the run stopped early.
    private(set) var note: String?
    private(set) var probedTrack: Track?
    private(set) var finishedAt: Date?

    let honest = NugsIdentity.honestForThisBuild
    let total = ProbePlan.allSteps().count

    @ObservationIgnored private var task: Task<Void, Never>?

    func result(for step: ProbeStep) -> ProbeResult? {
        results.first { $0.step == step }
    }

    func run(client: NugsClient, track: Track) {
        guard !isRunning else { return }
        results = []
        cdnTarget = nil
        note = nil
        completed = 0
        finishedAt = nil
        probedTrack = track
        isRunning = true
        let honest = honest
        task = Task { [weak self] in
            await self?.perform(client: client, track: track, honest: honest)
            self?.isRunning = false
            self?.activeStep = nil
            self?.finishedAt = Date()
        }
    }

    func cancel() {
        task?.cancel()
        task = nil
    }

    private func perform(client: NugsClient, track: Track, honest: NugsIdentity) async {
        var first = true
        /// The polite pause: nothing goes out less than a second after the
        /// previous request finished. False once the run is cancelled.
        func pace() async -> Bool {
            if !first { try? await Task.sleep(for: .seconds(1)) }
            first = false
            return !Task.isCancelled
        }
        do {
            for step in ProbePlan.apiSteps {
                if case .catalog = step, track.showId == nil {
                    // No request goes out, so no pause either.
                    record(ProbeParse.failure(step: step, error: "Current track has no show ID"))
                    continue
                }
                guard await pace() else { return stopped() }
                activeStep = step
                let identity = step.identity(honest: honest)
                if case .catalog = step, let showId = track.showId {
                    record(try await client.probeCatalog(step: step, showId: showId,
                                                         trackId: track.trackId, identity: identity))
                } else {
                    record(try await client.probeSubscriptions(step: step, identity: identity))
                }
            }
            for step in ProbePlan.resolveSteps() {
                guard await pace() else { return stopped() }
                guard case .resolve(_, let tier) = step else { continue }
                activeStep = step
                record(try await client.probeResolve(step: step, trackId: track.trackId,
                                                     platformId: tier,
                                                     identity: step.identity(honest: honest)))
            }
        } catch {
            note = "Stopped: \(error.localizedDescription)"
            return
        }
        guard let target = ProbePlan.cdnTarget(from: results), let url = target.streamURL else {
            note = "CDN checks skipped — no resolve returned a stream URL."
            return
        }
        cdnTarget = target
        for step in ProbePlan.cdnSteps {
            guard await pace() else { return stopped() }
            activeStep = step
            record(await client.probeCDN(step: step, url: url, identity: step.identity(honest: honest)))
        }
    }

    private func record(_ result: ProbeResult) {
        results.append(result)
        completed += 1
    }

    private func stopped() {
        note = "Stopped before finishing."
    }

    func reportText(platform: String) -> String {
        guard let track = probedTrack else { return "" }
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString")
            as? String ?? "?"
        let header = ProbeReport.Header(
            date: finishedAt ?? Date(), appVersion: version, platform: platform,
            trackTitle: track.title, trackArtist: track.artist, trackId: track.trackId,
            showId: track.showId, honest: honest)
        return ProbeReport.text(header: header, results: results, cdnTarget: cdnTarget, note: note)
    }
}

/// DEBUG-only diagnostics: for the current track, what nugs.net answers to the
/// honest identity versus the legacy Android one. Reached from the account menu
/// ("Network Probe (Debug)") on both platforms; `-UITestShowNetworkProbe`
/// presents it at launch for screenshots. Shared by the iOS and macOS shells,
/// so nothing here may come from `AppleNugs/macOS/` or `AppleNugs/iOS/`.
struct NetworkProbeView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var runner = NetworkProbeRunner()
    @State private var copied = false
    @State private var vitals: Vitals?
    @Environment(\.scenePhase) private var scenePhase

    /// One reading of the memory block: kernel footprint numbers plus the
    /// player's background-tick counters.
    private struct Vitals {
        var memory: MemoryFootprint?
        var backgroundTicks: Int
        var backgroundEntries: Int

        @MainActor init(player: PlayerService) {
            memory = MemoryFootprint.sample()
            backgroundTicks = player.debugBackgroundTicks
            backgroundEntries = player.debugBackgroundEntries
        }
    }

    private var platform: String {
        #if os(iOS)
        let os = "iOS"
        #else
        let os = "macOS"
        #endif
        return NugsIdentity.platformDescription(
            os: os, version: ProcessInfo.processInfo.operatingSystemVersion)
    }

    /// The now-playing track, as the probe would use it.
    private var track: NetworkProbeRunner.Track? {
        guard let t = app.player.current else { return nil }
        return .init(trackId: t.trackId, showId: t.showId, title: t.title ?? "Untitled",
                     artist: t.artist ?? "Unknown artist")
    }

    /// A seeded UI-test launch has stub tracks but a live session store, so a
    /// Run there would ask nugs about a track id that doesn't exist.
    private var runBlockedReason: String? {
        if AppModel.isUITestRun { return "Run is disabled in UI-test launches." }
        if track == nil { return "Play something first." }
        return nil
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    memoryBlock
                    trackBlock
                    identityBlock
                    controls
                    ForEach(ProbeGroup.allCases, id: \.self) { group in
                        groupBlock(group)
                    }
                }
                .padding(20)
                .frame(maxWidth: 720, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
            .navigationTitle("Network Probe")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 600, minHeight: 680)
        #endif
        .onDisappear { runner.cancel() }
        // Every 2 s while the sheet is up — and not while the app is in the
        // background, so the readout never becomes a background wake-up itself.
        // The peak needs no polling: it's the kernel's own high-water mark.
        .task(id: scenePhase) {
            guard scenePhase != .background else { return }
            while !Task.isCancelled {
                vitals = Vitals(player: app.player)
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }

    // MARK: - Blocks

    private var memoryBlock: some View {
        let memory = vitals?.memory
        let format = { (bytes: UInt64?) in bytes.map(MemoryFootprint.format(bytes:)) ?? "—" }
        return VStack(alignment: .leading, spacing: 6) {
            caption("Memory")
            memoryLine("Footprint", format(memory?.current))
            memoryLine("Peak", format(memory?.peak) + "  since launch")
            memoryLine("Headroom", memory?.limitRemaining.map {
                MemoryFootprint.format(bytes: $0) + "  before jetsam"
            } ?? "no limit reported")
            memoryLine("BG ticks", vitals.map {
                "\($0.backgroundTicks) in \($0.backgroundEntries) background "
                    + ($0.backgroundEntries == 1 ? "period" : "periods")
            } ?? "—")
        }
    }

    private func memoryLine(_ name: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(name)
                .font(.caption.weight(.semibold))
                .frame(width: 72, alignment: .leading)
            Text(value)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
        }
    }

    private var trackBlock: some View {
        VStack(alignment: .leading, spacing: 4) {
            caption("Track")
            if let track = runner.probedTrack ?? track {
                Text(track.title).font(.headline)
                Text("\(track.artist) · trackID \(track.trackId) · show \(track.showId ?? "none")")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                Text("Play something first").font(.headline)
                Text("The probe resolves the current track.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var identityBlock: some View {
        VStack(alignment: .leading, spacing: 6) {
            caption("Identities")
            identityLine("Yeti", runner.honest.userAgentAPI)
            identityLine("Android", NugsIdentity.legacyAndroidForProbe.userAgentAPI)
            identityLine("Resolve", NugsIdentity.legacyAndroidForProbe.userAgentLegacy)
            identityLine("Referer", NugsIdentity.legacyAndroidForProbe.refererCDN ?? "none")
        }
    }

    private func identityLine(_ name: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(name)
                .font(.caption.weight(.semibold))
                .frame(width: 58, alignment: .leading)
            Text(value)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Button {
                    if let track { runner.run(client: app.client, track: track) }
                } label: {
                    Label("Run", systemImage: "play.fill")
                }
                .buttonStyle(.borderedProminent)
                .disabled(runner.isRunning || runBlockedReason != nil)

                Button {
                    // Memory first, sampled now, so a copy made after a long
                    // background session carries the numbers that matter even
                    // without a network run.
                    let network = runner.reportText(platform: platform)
                    copy(memoryReportText() + (network.isEmpty ? "" : "\n\n" + network))
                    copied = true
                } label: {
                    Label(copied ? "Copied" : "Copy results", systemImage: "doc.on.doc")
                }
                .buttonStyle(.bordered)
                .disabled(runner.isRunning)
            }
            if runner.isRunning {
                ProgressView(value: Double(runner.completed), total: Double(runner.total)) {
                    Text("Step \(min(runner.completed + 1, runner.total)) of \(runner.total)"
                         + (runner.activeStep.map { " — \($0.label)" } ?? ""))
                        .font(.caption)
                }
            } else if let reason = runBlockedReason {
                Text(reason).font(.caption).foregroundStyle(.secondary)
            } else {
                Text("\(runner.total) requests, one at a time, a second apart.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if let note = runner.note {
                Text(note).font(.caption).foregroundStyle(.orange)
            }
        }
        .onChange(of: runner.isRunning) { _, running in
            if running { copied = false }
        }
    }

    private func groupBlock(_ group: ProbeGroup) -> some View {
        let steps = ProbePlan.allSteps().filter { $0.group == group }
        return VStack(alignment: .leading, spacing: 0) {
            caption(group.title).padding(.bottom, 6)
            if group == .cdn, let target = runner.cdnTarget, let format = target.format {
                Text("Fetching \(format.qualityLabel) from \(target.step.label)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 6)
            }
            ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                if index > 0 { Divider() }
                row(step)
            }
        }
        .padding(12)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
    }

    private func row(_ step: ProbeStep) -> some View {
        let result = runner.result(for: step)
        let isActive = runner.activeStep == step && runner.isRunning
        return HStack(alignment: .firstTextBaseline, spacing: 10) {
            Group {
                if let result {
                    Image(systemName: result.ok ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundStyle(result.ok ? .green : .red)
                } else {
                    Image(systemName: isActive ? "circle.dotted" : "circle")
                        .foregroundStyle(.tertiary)
                }
            }
            .font(.body)
            VStack(alignment: .leading, spacing: 2) {
                Text(step.label).font(.subheadline.weight(.medium))
                Text(result?.summary ?? (isActive ? "Requesting…" : "Not run"))
                    .font(.caption)
                    .foregroundStyle(result == nil ? HierarchicalShapeStyle.tertiary : .secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            Text(result?.statusText ?? "")
                .font(.system(.subheadline, design: .monospaced).weight(.semibold))
                .foregroundStyle(result.map { $0.ok ? Color.primary : Color.red } ?? .secondary)
        }
        .padding(.vertical, 7)
    }

    private func caption(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
    }

    /// The Memory block as plain text, from a fresh sample.
    private func memoryReportText() -> String {
        let v = Vitals(player: app.player)
        let format = { (bytes: UInt64?) in bytes.map(MemoryFootprint.format(bytes:)) ?? "—" }
        let headroom = v.memory?.limitRemaining.map {
            MemoryFootprint.format(bytes: $0) + " before jetsam"
        } ?? "no limit reported"
        return """
        [Memory — \(platform)]
        Footprint: \(format(v.memory?.current))
        Peak since launch: \(format(v.memory?.peak))
        Headroom: \(headroom)
        BG ticks: \(v.backgroundTicks) in \(v.backgroundEntries) background \(v.backgroundEntries == 1 ? "period" : "periods")
        """
    }

    private func copy(_ text: String) {
        #if canImport(UIKit)
        UIPasteboard.general.string = text
        #else
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        #endif
    }
}
#endif
