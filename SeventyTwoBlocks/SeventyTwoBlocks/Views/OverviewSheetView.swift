import SwiftUI

// MARK: - Main Overview Sheet with Tabs

struct OverviewSheetView: View {
    @EnvironmentObject var blockManager: BlockManager
    @Environment(\.dismiss) private var dismiss
    @State private var selectedTab: OverviewTab = .day

    enum OverviewTab: String, CaseIterable {
        case day = "Day"
        case week = "Week"
        case month = "Month"
        case year = "Year"
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Tab picker
                Picker("Period", selection: $selectedTab) {
                    ForEach(OverviewTab.allCases, id: \.self) { tab in
                        Text(tab.rawValue).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.top, 8)

                // Content based on selected tab - lazy loading
                Group {
                    switch selectedTab {
                    case .day:
                        DayOverviewContent()
                    case .week:
                        WeeklyOverviewContent()
                    case .month:
                        MonthlyOverviewContent()
                    case .year:
                        YearlyOverviewContent()
                    }
                }
            }
            .navigationTitle("Overview")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

// MARK: - Day Overview Content

struct DayOverviewContent: View {
    @EnvironmentObject var blockManager: BlockManager

    private var doneBlocks: Int {
        blockManager.blocks.filter { $0.status == .done }.count
    }

    private var skippedBlocks: Int {
        blockManager.blocks.filter { $0.status == .skipped }.count
    }

    private var plannedBlocks: Int {
        blockManager.blocks.filter { $0.status == .planned }.count
    }

    private var idleBlocks: Int {
        blockManager.blocks.filter { $0.status == .idle && !$0.isMuted }.count
    }

    private var mutedBlocks: Int {
        blockManager.blocks.filter { $0.isMuted }.count
    }

    private var totalWorkedSeconds: Int {
        OverviewHelpers.calculateWorkedSeconds(blocks: blockManager.blocks)
    }

    private var completedSets: Int {
        doneBlocks / 12
    }

    private var currentSetProgress: Int {
        doneBlocks % 12
    }

    private var categoryStats: [CategoryWithLabels] {
        OverviewHelpers.calculateCategoryStats(
            blocks: blockManager.blocks,
            categories: blockManager.categories
        )
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Summary stats
                HStack(spacing: 16) {
                    StatBox(icon: "checkmark.circle.fill", iconColor: .green, value: "\(doneBlocks)", label: "Completed")
                    StatBox(icon: "clock.fill", iconColor: .blue, value: OverviewHelpers.formatDuration(totalWorkedSeconds), label: "Worked")
                    StatBox(icon: "trophy.fill", iconColor: .yellow, value: "\(completedSets)", label: "Sets")
                }
                .padding()
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12))

                // Progress section
                VStack(alignment: .leading, spacing: 12) {
                    Text("Progress to Next Set")
                        .font(.headline)

                    HStack {
                        Text("\(currentSetProgress)/12 blocks")
                            .font(.subheadline.weight(.medium))
                        Spacer()
                        if completedSets > 0 {
                            Text("🏆 \(completedSets) set\(completedSets == 1 ? "" : "s") done!")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    ProgressBar(value: Double(currentSetProgress) / 12.0)
                }
                .padding()
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12))

                // Category breakdown
                if !categoryStats.isEmpty {
                    CategoryBreakdownSection(stats: categoryStats)
                }

                // Status breakdown
                VStack(alignment: .leading, spacing: 12) {
                    Text("Block Status")
                        .font(.headline)

                    HStack(spacing: 12) {
                        StatusPill(label: "Done", count: doneBlocks, color: .green)
                        StatusPill(label: "Planned", count: plannedBlocks, color: .blue)
                        StatusPill(label: "Skipped", count: skippedBlocks, color: .gray)
                        StatusPill(label: "Idle", count: idleBlocks, color: .secondary)
                    }

                    if mutedBlocks > 0 {
                        HStack {
                            Image(systemName: "moon.zzz.fill")
                                .foregroundStyle(.indigo)
                            Text("\(mutedBlocks) sleep blocks")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding()
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .padding()
        }
    }
}

// MARK: - Weekly Overview Content

struct WeeklyOverviewContent: View {
    @EnvironmentObject var blockManager: BlockManager
    @State private var weeklyBlocks: [Block] = []
    @State private var isLoading = true
    @State private var selectedWeekOffset = 0 // 0 = past 7 days, 1 = last week, etc.

