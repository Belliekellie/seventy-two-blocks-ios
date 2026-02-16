import SwiftUI
import Auth

struct SettingsView: View {
    @EnvironmentObject var authManager: AuthManager
    @EnvironmentObject var blockManager: BlockManager
    @EnvironmentObject var timerManager: TimerManager
    @Environment(\.dismiss) private var dismiss

    // Reset Day confirmation
    @State private var showResetConfirmation = false

    // Appearance (1 = light, 2 = dark) - matches CompactHeaderView and App
    @AppStorage("appearanceMode") private var appearanceMode: Int = 2

    // Day Settings
    @AppStorage("dayStartHour") private var dayStartHour = 6
    @AppStorage("pendingDayStartHour") private var pendingDayStartHour: Int = -1  // -1 means no pending change
    @AppStorage("pendingDayStartDateString") private var pendingDayStartDateString: String = ""

    @State private var showDayStartPreview = false

    // Timer Settings
    @AppStorage("disableAutoContinue") private var disableAutoContinue = false
    @AppStorage("blocksUntilCheckIn") private var blocksUntilCheckIn = 3
    @AppStorage("playSoundsInSilentMode") private var playSoundsInSilentMode = false

    // Skipped Block Style (motivational insults)
    @AppStorage("showMotivationalInsults") private var showMotivationalInsults = false

    // Custom Segment Names
    @AppStorage("segmentNameMorning") private var segmentNameMorning = "Morning"
    @AppStorage("segmentNameAfternoon") private var segmentNameAfternoon = "Afternoon & Evening"
    @AppStorage("segmentNameNight") private var segmentNameNight = "Night"

    // Focus Sounds
    @AppStorage("focusSoundEnabled") private var focusSoundEnabled = false
    @AppStorage("preferredFocusSound") private var preferredFocusSound = "rain"
    @AppStorage("focusSoundVolume") private var focusSoundVolume = 0.5

    // Favorite Labels

