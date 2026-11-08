#if os(macOS)
import AppKit
import AVFoundation
import SwiftUI
import WhisperKit

/// Voice notes to the agent, the WhatsApp / Telegram way: hold the mic (or the right ⌥ key) and
/// talk, release to send; slide left to cancel; slide up — or just tap — to keep recording
/// hands-free and send with the button. Speech becomes text on this Mac with Whisper
/// (WhisperKit, large-v3 turbo), biased toward the library's own vocabulary, and goes straight to
/// Claude Code's prompt as a message.
@MainActor
final class VoiceNote: ObservableObject {
    static let shared = VoiceNote()

    enum Phase: Equatable {
        case idle
        case recording
        case transcribing
        case message(String)     // a short notice (no speech, permission, model download…)
    }

    @Published private(set) var phase: Phase = .idle
    /// Recording continues after the press ends; the person sends or cancels with buttons.
    @Published var locked = false
    /// Recent input levels, 0…1, newest last: the waveform.
    @Published private(set) var levels: [Float] = Array(repeating: 0, count: 36)
    @Published private(set) var elapsed: TimeInterval = 0
    /// The loudness now, lightly smoothed: drives the wave and the mic's halo.
    var level: Float { levels.suffix(3).max() ?? 0 }
    /// True until the speech model is downloaded and loaded (the first use downloads ~600 MB).
    @Published private(set) var modelReady = false

    /// Words to bias recognition toward: the open page's title and keywords first, then the
    /// library's titles. Set by the root view, which owns the library index.
    var vocabulary: () -> [String] = { [] }