    private var dateRange: [String] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        var dates: [String] = []

        if selectedWeekOffset == 0 {
            // Past 7 days (rolling)
            for i in (0..<7).reversed() {
                if let date = calendar.date(byAdding: .day, value: -i, to: today) {
                    dates.append(OverviewHelpers.formatDateKey(date))
                }
            }
        } else {
            // Specific week (Mon-Sun)
            let weekStart = calendar.date(byAdding: .weekOfYear, value: -selectedWeekOffset, to: today)!
            let monday = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: weekStart))!

            for i in 0..<7 {
                if let date = calendar.date(byAdding: .day, value: i, to: monday) {
                    dates.append(OverviewHelpers.formatDateKey(date))
                }
            }
        }
        return dates
    }

    private var periodLabel: String {
        if selectedWeekOffset == 0 {
            return "Past 7 days"
        }
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        if let firstDate = OverviewHelpers.parseDate(dateRange.first ?? ""),
           let lastDate = OverviewHelpers.parseDate(dateRange.last ?? "") {
            return "\(formatter.string(from: firstDate)) – \(formatter.string(from: lastDate))"
        }
        return "Week"
    }

    private var stats: WeeklyStats {
        OverviewHelpers.calculateWeeklyStats(
            blocks: weeklyBlocks,
            dateRange: dateRange,
            categories: blockManager.categories
        )
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Week selector
                HStack {
                    Button {
                        selectedWeekOffset = min(selectedWeekOffset + 1, 12)
                    } label: {
                        Image(systemName: "chevron.left")
                            .foregroundStyle(.primary)
                    }
                    .disabled(selectedWeekOffset >= 12)

                    Spacer()

                    Text(periodLabel)
                        .font(.subheadline.weight(.medium))

                    Spacer()

                    Button {
                        selectedWeekOffset = max(selectedWeekOffset - 1, 0)
                    } label: {
                        Image(systemName: "chevron.right")
                            .foregroundStyle(.primary)
                    }
                    .disabled(selectedWeekOffset == 0)
                }
                .padding(.horizontal)

                if isLoading {
                    ProgressView()
                        .padding(.vertical, 40)
                } else {
                    // Summary stats
                    HStack(spacing: 16) {
                        StatBox(icon: "target", iconColor: .green, value: "\(stats.totalCompleted)", label: "Blocks")
                        StatBox(icon: "clock.fill", iconColor: .blue, value: OverviewHelpers.formatDuration(stats.totalMinutes * 60), label: "Time")
                        StatBox(icon: "trophy.fill", iconColor: .yellow, value: "\(stats.totalSets)", label: "Sets")
                    }
                    .padding()
                    .background(Color(.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 12))

                    // Additional stats
                    HStack(spacing: 12) {
                        MiniStatBox(value: "\(stats.daysWithActivity)", label: "Active Days")
                        MiniStatBox(value: "\(stats.avgBlocksPerActiveDay)", label: "Avg/Day")
                    }

                    // Daily bar chart
                    VStack(alignment: .leading, spacing: 12) {
                        Text("📊 Daily Activity")
                            .font(.headline)

                        DailyBarChart(dailyStats: stats.dailyStats)
                    }
                    .padding()
                    .background(Color(.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 12))

                    // Best day
                    if let bestDay = stats.bestDay, bestDay.completed > 0 {
                        HStack {
                            Text("🏆")
                            VStack(alignment: .leading) {
                                Text("Best Day: \(bestDay.dayName)")
                                    .font(.subheadline.weight(.medium))
                                Text("\(bestDay.completed) blocks • \(OverviewHelpers.formatDuration(bestDay.minutes * 60))")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                        }
                        .padding()
                        .background(Color.green.opacity(0.15))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }

                    // Category breakdown
                    if !stats.categoryStats.isEmpty {
                        CategoryBreakdownSection(stats: stats.categoryStats)
                    }
                }
            }
            .padding()
        }
        .task {
            await loadWeeklyBlocks()
        }
        .onChange(of: selectedWeekOffset) { _, _ in
            Task {
                await loadWeeklyBlocks()
            }
        }
    }

    private func loadWeeklyBlocks() async {
        isLoading = true
        weeklyBlocks = await blockManager.loadBlocksForDateRange(dates: dateRange, onlyWithActivity: true)
        isLoading = false
    }
}