    var body: some View {
        NavigationStack {
            Form {
                // Account section
                Section("Account") {
                    if let user = authManager.currentUser {
                        HStack {
                            Text("Email")
                            Spacer()
                            Text(user.email ?? "No email")
                                .foregroundStyle(.secondary)
                        }
                    }

                    Button(role: .destructive) {
                        Task {
                            await authManager.signOut()
                            dismiss()
                        }
                    } label: {
                        Text("Sign Out")
                    }
                }

                // Appearance
                Section {
                    HStack {
                        Text(appearanceMode == 2 ? "🌙" : "☀️")
                        Picker("Theme", selection: $appearanceMode) {
                            Text("Light").tag(1)
                            Text("Dark").tag(2)
                        }
                        .pickerStyle(.segmented)
                    }
                } header: {
                    Text("Appearance")
                }

                // Day Settings
                Section {
                    // Day start hour picker with pending change logic
                    DayStartHourPicker(
                        dayStartHour: $dayStartHour,
                        pendingDayStartHour: $pendingDayStartHour,
                        pendingDayStartDateString: $pendingDayStartDateString,
                        showPreview: $showDayStartPreview
                    )
                } header: {
                    Text("Day Settings")
                } footer: {
                    if pendingDayStartHour >= 0 {
                        Text("Change will take effect at \(pendingDayStartHour):00 AM on \(formattedPendingDate).")
                    }
                }

                // Timer Settings
                Section {
                    Toggle(isOn: $disableAutoContinue) {
                        HStack(spacing: 8) {
                            Text("⏱️")
                            Text("Disable auto-continue")
                        }
                    }

                    if !disableAutoContinue {
                        Stepper(value: $blocksUntilCheckIn, in: 1...12) {
                            HStack {
                                Text("⏰")
                                Text("Check in every \(blocksUntilCheckIn) block\(blocksUntilCheckIn == 1 ? "" : "s")")
                            }
                        }
                    }

                    Toggle(isOn: $playSoundsInSilentMode) {
                        HStack(spacing: 8) {
                            Text("🔔")
                            Text("Play sounds in silent mode")
                        }
                    }
                } header: {
                    Text("Timer")
                } footer: {
                    if playSoundsInSilentMode {
                        Text("Completion chime will play even when your phone is on silent.")
                    } else if disableAutoContinue {
                        Text("When disabled, timer won't automatically continue to the next block.")
                    } else {
                        Text("When the app auto-continues without interaction, it will ask you to confirm after this many blocks.")
                    }
                }

                // Skipped Blocks Style
                Section {
                    Toggle(isOn: $showMotivationalInsults) {
                        HStack(spacing: 8) {
                            Text("😈")
                            Text("Motivational insults")
                        }
                    }
                } header: {
                    Text("Skipped Blocks")
                } footer: {
                    Text("Show random insults on skipped blocks instead of \"SKIPPED\".")
                }

                // Segment Names
                Section {
                    NavigationLink {
                        SegmentNamesSettingsView(
                            morning: $segmentNameMorning,
                            afternoon: $segmentNameAfternoon,
                            night: $segmentNameNight
                        )
                    } label: {
                        HStack(spacing: 8) {
                            Text("📝")
                            Text("Customise Segment Names")
                        }
                    }

                    HStack {
                        Text("☀️ Morning")
                        Spacer()
                        Text(segmentNameMorning)
                            .foregroundStyle(.secondary)
                    }

                    HStack {
                        Text("🌅 Afternoon")
                        Spacer()
                        Text(segmentNameAfternoon)
                            .foregroundStyle(.secondary)
                    }

                    HStack {
                        Text("🌙 Night")
                        Spacer()
                        Text(segmentNameNight)
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Segment Names")
                }

                // Categories
                Section {
                    NavigationLink {
                        CategoriesSettingsView()
                    } label: {
                        HStack(spacing: 8) {
                            Text("🎨")
                            Text("Manage Categories")
                        }
                    }
                } header: {
                    Text("Categories")
                }

                // Favorite Labels
                Section {
                    NavigationLink {
                        FavoriteLabelsSettingsView()
                    } label: {
                        HStack(spacing: 8) {
                            Text("⭐")
                            Text("Manage Favourite Labels")
                            Spacer()
                            Text("\(blockManager.favoriteLabels.count)")
                                .foregroundStyle(.secondary)
                        }
                    }
                } header: {
                    Text("Quick Labels")
                } footer: {
                    Text("Favourite labels appear at the top when selecting a label for blocks. Synced across devices.")
                }

                // Focus Sounds
                Section {
                    Toggle(isOn: $focusSoundEnabled) {
                        HStack(spacing: 8) {
                            Text("🎵")
                            Text("Enable focus sounds")
                        }
                    }

                    if focusSoundEnabled {
                        Picker("Sound", selection: $preferredFocusSound) {
                            Text("🌧️ Rain").tag("rain")
                            Text("🌊 Ocean Waves").tag("ocean")
                            Text("🔥 Fireplace").tag("fireplace")
                            Text("🧠 Binaural Focus").tag("binaural")
                            Text("🟤 Brown Noise").tag("brownnoise")
                            Text("🩷 Pink Noise").tag("pinknoise")
                        }

                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("🔊 Volume")
                                Spacer()
                                Text("\(Int(focusSoundVolume * 100))%")
                                    .foregroundStyle(.secondary)
                            }
                            Slider(value: $focusSoundVolume, in: 0...1, step: 0.1)
                        }
                    }
                } header: {
                    Text("Focus Sounds")
                } footer: {
                    Text("Ambient sounds to help you focus during work blocks.")
                }

                // Stats
                Section {
                    NavigationLink {
                        WeeklyStatsView()
                    } label: {
                        HStack(spacing: 8) {
                            Text("📊")
                            Text("Weekly Overview")
                        }
                    }
                    NavigationLink {
                        MonthlyStatsView()
                    } label: {
                        HStack(spacing: 8) {
                            Text("📈")
                            Text("Monthly Overview")
                        }
                    }
                    NavigationLink {
                        YearlyStatsView()
                    } label: {
                        HStack(spacing: 8) {
                            Text("📅")
                            Text("Yearly Overview")
                        }
                    }
                    NavigationLink {
                        StatsExportView()
                    } label: {
                        HStack(spacing: 8) {
                            Text("📤")
                            Text("Export Statistics")
                        }
                    }
                } header: {
                    Text("Statistics")
                }

                // Data Management
                Section {
                    Button(role: .destructive) {
                        if !timerManager.isActive {
                            showResetConfirmation = true
                        } else {
                            AudioManager.shared.triggerHapticFeedback(.error)
                        }
                    } label: {
                        HStack(spacing: 8) {
                            Text("🔄")
                            Text("Reset Today's Blocks")
                        }
                    }
                    .disabled(timerManager.isActive)
                } header: {
                    Text("Data")
                } footer: {
                    if timerManager.isActive {
                        Text("Stop the timer before resetting today's blocks.")
                    } else {
                        Text("Clear all data from today's blocks including categories, labels, and progress.")
                    }
                }

                // About
                Section("About") {
                    HStack {
                        Text("Version")
                        Spacer()
                        Text("1.0.0")
                            .foregroundStyle(.secondary)
                    }

                    Link("Visit Website", destination: URL(string: "https://72blocks.com")!)
                }
            }
            .navigationTitle("Settings")
            .alert("Reset All Blocks?", isPresented: $showResetConfirmation) {
                Button("Cancel", role: .cancel) { }
                Button("Reset Day", role: .destructive) {
                    Task {
                        await blockManager.resetTodayBlocks()
                        AudioManager.shared.triggerHapticFeedback(.success)
                    }
                }
            } message: {
                Text("This will clear all data from today's blocks including categories, labels, and progress. This cannot be undone.")
            }
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .sheet(isPresented: $showDayStartPreview) {
                DayStartPreviewSheet(
                    previewHour: pendingDayStartHour >= 0 ? pendingDayStartHour : dayStartHour
                )
            }
        }
    }

    private var formattedPendingDate: String {
        guard !pendingDayStartDateString.isEmpty else { return "" }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        guard let date = formatter.date(from: pendingDayStartDateString) else { return pendingDayStartDateString }
        formatter.dateFormat = "MMMM d"
        return formatter.string(from: date)
    }
}