    static let model = "large-v3-v20240930_626MB"
    /// Kept out of ~/Documents, which may sync to iCloud Drive.
    static var modelFolder: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Wiki LLM/Whisper", isDirectory: true)
    }

    private let engine = AVAudioEngine()
    private let buffer = SampleBuffer()
    private var started: Date?
    private var clock: Timer?
    private var whisper: Task<WhisperKit, Error>?
    private var noticeTask: Task<Void, Never>?

    // MARK: - Speech model

    /// Downloads (first time) and loads Whisper in the background, so the first note is quick.
    func prepare() { _ = loadWhisper() }

    private func loadWhisper() -> Task<WhisperKit, Error> {
        if let whisper { return whisper }
        let task = Task { () throws -> WhisperKit in
            try FileManager.default.createDirectory(at: Self.modelFolder, withIntermediateDirectories: true)
            let config = WhisperKitConfig(model: Self.model, downloadBase: Self.modelFolder,
                                          verbose: false, prewarm: true, load: true, download: true)
            let kit = try await WhisperKit(config)
            await MainActor.run { VoiceNote.shared.modelReady = true }
            return kit
        }
        whisper = task
        return task
    }

    // MARK: - Recording

    func start() {
        guard phase != .recording, phase != .transcribing else { return }
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: break
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                Task { @MainActor in
                    VoiceNote.shared.notice(granted ? "Microphone allowed. Hold the mic again to talk."
                                                    : "Microphone access is off.")
                }
            }
            return
        default:
            notice("Allow the microphone for Wiki LLM in System Settings › Privacy & Security.")
            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")!)
            return
        }
        prepare()
        buffer.reset()
        let input = engine.inputNode
        let inFormat = input.outputFormat(forBus: 0)
        guard inFormat.sampleRate > 0,
              let outFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16_000,
                                            channels: 1, interleaved: false),
              let converter = AVAudioConverter(from: inFormat, to: outFormat)
        else { return notice("No microphone found.") }
        let samples = buffer
        input.installTap(onBus: 0, bufferSize: 4096, format: inFormat) { pcm, _ in
            // Resample to 16 kHz mono, which Whisper expects.
            let ratio = 16_000 / inFormat.sampleRate
            let capacity = AVAudioFrameCount(Double(pcm.frameLength) * ratio) + 64
            guard let out = AVAudioPCMBuffer(pcmFormat: outFormat, frameCapacity: capacity) else { return }
            var fed = false
            var error: NSError?
            converter.convert(to: out, error: &error) { _, status in
                if fed { status.pointee = .noDataNow; return nil }
                fed = true
                status.pointee = .haveData
                return pcm
            }
            guard error == nil, let data = out.floatChannelData?[0] else { return }
            let chunk = Array(UnsafeBufferPointer(start: data, count: Int(out.frameLength)))
            samples.append(chunk)
            let rms = sqrt(chunk.reduce(0) { $0 + $1 * $1 } / Float(max(chunk.count, 1)))
            let level = min(1, rms * 9)
            Task { @MainActor in VoiceNote.shared.push(level: level) }
        }
        do {
            engine.prepare()
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            return notice("Couldn't start the microphone: \(error.localizedDescription)")
        }
        started = Date()
        elapsed = 0
        levels = Array(repeating: 0, count: levels.count)
        clock?.invalidate()
        clock = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
            Task { @MainActor in
                if let s = VoiceNote.shared.started { VoiceNote.shared.elapsed = Date().timeIntervalSince(s) }
            }
        }
        phase = .recording
    }

    /// Ends the recording; sends it to the agent unless `send` is false.
    func stop(send: Bool) {
        guard phase == .recording else { return }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        clock?.invalidate()
        clock = nil
        started = nil
        locked = false
        let audio = buffer.take()
        guard send else { phase = .idle; return }
        guard audio.count > 16_000 / 3 else { return notice("Hold the mic while you talk.") }
        phase = .transcribing
        let words = vocabulary()
        Task {
            do {
                let kit = try await loadWhisper().value
                let text = try await Self.transcribe(audio, with: kit, vocabulary: words)
                if text.isEmpty {
                    notice("I didn't catch any words.")
                } else {
                    AgentPanelModel.shared.submit(text)
                    phase = .idle
                }
            } catch {
                whisper = nil   // try loading again next time
                notice("Speech recognition failed: \(error.localizedDescription)")
            }
        }
    }

    private static func transcribe(_ audio: [Float], with kit: WhisperKit, vocabulary: [String]) async throws -> String {
        // A prompt of the library's terms teaches Whisper their spelling (Galois, Clebsch–Gordan…).
        var options = DecodingOptions(task: .transcribe, language: "en", temperature: 0,
                                      usePrefillPrompt: true, skipSpecialTokens: true,
                                      withoutTimestamps: true)
        if let tokenizer = kit.tokenizer, !vocabulary.isEmpty {
            // WhisperKit keeps only the end of a long prompt, so the most relevant terms (the
            // vocabulary's first ones) go last.
            options.promptTokens = tokenizer.encode(text: " " + vocabulary.reversed().joined(separator: ", ") + ".")
        }
        let results = try await kit.transcribe(audioArray: audio, decodeOptions: options)
        let text = results.map(\.text).joined(separator: " ")
            .replacingOccurrences(of: #"\[(BLANK_AUDIO|MUSIC|NOISE|SILENCE)\]|\((silence|music)\)"#,
                                  with: "", options: [.regularExpression, .caseInsensitive])
        return text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    #if DEBUG
    /// `-debugTranscribe <audio file>`: transcribes a file with the same settings and writes the
    /// text next to it (`<file>.txt`), to check the speech pipeline without a microphone.
    func debugTranscribe(_ path: String) async {
        let out = URL(fileURLWithPath: path + ".txt")
        do {
            let kit = try await loadWhisper().value
            let audio = try AudioProcessor.loadAudioAsFloatArray(fromPath: path)
            let started = Date()
            let text = try await Self.transcribe(audio, with: kit, vocabulary: vocabulary())
            try "\(text)\n[\(String(format: "%.1f", Date().timeIntervalSince(started))) s]\n"
                .write(to: out, atomically: true, encoding: .utf8)
        } catch {
            try? "ERROR \(error)\n".write(to: out, atomically: true, encoding: .utf8)
        }
    }
    #endif

    private func push(level: Float) {
        guard phase == .recording else { return }
        levels.removeFirst()
        levels.append(level)
    }

    private func notice(_ text: String) {
        phase = .message(text)
        noticeTask?.cancel()
        noticeTask = Task {
            try? await Task.sleep(for: .seconds(3.5))
            guard !Task.isCancelled, case .message = phase else { return }
            phase = .idle
        }
    }

    // MARK: - Hold the right ⌥ key to talk, from any app

    private var keyMonitors: [Any] = []
    private var keyDown = false

    /// Right Option alone, held: talk; released: send to Claude. It works in every app (a global
    /// hotkey, so it needs no Fn key and never opens Emoji & Symbols) and brings Wiki LLM forward so
    /// the recording and the answer are on screen. Pressing another key while it's held cancels, so
    /// ⌥ shortcuts and special characters still work.
    func installKeyMonitor() {
        guard keyMonitors.isEmpty else { return }
        if let local = NSEvent.addLocalMonitorForEvents(matching: [.flagsChanged, .keyDown], handler: { event in
            VoiceNote.shared.handleKey(event, global: false)
            return event
        }) { keyMonitors.append(local) }
        // Other apps' key events reach us only with Accessibility access; ask once.
        let promptKey = "voiceNote.askedAccessibility"
        let ask = !UserDefaults.standard.bool(forKey: promptKey)
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: ask] as CFDictionary
        if !AXIsProcessTrustedWithOptions(options) { UserDefaults.standard.set(true, forKey: promptKey) }
        if let global = NSEvent.addGlobalMonitorForEvents(matching: [.flagsChanged, .keyDown], handler: { event in
            Task { @MainActor in VoiceNote.shared.handleKey(event, global: true) }
        }) { keyMonitors.append(global) }
    }

    private func handleKey(_ event: NSEvent, global: Bool) {
        if event.type == .keyDown {
            if keyDown { keyDown = false; stop(send: false) }
            return
        }
        guard event.keyCode == 61 else { return }          // right Option
        let pressed = event.modifierFlags.contains(.option)
        let free: Bool = { if case .message = phase { return true }; return phase == .idle }()
        if pressed, !keyDown, free {
            keyDown = true
            if global {
                UserDefaults.standard.set(true, forKey: "agentPanelVisible")
                NSApp.activate(ignoringOtherApps: true)
            }
            start()
        } else if !pressed, keyDown {
            keyDown = false
            if !locked { stop(send: true) }
        }
    }
}