// MARK: - Monthly Overview Content

struct MonthlyOverviewContent: View {
    @EnvironmentObject var blockManager: BlockManager
    @State private var monthlyBlocks: [Block] = []
    @State private var isLoading = true
    @State private var selectedMonthOffset = 0 // 0 = past 30 days

    private var dateRange: [String] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        var dates: [String] = []

        if selectedMonthOffset == 0 {
            // Past 30 days
            for i in (0..<30).reversed() {
                if let date = calendar.date(byAdding: .day, value: -i, to: today) {
                    dates.append(OverviewHelpers.formatDateKey(date))
                }
            }
        } else {
            // Specific month
            if let monthStart = calendar.date(byAdding: .month, value: -selectedMonthOffset, to: today) {
                let range = calendar.range(of: .day, in: .month, for: monthStart)!
                let startOfMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: monthStart))!

                for i in 0..<range.count {
                    if let date = calendar.date(byAdding: .day, value: i, to: startOfMonth) {
                        dates.append(OverviewHelpers.formatDateKey(date))
                    }
                }
            }
        }
        return dates
    }

    private var periodLabel: String {
        if selectedMonthOffset == 0 {
            return "Past 30 days"
        }
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        if let firstDate = OverviewHelpers.parseDate(dateRange.first ?? "") {
            return formatter.string(from: firstDate)
        }
        return "Month"
    }

    private var stats: MonthlyStats {
        OverviewHelpers.calculateMonthlyStats(
            blocks: monthlyBlocks,
            dateRange: dateRange,
            categories: blockManager.categories
        )
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Month selector
                HStack {
                    Button {
                        selectedMonthOffset = min(selectedMonthOffset + 1, 12)
                    } label: {
                        Image(systemName: "chevron.left")
                    }
                    .disabled(selectedMonthOffset >= 12)

                    Spacer()

                    Text(periodLabel)
                        .font(.subheadline.weight(.medium))

                    Spacer()

                    Button {
                        selectedMonthOffset = max(selectedMonthOffset - 1, 0)
                    } label: {
                        Image(systemName: "chevron.right")
                    }
                    .disabled(selectedMonthOffset == 0)
                }
                .padding(.horizontal)

                if isLoading {
                    ProgressView()
                        .padding(.vertical, 40)
                } else {
                    // Summary stats
                    HStack(spacing: 16) {
                        StatBox(icon: "target", iconColor: .green, value: "\(stats.totalCompleted)", label: "Blocks")
                        StatBox(icon: "clock.fill", iconColor: .blue, value: OverviewHelpers.formatDuration(stats.totalMinutes * 60), label: "Time")
                        StatBox(icon: "trophy.fill", iconColor: .yellow, value: "\(stats.totalSets)", label: "Sets")
                    }
                    .padding()
                    .background(Color(.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 12))

                    // Weekly breakdown
                    VStack(alignment: .leading, spacing: 12) {
                        Text("📅 Weekly Breakdown")
                            .font(.headline)

                        ForEach(stats.weeklyStats, id: \.weekLabel) { week in
                            HStack {
                                Text(week.weekLabel)
                                    .font(.subheadline)
                                Spacer()
                                Text("\(week.completed) blocks")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                Text("•")
                                    .foregroundStyle(.secondary)
                                Text(OverviewHelpers.formatDuration(week.minutes * 60))
                                    .font(.subheadline.weight(.medium))
                            }
                            .padding(.vertical, 4)
                        }
                    }
                    .padding()
                    .background(Color(.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 12))

                    // Category breakdown
                    if !stats.categoryStats.isEmpty {
                        CategoryBreakdownSection(stats: stats.categoryStats)
                    }
                }
            }
            .padding()
        }
        .task {
            await loadMonthlyBlocks()
        }
        .onChange(of: selectedMonthOffset) { _, _ in
            Task {
                await loadMonthlyBlocks()
            }
        }
    }

    private func loadMonthlyBlocks() async {
        isLoading = true
        monthlyBlocks = await blockManager.loadBlocksForDateRange(dates: dateRange, onlyWithActivity: true)
        isLoading = false
    }
}

