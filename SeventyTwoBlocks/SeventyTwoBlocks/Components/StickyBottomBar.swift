import SwiftUI
import AVFoundation

struct StickyBottomBar: View {
    @EnvironmentObject var blockManager: BlockManager
    @StateObject private var soundManager = FocusSoundManager.shared

    // Settings storage
    @AppStorage("preferredFocusSound") private var preferredFocusSound = "rain"
    @AppStorage("focusSoundVolume") private var focusSoundVolume = 0.5

    @State private var showSoundPicker = false

    // Progress calculations
    private var doneBlocks: Int {
        blockManager.blocks.filter { $0.status == .done }.count
    }

    private var currentSetProgress: Int {
        doneBlocks % 12
    }

    private var completedSets: Int {
        doneBlocks / 12
    }

    var body: some View {
        VStack(spacing: 0) {
            Divider()

            HStack(spacing: 12) {
                // Completed Blocks
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text("Completed Blocks")
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.secondary)

                        Text("\(currentSetProgress)/12")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.primary)

                        if completedSets > 0 {
                            Text("• \(completedSets) set\(completedSets == 1 ? "" : "s") done")
                                .font(.caption2)
                                .foregroundStyle(.green)
                        }
                    }

                    // Progress bar
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 3)
                                .fill(Color.gray.opacity(0.2))
                                .frame(height: 6)

                            RoundedRectangle(cornerRadius: 3)
                                .fill(
                                    LinearGradient(
                                        colors: [.green, .blue],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .frame(width: geo.size.width * CGFloat(currentSetProgress) / 12, height: 6)
                        }
                    }
                    .frame(height: 6)
                }
                .frame(maxWidth: .infinity)

                // Focus Sound Controls
                HStack(spacing: 8) {
                    // Play/Stop toggle button
                    Button {
                        if soundManager.isPlaying {
                            soundManager.stop()
                        } else {
                            soundManager.currentSound = preferredFocusSound
                            soundManager.setVolume(Float(focusSoundVolume))
                            soundManager.play()
                        }
                    } label: {
                        Image(systemName: soundManager.isPlaying ? "stop.fill" : "play.fill")
                            .font(.caption)
                            .foregroundStyle(soundManager.isPlaying ? .red : .green)
                            .frame(width: 28, height: 28)
                            .background(Color.gray.opacity(0.15))
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                    }
                    .buttonStyle(.plain)

                    // Sound picker button
                    Button {
                        showSoundPicker = true
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: soundManager.soundIcon(for: preferredFocusSound))
                                .font(.caption)
                                .foregroundStyle(soundManager.isPlaying ? .blue : .secondary)

                            Text(soundManager.soundName(for: preferredFocusSound))
                                .font(.caption2.weight(.medium))
                                .foregroundStyle(soundManager.isPlaying ? .primary : .secondary)
                                .lineLimit(1)

                            Image(systemName: "chevron.up")
                                .font(.system(size: 7, weight: .semibold))
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                        .background(Color.gray.opacity(0.15))
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 24)  // Align with card content
            .padding(.vertical, 10)
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
                // Now Playing indicator
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

                // Sound selection grid
                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 3), spacing: 12) {
                    ForEach(FocusSoundManager.availableSounds, id: \.id) { sound in
                        Button {
                            selectedSound = sound.id
                            if soundManager.isPlaying {
                                soundManager.changeSound(sound.id)
                            }
                            AudioManager.shared.triggerHapticFeedback(.light)
                        } label: {
                            VStack(spacing: 8) {
                                ZStack {
                                    Circle()
                                        .fill(selectedSound == sound.id ? Color.blue : Color.gray.opacity(0.15))
                                        .frame(width: 50, height: 50)

                                    Image(systemName: sound.icon)
                                        .font(.title3)
                                        .foregroundStyle(selectedSound == sound.id ? .white : .primary)
                                }

                                Text(sound.name)
                                    .font(.caption)
                                    .foregroundStyle(selectedSound == sound.id ? .primary : .secondary)

                                // Show "Generated" badge for noise types
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

                // Volume slider
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

                // Play/Stop button
                Button {
                    if soundManager.isPlaying {
                        soundManager.stop()
                    } else {
                        soundManager.currentSound = selectedSound
                        soundManager.setVolume(Float(volume))
                        soundManager.play()
                    }
                } label: {
                    HStack {
                        Image(systemName: soundManager.isPlaying ? "stop.fill" : "play.fill")
                        Text(soundManager.isPlaying ? "Stop Sound" : "Play Sound")
                    }
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(soundManager.isPlaying ? Color.red : Color.blue)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
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
        StickyBottomBar()
            .environmentObject(BlockManager())
    }
}