/// Audio samples gathered on the audio thread.
private final class SampleBuffer: @unchecked Sendable {
    private var samples: [Float] = []
    private let lock = NSLock()
    func reset() { lock.lock(); samples.removeAll(keepingCapacity: true); lock.unlock() }
    func append(_ chunk: [Float]) { lock.lock(); samples.append(contentsOf: chunk); lock.unlock() }
    func take() -> [Float] { lock.lock(); defer { samples = []; lock.unlock() }; return samples }
}

// MARK: - The bar under the agent's terminal

/// WhatsApp-style composer in LahLah Voice's white pill, sitting under Claude's terminal: a
/// ringed mic to hold on the left, a live waveform, and Send.
struct VoiceNoteBar: View {
    @ObservedObject private var note = VoiceNote.shared
    @State private var pressStart: Date?
    @State private var drag: CGSize = .zero
    @State private var cancelled = false
    @State private var hovering = false

    private let cancelDistance: CGFloat = 90
    private let lockDistance: CGFloat = 50
    private let micSize: CGFloat = 36

    var body: some View {
        HStack(spacing: 10) {
            switch note.phase {
            case .recording:
                if note.locked { lockedControls } else { holdingControls }
            case .transcribing:
                ProgressView().controlSize(.small).frame(width: micSize, height: micSize)
                Text(note.modelReady ? "Turning your voice into text…"
                                     : "Getting the speech model ready (first time downloads about 600 MB)…")
                    .font(.callout.weight(.medium)).lineLimit(1)
                Spacer(minLength: 0)
            case .message(let text):
                micButton
                Image(systemName: "info.circle").foregroundStyle(.secondary)
                Text(text).font(.callout).foregroundStyle(.secondary).lineLimit(2)
                Spacer(minLength: 0)
            case .idle:
                micButton
                VoiceWave(level: 0.3, barCount: 11, maxHeight: 18, animated: false)
                Text("Hold to talk to Claude · or right ⌥ · tap for hands-free")
                    .font(.callout).foregroundStyle(.secondary).lineLimit(1)
                Spacer(minLength: 0)
            }
        }
        .padding(.leading, 6)
        .padding(.trailing, 8)
        .frame(height: 48)
        .background(Capsule().fill(Color.white))
        .overlay(Capsule().strokeBorder(Color.black.opacity(0.08)))
        .shadow(color: .black.opacity(0.25), radius: 8, y: 2)
        .foregroundStyle(Color.black.opacity(0.85))
        .environment(\.colorScheme, .light)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color.black)
        .onAppear {
            note.installKeyMonitor()
            note.prepare()
        }
    }

    // Holding: mic, timer, waveform and "slide to cancel"; the lock hint sits above the mic.
    private var holdingControls: some View {
        Group {
            micButton
                .overlay(alignment: .top) {
                    Image(systemName: "lock.fill").font(.system(size: 9)).foregroundStyle(.secondary)
                        .opacity(drag.height < -10 ? 1 : 0.5)
                        .offset(y: -12)
                }
            recordingDot
            Text(timeText).font(.callout.monospacedDigit().weight(.medium))
            VoiceWave(level: note.level, maxHeight: 28)
            Text(cancelled ? "Release to cancel" : "‹ Slide to cancel")
                .font(.callout).foregroundStyle(cancelled ? .red : .secondary)
                .lineLimit(1)
                .offset(x: max(-60, min(0, drag.width / 2)))
            Spacer(minLength: 0)
        }
    }

    // Hands-free: delete, timer + waveform, and Send.
    private var lockedControls: some View {
        Group {
            Button { note.stop(send: false) } label: {
                Image(systemName: "trash").font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.red)
                    .frame(width: micSize, height: micSize)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .help("Discard this voice note")
            recordingDot
            Text(timeText).font(.callout.monospacedDigit().weight(.medium))
            VoiceWave(level: note.level, maxHeight: 28)
            Spacer(minLength: 4)
            Button { note.stop(send: true) } label: {
                Label("Send", systemImage: "arrow.up")
                    .font(.callout.weight(.semibold))
                    .labelStyle(.titleAndIcon)
                    .padding(.horizontal, 14)
                    .frame(height: 32)
                    .foregroundStyle(Theme.onAccent)
                    .background(Capsule().fill(Theme.accent))
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.return, modifiers: [])
            .help("Send to Claude (Return)")
        }
    }

    private var recordingDot: some View {
        Circle().fill(Color.red).frame(width: 8, height: 8)
            .opacity(Int(note.elapsed * 2) % 2 == 0 ? 1 : 0.35)
            .accessibilityLabel("Recording")
    }

    private var timeText: String {
        let s = Int(note.elapsed)
        return String(format: "%d:%02d", s / 60, s % 60)
    }

    /// LahLah's mark: a white disc with an accent ring. It fills with the accent while recording
    /// and a halo follows the voice.
    private var micButton: some View {
        let recording = note.phase == .recording
        return Image(systemName: recording ? "mic.fill" : "mic")
            .font(.system(size: micSize * 0.44, weight: .semibold))
            .foregroundStyle(recording ? Theme.onAccent : Theme.accent)
            .frame(width: micSize, height: micSize)
            .background(Circle().fill(recording ? Theme.accent : (hovering ? Theme.accent.opacity(0.12) : Color.white)))
            .overlay(Circle().strokeBorder(Theme.accent, lineWidth: 2.5))
            .background(
                Circle()
                    .fill(Theme.accent.opacity(recording ? 0.25 : 0))
                    .scaleEffect(recording ? 1.1 + CGFloat(note.level) * 0.35 : 1)
            )
            .animation(.easeOut(duration: 0.12), value: note.level)
            .animation(.easeOut(duration: 0.15), value: note.phase)
            .animation(.easeOut(duration: 0.15), value: hovering)
            .padding(3)                     // a slightly larger click target than the disc
            .contentShape(Circle())
            .onHover { hovering = $0 }
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        if pressStart == nil {
                            pressStart = Date()
                            cancelled = false
                            if note.phase != .recording { note.start() }
                        }
                        drag = value.translation
                        guard note.phase == .recording, !note.locked else { return }
                        cancelled = value.translation.width < -cancelDistance
                        if value.translation.height < -lockDistance { note.locked = true }
                    }
                    .onEnded { _ in
                        let held = pressStart.map { Date().timeIntervalSince($0) } ?? 0
                        pressStart = nil
                        drag = .zero
                        guard note.phase == .recording, !note.locked else { return }
                        if cancelled {
                            note.stop(send: false)
                        } else if held < 0.35 {
                            note.locked = true          // a tap: keep recording hands-free
                        } else {
                            note.stop(send: true)       // released: send
                        }
                        cancelled = false
                    }
            )
            .help("Hold to talk, release to send. Slide left to cancel, up to lock. Tap for hands-free.")
            .accessibilityLabel("Voice note to Claude")
            .accessibilityAddTraits(.isButton)
    }
}