// MARK: - Day Start Hour Picker

struct DayStartHourPicker: View {
    @Binding var dayStartHour: Int
    @Binding var pendingDayStartHour: Int
    @Binding var pendingDayStartDateString: String
    @Binding var showPreview: Bool

    @State private var selectedHour: Int = 6

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Text("🕐")
                Picker("Day starts at", selection: $selectedHour) {
                    ForEach(0..<9) { hour in
                        Text("\(hour):00 AM").tag(hour)
                    }
                }
                .onChange(of: selectedHour) { _, newValue in
                    handleDayStartHourChange(to: newValue)
                }
            }

            // Show pending change info
            if pendingDayStartHour >= 0 {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: "clock.badge")
                            .foregroundStyle(.orange)
                        Text("Scheduled change to \(pendingDayStartHour):00 AM")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }

                    HStack(spacing: 12) {
                        Button {
                            showPreview = true
                        } label: {
                            Label("Preview", systemImage: "eye")
                                .font(.caption)
                        }
                        .buttonStyle(.bordered)

                        Button(role: .destructive) {
                            cancelPendingChange()
                        } label: {
                            Label("Cancel", systemImage: "xmark")
                                .font(.caption)
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }
        }
        .onAppear {
            // Initialize picker to current value (or pending if exists)
            selectedHour = pendingDayStartHour >= 0 ? pendingDayStartHour : dayStartHour
        }
    }

    private func handleDayStartHourChange(to newHour: Int) {
        // If same as current (and no pending), do nothing
        if newHour == dayStartHour && pendingDayStartHour < 0 {
            return
        }

        // If same as current and there was a pending, cancel the pending
        if newHour == dayStartHour && pendingDayStartHour >= 0 {
            cancelPendingChange()
            return
        }

        let calendar = Calendar.current
        let currentHour = calendar.component(.hour, from: Date())

        // Check if change can apply immediately
        // Safe if: currentHour < min(oldDayStartHour, newDayStartHour)
        let minHour = min(dayStartHour, newHour)

        if currentHour < minHour {
            // Safe - apply immediately
            dayStartHour = newHour
            pendingDayStartHour = -1
            pendingDayStartDateString = ""
        } else {
            // Defer - set pending for next calendar day
            pendingDayStartHour = newHour
            let tomorrow = calendar.date(byAdding: .day, value: 1, to: Date()) ?? Date()
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd"
            pendingDayStartDateString = formatter.string(from: tomorrow)
        }
    }

    private func cancelPendingChange() {
        pendingDayStartHour = -1
        pendingDayStartDateString = ""
        selectedHour = dayStartHour
    }
}

// MARK: - Day Start Preview Sheet

struct DayStartPreviewSheet: View {
    let previewHour: Int
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("With day starting at \(previewHour):00 AM:")
                        .font(.headline)
                        .padding(.horizontal)