// MARK: - Yearly Overview Content

struct YearlyOverviewContent: View {
    @EnvironmentObject var blockManager: BlockManager
    @State private var yearlyBlocks: [Block] = []
    @State private var isLoading = true
    @State private var selectedYear: Int = Calendar.current.component(.year, from: Date())

    private var dateRange: [String] {
        let calendar = Calendar.current
        var dates: [String] = []

        var components = DateComponents()
        components.year = selectedYear
        components.month = 1
        components.day = 1

        guard let yearStart = calendar.date(from: components) else { return dates }

        let daysInYear = calendar.range(of: .day, in: .year, for: yearStart)?.count ?? 365

        for i in 0..<daysInYear {
            if let date = calendar.date(byAdding: .day, value: i, to: yearStart) {
                dates.append(OverviewHelpers.formatDateKey(date))
            }
        }
        return dates
    }

    private var stats: YearlyStats {
        OverviewHelpers.calculateYearlyStats(
            blocks: yearlyBlocks,
            year: selectedYear,
            categories: blockManager.categories
        )
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Year selector
                HStack {
                    Button {
                        selectedYear -= 1
                    } label: {
                        Image(systemName: "chevron.left")
                    }
                    .disabled(selectedYear <= 2020)

                    Spacer()

                    Text(String(selectedYear))
                        .font(.subheadline.weight(.medium))

                    Spacer()

                    Button {
                        selectedYear += 1
                    } label: {
                        Image(systemName: "chevron.right")
                    }
                    .disabled(selectedYear >= Calendar.current.component(.year, from: Date()))
                }
                .padding(.horizontal)

                if isLoading {
                    ProgressView()
                        .padding(.vertical, 40)
                } else {
                    // Summary stats
                    HStack(spacing: 16) {
                        StatBox(icon: "target", iconColor: .green, value: "\(stats.totalCompleted)", label: "Blocks")
                        StatBox(icon: "clock.fill", iconColor: .blue, value: OverviewHelpers.formatDuration(stats.totalMinutes * 60), label: "Time")
                        StatBox(icon: "trophy.fill", iconColor: .yellow, value: "\(stats.totalSets)", label: "Sets")
                    }
                    .padding()
                    .background(Color(.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 12))

                    // Additional stats
                    HStack(spacing: 12) {
                        MiniStatBox(value: "\(stats.daysWithActivity)", label: "Active Days")
                        MiniStatBox(value: "\(stats.avgBlocksPerActiveDay)", label: "Avg/Day")
                    }

                    // Monthly breakdown
                    VStack(alignment: .leading, spacing: 12) {
                        Text("📅 Monthly Breakdown")
                            .font(.headline)

                        ForEach(stats.monthlyStats, id: \.monthLabel) { month in
                            HStack {
                                Text(month.monthLabel)
                                    .font(.subheadline)
                                    .frame(width: 80, alignment: .leading)

                                // Mini bar
                                GeometryReader { geo in
                                    let maxBlocks = stats.monthlyStats.map(\.completed).max() ?? 1
                                    RoundedRectangle(cornerRadius: 3)
                                        .fill(Color.blue)
                                        .frame(width: geo.size.width * CGFloat(month.completed) / CGFloat(max(maxBlocks, 1)))
                                }
                                .frame(height: 8)

                                Text("\(month.completed)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .frame(width: 40, alignment: .trailing)
                            }
                            .padding(.vertical, 2)
                        }
                    }
                    .padding()
                    .background(Color(.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 12))

                    // Category breakdown
                    if !stats.categoryStats.isEmpty {
                        CategoryBreakdownSection(stats: stats.categoryStats)
                    }
                }
            }
            .padding()
        }
        .task {
            await loadYearlyBlocks()
        }
        .onChange(of: selectedYear) { _, _ in
            Task {
                await loadYearlyBlocks()
            }
        }
    }

    private func loadYearlyBlocks() async {
        isLoading = true
        // Only load blocks with activity for better performance
        yearlyBlocks = await blockManager.loadBlocksForDateRange(dates: dateRange, onlyWithActivity: true)
        isLoading = false
    }
}