/// LahLah Voice's wave: a symmetric row of bars that swells with the voice and ripples while
/// it listens. Every fourth bar is in the accent colour.
private struct VoiceWave: View {
    var level: Float
    var barCount = 27
    var maxHeight: CGFloat = 34
    var animated = true

    var body: some View {
        if animated {
            TimelineView(.animation(minimumInterval: 1 / 30)) { context in
                bars(context.date.timeIntervalSinceReferenceDate)
            }
        } else {
            bars(0)
        }
    }

    private func bars(_ time: Double) -> some View {
        HStack(spacing: 4) {
            ForEach(0..<barCount, id: \.self) { index in
                Capsule()
                    .fill(index % 4 == 0 ? Theme.accent : Color.black.opacity(0.8))
                    .frame(width: 3.5, height: height(index, time))
            }
        }
        .frame(height: maxHeight)
        .accessibilityHidden(true)
    }

    private func height(_ index: Int, _ time: Double) -> CGFloat {
        let position = Double(index) / Double(max(barCount - 1, 1))
        let shape = pow(abs(sin(position * .pi * 2)), 1.4)
        let loudness = min(1, Double(level) * 1.6)
        let ripple = 0.72 + 0.28 * sin(time * 7 + Double(index) * 0.9)
        return 5 + (maxHeight - 5) * CGFloat(shape * (0.18 + 0.82 * loudness) * ripple)
    }
}
#endif