                    // Show the segment breakdown
                    VStack(alignment: .leading, spacing: 12) {
                        SegmentPreviewRow(
                            icon: "sun.max.fill",
                            iconColor: .orange,
                            name: "Morning",
                            timeRange: formatTimeRange(startHour: previewHour, hours: 8),
                            blockRange: "1-24"
                        )

                        SegmentPreviewRow(
                            icon: "sun.haze.fill",
                            iconColor: .yellow,
                            name: "Afternoon & Evening",
                            timeRange: formatTimeRange(startHour: (previewHour + 8) % 24, hours: 8),
                            blockRange: "25-48"
                        )

                        SegmentPreviewRow(
                            icon: "moon.fill",
                            iconColor: .indigo,
                            name: "Night",
                            timeRange: formatTimeRange(startHour: (previewHour + 16) % 24, hours: 8),
                            blockRange: "49-72"
                        )
                    }
                    .padding()
                    .background(Color(.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .padding(.horizontal)

                    Text("Your day will flow from top to bottom, starting at \(previewHour):00 AM and ending at \(previewHour == 0 ? "11:59 PM" : "\(previewHour - 1):59 AM").")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal)
                }
                .padding(.vertical)
            }
            .navigationTitle("Layout Preview")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium])
    }

    private func formatTimeRange(startHour: Int, hours: Int) -> String {
        let endHour = (startHour + hours) % 24
        return "\(formatHour(startHour)) - \(formatHour(endHour))"
    }

    private func formatHour(_ hour: Int) -> String {
        if hour == 0 {
            return "12:00 AM"
        } else if hour < 12 {
            return "\(hour):00 AM"
        } else if hour == 12 {
            return "12:00 PM"
        } else {
            return "\(hour - 12):00 PM"
        }
    }
}