// MARK: - Supporting Views

struct StatBox: View {
    let icon: String
    let iconColor: Color
    let value: String
    let label: String

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(iconColor)

            Text(value)
                .font(.title2.weight(.bold))

            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

struct MiniStatBox: View {
    let value: String
    let label: String

    var body: some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.title3.weight(.bold))
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

struct StatusPill: View {
    let label: String
    let count: Int
    let color: Color

    var body: some View {
        VStack(spacing: 4) {
            Text("\(count)")
                .font(.headline)
                .foregroundStyle(color)

            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

struct ProgressBar: View {
    let value: Double

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.gray.opacity(0.2))
                    .frame(height: 12)

                RoundedRectangle(cornerRadius: 6)
                    .fill(
                        LinearGradient(
                            colors: [.green, .blue],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: geo.size.width * max(0, min(1, value)), height: 12)
            }
        }
        .frame(height: 12)
    }
}

struct DailyBarChart: View {
    let dailyStats: [DailyStats]

    private var maxBlocks: Int {
        max(dailyStats.map(\.completed).max() ?? 1, 1)
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: 4) {
            ForEach(dailyStats, id: \.date) { day in
                VStack(spacing: 4) {
                    if day.completed > 0 {
                        Text("\(day.completed)")
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                    }

                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.blue)
                        .frame(height: max(4, CGFloat(day.completed) / CGFloat(maxBlocks) * 60))

                    Text(day.dayName)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .frame(height: 90)
    }
}

struct CategoryBreakdownSection: View {
    let stats: [CategoryWithLabels]

