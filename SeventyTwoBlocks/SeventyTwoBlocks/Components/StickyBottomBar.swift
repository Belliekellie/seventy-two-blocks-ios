import SwiftUI
import AVFoundation

struct StickyBottomBar: View {
    @EnvironmentObject var blockManager: BlockManager
    @Binding var showOverview: Bool
    @StateObject private var soundManager = FocusSoundManager.shared

    // Settings storage
    @AppStorage("preferredFocusSound") private var preferredFocusSound = "rain"
    @AppStorage("focusSoundVolume") private var focusSoundVolume = 0.5

    @State private var showSoundPicker = false

    // Worked time
    private var totalWorkedSeconds: Int {
        blockManager.blocks.reduce(0) { total, block in
            guard block.status == .done else { return total }
            let workSeconds = block.segments
                .filter { $0.type == .work }
                .reduce(0) { $0 + $1.seconds }
            return total + (workSeconds >= 19 * 60 ? 20 * 60 : workSeconds)
        }
    }

    private var workedTimeString: String {
        if totalWorkedSeconds == 0 { return "0m" }
        if totalWorkedSeconds < 30 { return "<1m" }
        let totalMinutes = (totalWorkedSeconds + 30) / 60
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        return hours > 0 ? "\(hours)h \(minutes)m" : "\(minutes)m"
    }

    var body: some View {
        VStack(spacing: 0) {
            Divider()

            GeometryReader { geo in
                let columnWidth = (geo.size.width - 40) / 3 // 40 = horizontal padding (20 * 2)

                HStack(spacing: 0) {
                    // Focus Sounds (left)
                    VStack(spacing: 4) {
                        HStack(spacing: 4) {
                            Button {
                                if soundManager.isPlaying {
                                    soundManager.stop()
                                } else {
                                    soundManager.currentSound = preferredFocusSound
                                    soundManager.setVolume(Float(focusSoundVolume))
                                    soundManager.play()
                                }
                            } label: {
                                Image(systemName: soundManager.isPlaying ? "speaker.wave.2.fill" : soundManager.soundIcon(for: preferredFocusSound))
                                    .font(.subheadline)
                                    .foregroundStyle(soundManager.isPlaying ? .blue : .secondary)
                                    .frame(height: 22)
                            }
                            .buttonStyle(.plain)

                            Button {
                                showSoundPicker = true
                            } label: {
                                HStack(spacing: 4) {
                                    Text(soundManager.shortSoundName(for: preferredFocusSound))
                                        .font(.subheadline.weight(.semibold))
                                        .lineLimit(1)
                                    Image(systemName: "chevron.up")
                                        .font(.system(size: 8, weight: .semibold))
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                        .frame(height: 22)
                        Text("Focus Sounds")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(width: columnWidth)

                    Divider()
                        .frame(height: 36)

                    // Overview (center)
                    Button {
                        showOverview = true
                    } label: {
                        VStack(spacing: 4) {
                            Image(systemName: "chart.bar.fill")
                                .font(.subheadline)
                                .foregroundStyle(.purple)
                                .frame(height: 22)
                            Text("Overview")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .frame(width: columnWidth)
                    }
                    .buttonStyle(.plain)

                    Divider()
                        .frame(height: 36)

                    // Worked time (right)
                    VStack(spacing: 4) {
                        HStack(spacing: 4) {
                            Image(systemName: "clock.fill")
                                .font(.subheadline)
                                .foregroundStyle(.blue)
                            Text(workedTimeString)
                                .font(.subheadline.weight(.semibold))
                        }
                        .frame(height: 22)
                        Text("Worked")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(width: columnWidth)
                }
                .frame(maxWidth: .infinity)
            }
            .frame(height: 42)
            .padding(.top, 14)
            .padding(.bottom, 6)
            .padding(.horizontal, 20)
            .background(Color(.systemBackground))
        }
        .sheet(isPresented: $showSoundPicker) {
            FocusSoundPickerSheet(
                selectedSound: $preferredFocusSound,
                volume: $focusSoundVolume
            )
            .presentationDetents([.medium])
        }
        .onChange(of: preferredFocusSound) { _, newSound in
            if soundManager.isPlaying {
                soundManager.changeSound(newSound)
            }
        }
        .onChange(of: focusSoundVolume) { _, newVolume in
            soundManager.setVolume(Float(newVolume))
        }
    }
}

// MARK: - Focus Sound Picker Sheet

struct FocusSoundPickerSheet: View {
    @Binding var selectedSound: String
    @Binding var volume: Double
    @StateObject private var soundManager = FocusSoundManager.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                if soundManager.isPlaying {
                    HStack {
                        Image(systemName: "waveform")
                            .foregroundStyle(.blue)
                            .symbolEffect(.variableColor.iterative)
                        Text("Now Playing")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.blue)
                    }
                    .padding(.top)
                }

                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 3), spacing: 12) {
                    ForEach(FocusSoundManager.availableSounds, id: \.id) { sound in
                        let isCurrentlyPlaying = soundManager.isPlaying && soundManager.currentSound == sound.id
                        Button {
                            if isCurrentlyPlaying {
                                // Tapping the playing sound stops it
                                soundManager.stop()
                            } else {
                                // Select and play this sound
                                selectedSound = sound.id
                                soundManager.setVolume(Float(volume))
                                soundManager.play(sound: sound.id)
                            }
                            AudioManager.shared.triggerHapticFeedback(.light)
                        } label: {
                            VStack(spacing: 8) {
                                ZStack {
                                    Circle()
                                        .fill(isCurrentlyPlaying ? Color.blue : (selectedSound == sound.id ? Color.blue.opacity(0.3) : Color.gray.opacity(0.15)))
                                        .frame(width: 50, height: 50)

                                    if isCurrentlyPlaying {
                                        Image(systemName: "stop.fill")
                                            .font(.title3)
                                            .foregroundStyle(.white)
                                    } else {
                                        Image(systemName: sound.icon)
                                            .font(.title3)
                                            .foregroundStyle(selectedSound == sound.id ? .blue : .primary)
                                    }
                                }

                                Text(sound.name)
                                    .font(.caption)
                                    .foregroundStyle(isCurrentlyPlaying ? .blue : (selectedSound == sound.id ? .primary : .secondary))

                                if sound.isGenerated {
                                    Text("Generated")
                                        .font(.system(size: 8))
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal)
                .padding(.top, soundManager.isPlaying ? 0 : 12)

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Volume")
                            .font(.subheadline.weight(.medium))
                        Spacer()
                        Text("\(Int(volume * 100))%")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    HStack(spacing: 12) {
                        Image(systemName: "speaker.fill")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Slider(value: $volume, in: 0...1, step: 0.1)

                        Image(systemName: "speaker.wave.3.fill")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal)
                .padding(.top, 8)

                Spacer()
            }
            .navigationTitle("Focus Sounds")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

#Preview {
    VStack {
        Spacer()
        StickyBottomBar(showOverview: .constant(false))
            .environmentObject(BlockManager())
    }
}