struct SegmentPreviewRow: View {
    let icon: String
    let iconColor: Color
    let name: String
    let timeRange: String
    let blockRange: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(iconColor)
                .frame(width: 30)

            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(.subheadline.weight(.medium))
                Text(timeRange)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Text("Blocks \(blockRange)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Segment Names Settings

struct SegmentNamesSettingsView: View {
    @Binding var morning: String
    @Binding var afternoon: String
    @Binding var night: String

    var body: some View {
        Form {
            Section {
                HStack {
                    Image(systemName: "sun.max.fill")
                        .foregroundStyle(.orange)
                    TextField("Morning name", text: $morning)
                }

                HStack {
                    Image(systemName: "sun.haze.fill")
                        .foregroundStyle(.yellow)
                    TextField("Afternoon name", text: $afternoon)
                }

                HStack {
                    Image(systemName: "moon.fill")
                        .foregroundStyle(.indigo)
                    TextField("Night name", text: $night)
                }
            } footer: {
                Text("Customize the names shown for each time segment.")
            }

            Section {
                Button("Reset to Defaults") {
                    morning = "Morning"
                    afternoon = "Afternoon & Evening"
                    night = "Night"
                }
            }
        }
        .navigationTitle("Segment Names")
    }
}

// MARK: - Categories Settings

struct CategoriesSettingsView: View {
    @EnvironmentObject var blockManager: BlockManager
    @State private var editingCategory: Category?
    @State private var colorPickerCategory: Category?
    @State private var editedName: String = ""

    var body: some View {
        List {
            // Categories list with hint
            Section {
                ForEach(blockManager.categories) { category in
                    CategoryRowView(
                        category: category,
                        onColorTap: {
                            colorPickerCategory = category
                        },
                        onEditTap: {
                            editedName = category.label
                            editingCategory = category
                        }
                    )
                }
            } header: {
                Text("Tap colour or ✏️ to edit")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textCase(nil)
            }
        }
        .navigationTitle("Categories")
        .task {
            await blockManager.loadCategories()
        }
        .sheet(item: $colorPickerCategory) { category in
            CategoryColorPickerSheet(category: category)
        }
        .alert("Edit Category Name", isPresented: .init(
            get: { editingCategory != nil },
            set: { if !$0 { editingCategory = nil } }
        )) {
            TextField("Category name", text: $editedName)
            Button("Cancel", role: .cancel) {
                editingCategory = nil
            }
            Button("Save") {
                if let category = editingCategory {
                    Task {
                        await blockManager.updateCategory(
                            categoryId: category.id,
                            name: editedName,
                            color: category.color
                        )
                        editingCategory = nil
                    }
                }
            }
        }
    }
}

// MARK: - Category Row View

struct CategoryRowView: View {
    let category: Category
    let onColorTap: () -> Void
    let onEditTap: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            // Tappable colour circle
            Button {
                onColorTap()
            } label: {
                Circle()
                    .fill(category.swiftUIColor)
                    .frame(width: 28, height: 28)
                    .overlay(
                        Circle()
                            .strokeBorder(Color.primary.opacity(0.2), lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)

            // Category name
            Text(category.label)
                .font(.body)

            Spacer()

            // Edit name button
            Button {
                onEditTap()
            } label: {
                Image(systemName: "pencil")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(8)
                    .background(Color.gray.opacity(0.15))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Colour Picker Sheet

struct CategoryColorPickerSheet: View {
    let category: Category
    @EnvironmentObject var blockManager: BlockManager
    @Environment(\.dismiss) private var dismiss

    @State private var selectedHue: Double = 0
    @State private var selectedSaturation: Double = 0.7
    @State private var selectedLightness: Double = 0.5

    private let presetColors: [(name: String, hsl: String)] = [
        ("Cyan", "187 85% 53%"),
        ("Purple", "280 70% 60%"),
        ("Gold", "45 93% 58%"),
        ("Pink", "340 82% 65%"),
        ("Green", "142 71% 45%"),
        ("Gray", "215 25% 50%"),
        ("Orange", "25 95% 60%"),
        ("Violet", "260 50% 60%"),
        ("Red", "0 70% 55%"),
        ("Blue", "220 80% 55%"),
        ("Teal", "170 70% 45%"),
        ("Yellow", "50 90% 55%"),
    ]

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                // Current colour preview
                HStack {
                    Text(category.label)
                        .font(.headline)
                    Spacer()
                    Circle()
                        .fill(currentColor)
                        .frame(width: 40, height: 40)
                        .overlay(
                            Circle()
                                .strokeBorder(Color.primary.opacity(0.2), lineWidth: 1)
                        )
                }
                .padding(.horizontal)
                .padding(.top)

                // Preset colors grid
                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 6), spacing: 16) {
                    ForEach(presetColors, id: \.name) { preset in
                        Button {
                            applyPreset(preset.hsl)
                        } label: {
                            Circle()
                                .fill(colorFromHSL(preset.hsl))
                                .frame(width: 44, height: 44)
                                .overlay(
                                    Circle()
                                        .strokeBorder(Color.primary, lineWidth: isSelected(preset.hsl) ? 3 : 0)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal)

                // Custom colour sliders
                VStack(alignment: .leading, spacing: 16) {
                    Text("Custom Colour")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)

                    VStack(spacing: 12) {
                        HStack {
                            Text("Hue")
                                .font(.caption)
                                .frame(width: 70, alignment: .leading)
                            Slider(value: $selectedHue, in: 0...360)
                                .tint(currentColor)
                        }

                        HStack {
                            Text("Saturation")
                                .font(.caption)
                                .frame(width: 70, alignment: .leading)
                            Slider(value: $selectedSaturation, in: 0...1)
                                .tint(currentColor)
                        }

                        HStack {
                            Text("Lightness")
                                .font(.caption)
                                .frame(width: 70, alignment: .leading)
                            Slider(value: $selectedLightness, in: 0.2...0.8)
                                .tint(currentColor)
                        }
                    }
                }
                .padding(.horizontal)

                Spacer()
            }
            .navigationTitle("Choose Colour")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveColor()
                    }
                    .fontWeight(.semibold)
                }
            }
            .onAppear {
                parseCurrentColor()
            }
        }
        .presentationDetents([.medium])
    }

    private var currentColor: Color {
        let h = selectedHue / 360
        let s = selectedSaturation
        let l = selectedLightness

        let b = l + s * min(l, 1 - l)
        let sHsb = b == 0 ? 0 : 2 * (1 - l / b)

        return Color(hue: h, saturation: sHsb, brightness: b)
    }

    private func colorFromHSL(_ hsl: String) -> Color {
        let components = hsl.split(separator: " ")
        guard components.count >= 3,
              let h = Double(components[0]),
              let s = Double(String(components[1]).replacingOccurrences(of: "%", with: "")),
              let l = Double(String(components[2]).replacingOccurrences(of: "%", with: "")) else {
            return .gray
        }

        let sNorm = s / 100
        let lNorm = l / 100
        let b = lNorm + sNorm * min(lNorm, 1 - lNorm)
        let sHsb = b == 0 ? 0 : 2 * (1 - lNorm / b)

        return Color(hue: h / 360, saturation: sHsb, brightness: b)
    }