    private var totalSeconds: Int {
        stats.reduce(0) { $0 + $1.seconds }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("📁 By Category")
                .font(.headline)

            VStack(spacing: 8) {
                ForEach(stats, id: \.category.id) { stat in
                    CategoryRowWithLabels(stat: stat, totalSeconds: totalSeconds)
                }
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

struct CategoryRowWithLabels: View {
    let stat: CategoryWithLabels
    let totalSeconds: Int
    @State private var isExpanded = false

    var body: some View {
        VStack(spacing: 4) {
            // Category row
            HStack {
                // Expand/collapse button if has labels
                if !stat.labels.isEmpty {
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            isExpanded.toggle()
                        }
                    } label: {
                        Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .frame(width: 14)
                    }
                    .buttonStyle(.plain)
                } else {
                    Spacer().frame(width: 14)
                }

                Circle()
                    .fill(stat.category.swiftUIColor)
                    .frame(width: 12, height: 12)

                Text(stat.category.label)
                    .font(.subheadline)

                Spacer()

                let percentage = totalSeconds > 0 ? Int(Double(stat.seconds) / Double(totalSeconds) * 100) : 0
                Text("\(OverviewHelpers.formatDuration(stat.seconds)) (\(percentage)%)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            // Nested labels (when expanded)
            if isExpanded && !stat.labels.isEmpty {
                VStack(spacing: 4) {
                    ForEach(stat.labels, id: \.label) { labelStat in
                        HStack {
                            Spacer().frame(width: 26)
                            Text(labelStat.label)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text(OverviewHelpers.formatDuration(labelStat.seconds))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(.leading, 14)
            }

            // Progress bar
            GeometryReader { geo in
                let percentage = totalSeconds > 0 ? Double(stat.seconds) / Double(totalSeconds) : 0
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.gray.opacity(0.2))
                        .frame(height: 6)

                    RoundedRectangle(cornerRadius: 3)
                        .fill(stat.category.swiftUIColor)
                        .frame(width: geo.size.width * percentage, height: 6)
                }
            }
            .frame(height: 6)
            .padding(.leading, 14)
        }
    }
}


// MARK: - Data Types

struct LabelStats {
    let label: String
    let seconds: Int
}

struct CategoryWithLabels {
    let category: Category
    let count: Int
    let seconds: Int
    let labels: [LabelStats]
}

struct DailyStats {
    let date: String
    let dayName: String
    let completed: Int
    let minutes: Int
    let setsCompleted: Int
}

struct WeeklyStats {
    let dailyStats: [DailyStats]
    let totalCompleted: Int
    let totalMinutes: Int
    let totalSets: Int
    let daysWithActivity: Int
    let avgBlocksPerActiveDay: Int
    let bestDay: DailyStats?
    let categoryStats: [CategoryWithLabels]
}

struct MonthlyStats {
    let weeklyStats: [(weekLabel: String, completed: Int, minutes: Int)]
    let totalCompleted: Int
    let totalMinutes: Int
    let totalSets: Int
    let categoryStats: [CategoryWithLabels]
}

struct YearlyStats {
    let monthlyStats: [(monthLabel: String, completed: Int, minutes: Int)]
    let totalCompleted: Int
    let totalMinutes: Int
    let totalSets: Int
    let daysWithActivity: Int
    let avgBlocksPerActiveDay: Int
    let categoryStats: [CategoryWithLabels]
}

// MARK: - Helper Functions

enum OverviewHelpers {
    static func formatDuration(_ seconds: Int) -> String {
        if seconds == 0 {
            return "0m"
        }
        // Under 30 seconds shows as "<1m"
        if seconds > 0 && seconds < 30 {
            return "<1m"
        }
        // Round to nearest minute (30s+ rounds up)
        let totalMinutes = (seconds + 30) / 60
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }
        return "\(minutes)m"
    }

    static func formatDateKey(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    static func parseDate(_ dateString: String) -> Date? {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: dateString)
    }

    // Calculate worked seconds from actual segments (matches StatsCardView)
    // IMPORTANT: Only counts blocks that are .done - skipped blocks should not count toward totals
    static func calculateWorkedSeconds(blocks: [Block]) -> Int {
        return blocks.reduce(0) { total, block in
            total + workedSecondsFor(block)
        }
    }

    // Calculate worked seconds for a single block from segments
    // Returns 0 for skipped blocks - they shouldn't count toward worked time
    static func workedSecondsFor(_ block: Block) -> Int {
        // Skip blocks that aren't done - skipped blocks shouldn't count toward worked time
        guard block.status == .done else { return 0 }

        // Sum actual work segments (not break segments)
        let workSeconds = block.segments
            .filter { $0.type == .work }
            .reduce(0) { $0 + $1.seconds }

        // Round up to 20m (1200s) if worked >= 19 minutes (95% of block)
        // This credits auto-continue and quick starts without penalizing small gaps
        if workSeconds >= 19 * 60 {
            return 20 * 60
        }
        return workSeconds
    }

    static func calculateCategoryStats(blocks: [Block], categories: [Category]) -> [CategoryWithLabels] {
        // Track category -> (count, seconds, labels -> seconds)
        // IMPORTANT: Aggregate from SEGMENT-level category/label, not block-level
        // This matches the web app behavior and allows segment edits to reflect in stats
        var stats: [String: (count: Int, seconds: Int, labels: [String: Int])] = [:]

        for block in blocks where block.status == .done {
            // Use segment-level data if available
            if !block.segments.isEmpty {
                for segment in block.segments where segment.type == .work {
                    // Segment category takes priority, fall back to block category
                    let catId = segment.category ?? block.category ?? "uncategorized"
                    // Segment label takes priority, fall back to block label
                    let labelKey = segment.label ?? block.label ?? "Unlabelled"
                    let seconds = segment.seconds

                    var current = stats[catId] ?? (0, 0, [:])
                    // Don't increment count per segment - count blocks separately
                    current.1 += seconds
                    current.2[labelKey, default: 0] += seconds
                    stats[catId] = current
                }
            } else {
                // Fallback: use block-level data for legacy blocks without segments
                let catId = block.category ?? "uncategorized"
                let labelKey = block.label ?? "Unlabelled"
                let seconds = workedSecondsFor(block)

                var current = stats[catId] ?? (0, 0, [:])
                current.1 += seconds
                current.2[labelKey, default: 0] += seconds
                stats[catId] = current
            }

            // Count blocks per category (based on primary block category)
            let blockCatId = block.category ?? "uncategorized"
            var current = stats[blockCatId] ?? (0, 0, [:])
            current.0 += 1
            stats[blockCatId] = current
        }

        return stats.compactMap { (catId, data) in
            let category: Category
            if catId == "uncategorized" {
                category = Category(
                    id: "uncategorized",
                    label: "Uncategorised",
                    color: "0 0% 50%",
                    labels: nil
                )
            } else if let cat = categories.first(where: { $0.id == catId }) {
                category = cat
            } else {
                // Create a placeholder category for unknown IDs
                category = Category(
                    id: catId,
                    label: catId.capitalized,
                    color: "0 0% 50%",
                    labels: nil
                )
            }

            // Convert labels dict to sorted array
            let labelStats = data.2.map { LabelStats(label: $0.key, seconds: $0.value) }
                .sorted { $0.seconds > $1.seconds }

            return CategoryWithLabels(
                category: category,
                count: data.0,
                seconds: data.1,
                labels: labelStats
            )
        }.sorted { $0.seconds > $1.seconds }
    }

    static func calculateWeeklyStats(blocks: [Block], dateRange: [String], categories: [Category]) -> WeeklyStats {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE"

        // Group blocks by date
        var blocksByDate: [String: [Block]] = [:]
        dateRange.forEach { blocksByDate[$0] = [] }
        blocks.forEach { block in
            blocksByDate[block.date, default: []].append(block)
        }

        // Calculate daily stats
        let dailyStats: [DailyStats] = dateRange.map { date in
            let dayBlocks = blocksByDate[date] ?? []
            let completed = dayBlocks.filter { $0.status == .done }.count
            let seconds = dayBlocks.filter { $0.status == .done }.reduce(0) { $0 + workedSecondsFor($1) }

            let dayName: String
            if let d = parseDate(date) {
                dayName = formatter.string(from: d)
            } else {
                dayName = ""
            }

            return DailyStats(
                date: date,
                dayName: dayName,
                completed: completed,
                minutes: seconds / 60,
                setsCompleted: completed / 12
            )
        }

        let totalCompleted = dailyStats.reduce(0) { $0 + $1.completed }
        let totalMinutes = dailyStats.reduce(0) { $0 + $1.minutes }
        let totalSets = dailyStats.reduce(0) { $0 + $1.setsCompleted }
        let daysWithActivity = dailyStats.filter { $0.completed > 0 }.count
        let avgBlocksPerActiveDay = daysWithActivity > 0 ? totalCompleted / daysWithActivity : 0
        let bestDay = dailyStats.max(by: { $0.completed < $1.completed })

        let categoryStats = calculateCategoryStats(blocks: blocks.filter { $0.status == .done }, categories: categories)

        return WeeklyStats(
            dailyStats: dailyStats,
            totalCompleted: totalCompleted,
            totalMinutes: totalMinutes,
            totalSets: totalSets,
            daysWithActivity: daysWithActivity,
            avgBlocksPerActiveDay: avgBlocksPerActiveDay,
            bestDay: bestDay,
            categoryStats: categoryStats
        )
    }

    static func calculateMonthlyStats(blocks: [Block], dateRange: [String], categories: [Category]) -> MonthlyStats {
        let calendar = Calendar.current

        // Group by week
        var weeklyData: [(weekLabel: String, completed: Int, minutes: Int)] = []
        var currentWeekBlocks: [Block] = []
        var currentWeekStart: Date?

        for dateString in dateRange {
            guard let date = parseDate(dateString) else { continue }
            let dayBlocks = blocks.filter { $0.date == dateString }

            if currentWeekStart == nil {
                currentWeekStart = date
            }

            // Check if new week
            if let start = currentWeekStart,
               calendar.component(.weekOfYear, from: date) != calendar.component(.weekOfYear, from: start) {
                // Save current week
                let completed = currentWeekBlocks.filter { $0.status == .done }.count
                let seconds = currentWeekBlocks.filter { $0.status == .done }.reduce(0) { $0 + workedSecondsFor($1) }
                let formatter = DateFormatter()
                formatter.dateFormat = "MMM d"
                weeklyData.append((formatter.string(from: start), completed, seconds / 60))

                currentWeekBlocks = []
                currentWeekStart = date
            }

            currentWeekBlocks.append(contentsOf: dayBlocks)
        }

        // Don't forget last week
        if let start = currentWeekStart, !currentWeekBlocks.isEmpty {
            let completed = currentWeekBlocks.filter { $0.status == .done }.count
            let seconds = currentWeekBlocks.filter { $0.status == .done }.reduce(0) { $0 + workedSecondsFor($1) }
            let formatter = DateFormatter()
            formatter.dateFormat = "MMM d"
            weeklyData.append((formatter.string(from: start), completed, seconds / 60))
        }

        let totalCompleted = blocks.filter { $0.status == .done }.count
        let totalMinutes = calculateWorkedSeconds(blocks: blocks.filter { $0.status == .done }) / 60
        let totalSets = totalCompleted / 12

        let categoryStats = calculateCategoryStats(blocks: blocks.filter { $0.status == .done }, categories: categories)

        return MonthlyStats(
            weeklyStats: weeklyData,
            totalCompleted: totalCompleted,
            totalMinutes: totalMinutes,
            totalSets: totalSets,
            categoryStats: categoryStats
        )
    }

    static func calculateYearlyStats(blocks: [Block], year: Int, categories: [Category]) -> YearlyStats {
        let calendar = Calendar.current
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM"

        // Group by month
        var monthlyData: [(monthLabel: String, completed: Int, minutes: Int)] = []

        for month in 1...12 {
            var components = DateComponents()
            components.year = year
            components.month = month
            components.day = 1

            guard let monthStart = calendar.date(from: components) else { continue }

            let monthBlocks = blocks.filter { block in
                guard let blockDate = parseDate(block.date) else { return false }
                return calendar.component(.month, from: blockDate) == month &&
                       calendar.component(.year, from: blockDate) == year
            }

            let completed = monthBlocks.filter { $0.status == .done }.count
            let seconds = monthBlocks.filter { $0.status == .done }.reduce(0) { $0 + workedSecondsFor($1) }

            monthlyData.append((formatter.string(from: monthStart), completed, seconds / 60))
        }

        let doneBlocks = blocks.filter { $0.status == .done }
        let totalCompleted = doneBlocks.count
        let totalMinutes = calculateWorkedSeconds(blocks: doneBlocks) / 60
        let totalSets = totalCompleted / 12

        // Days with activity
        let uniqueDates = Set(doneBlocks.map { $0.date })
        let daysWithActivity = uniqueDates.count
        let avgBlocksPerActiveDay = daysWithActivity > 0 ? totalCompleted / daysWithActivity : 0

        let categoryStats = calculateCategoryStats(blocks: doneBlocks, categories: categories)

        return YearlyStats(
            monthlyStats: monthlyData,
            totalCompleted: totalCompleted,
            totalMinutes: totalMinutes,
            totalSets: totalSets,
            daysWithActivity: daysWithActivity,
            avgBlocksPerActiveDay: avgBlocksPerActiveDay,
            categoryStats: categoryStats
        )
    }
}

#Preview {
    OverviewSheetView()
        .environmentObject(BlockManager())
}