    private func isSelected(_ hsl: String) -> Bool {
        let components = hsl.split(separator: " ")
        guard components.count >= 3,
              let h = Double(components[0]),
              let s = Double(String(components[1]).replacingOccurrences(of: "%", with: "")),
              let l = Double(String(components[2]).replacingOccurrences(of: "%", with: "")) else {
            return false
        }
        return abs(selectedHue - h) < 5 && abs(selectedSaturation * 100 - s) < 5 && abs(selectedLightness * 100 - l) < 5
    }

    private func applyPreset(_ hsl: String) {
        let components = hsl.split(separator: " ")
        guard components.count >= 3,
              let h = Double(components[0]),
              let s = Double(String(components[1]).replacingOccurrences(of: "%", with: "")),
              let l = Double(String(components[2]).replacingOccurrences(of: "%", with: "")) else {
            return
        }
        selectedHue = h
        selectedSaturation = s / 100
        selectedLightness = l / 100
    }

    private func parseCurrentColor() {
        let components = category.color.split(separator: " ")
        guard components.count >= 3,
              let h = Double(components[0]),
              let s = Double(String(components[1]).replacingOccurrences(of: "%", with: "")),
              let l = Double(String(components[2]).replacingOccurrences(of: "%", with: "")) else {
            return
        }
        selectedHue = h
        selectedSaturation = s / 100
        selectedLightness = l / 100
    }

    private func saveColor() {
        let newColor = "\(Int(selectedHue)) \(Int(selectedSaturation * 100))% \(Int(selectedLightness * 100))%"
        Task {
            await blockManager.updateCategory(categoryId: category.id, name: category.label, color: newColor)
            dismiss()
        }
    }
}

// MARK: - Favorite Labels Settings

struct FavoriteLabelsSettingsView: View {
    @EnvironmentObject var blockManager: BlockManager
    @State private var newLabel = ""

    var body: some View {
        Form {
            Section {
                if blockManager.favoriteLabels.isEmpty {
                    Text("No favourite labels yet")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(blockManager.favoriteLabels, id: \.self) { label in
                        HStack {
                            Image(systemName: "star.fill")
                                .foregroundStyle(.yellow)
                                .font(.caption)
                            Text(label)
                        }
                    }
                    .onDelete { indexSet in
                        Task {
                            for index in indexSet {
                                let label = blockManager.favoriteLabels[index]
                                await blockManager.removeFavoriteLabel(label)
                            }
                        }
                    }
                }
            } header: {
                Text("Favourite Labels")
            } footer: {
                Text("These labels appear at the top of the label picker for quick access. Max 30 labels. Synced across devices.")
            }

            Section {
                HStack {
                    TextField("Add favourite label", text: $newLabel)
                        .textInputAutocapitalization(.sentences)
                    Button {
                        addLabel()
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .foregroundStyle(.green)
                    }
                    .disabled(newLabel.trimmingCharacters(in: .whitespaces).isEmpty || blockManager.favoriteLabels.count >= 30)
                }
            } footer: {
                if blockManager.favoriteLabels.count >= 30 {
                    Text("Maximum of 30 favourite labels reached.")
                        .foregroundStyle(.orange)
                }
            }
        }
        .navigationTitle("Favourite Labels")
    }

    private func addLabel() {
        let trimmed = newLabel.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        guard !blockManager.favoriteLabels.contains(trimmed) else {
            newLabel = ""
            return
        }

        Task {
            await blockManager.addFavoriteLabel(trimmed)
            newLabel = ""
        }
    }
}

// MARK: - Weekly Stats View

struct WeeklyStatsView: View {
    var body: some View {
        WeeklyOverviewContent()
            .navigationTitle("Weekly Overview")
    }
}

// MARK: - Monthly Stats View

struct MonthlyStatsView: View {
    var body: some View {
        MonthlyOverviewContent()
            .navigationTitle("Monthly Overview")
    }
}

// MARK: - Yearly Stats View

struct YearlyStatsView: View {
    var body: some View {
        YearlyOverviewContent()
            .navigationTitle("Yearly Overview")
    }
}

#Preview {
    SettingsView()
        .environmentObject(AuthManager())
        .environmentObject(BlockManager())
        .environmentObject(TimerManager())
}
