import SwiftUI
import MessageUI
import PDFKit

struct StatsExportView: View {
    @EnvironmentObject var blockManager: BlockManager
    @Environment(\.dismiss) private var dismiss

    @State private var periodType: PeriodType = .week
    @State private var selectedOffset = 0
    @State private var isExporting = false
    @State private var blocks: [Block] = []
    @State private var showShareSheet = false
    @State private var showEmailSheet = false
    @State private var exportText = ""
    @State private var exportFormat: ExportFormat = .text
    @State private var pdfData: Data?

    enum PeriodType: String, CaseIterable {
        case week = "Weekly"
        case month = "Monthly"
        case year = "Yearly"
    }

    enum ExportFormat: String, CaseIterable {
        case text = "Text"
        case pdf = "PDF"
    }

    private var dateRange: (start: String, end: String, label: String) {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())

        switch periodType {
        case .week:
            if selectedOffset == 0 {
                let start = calendar.date(byAdding: .day, value: -6, to: today)!
                return (formatDate(start), formatDate(today), "Past 7 days")
            } else {
                let weekStart = calendar.date(byAdding: .weekOfYear, value: -selectedOffset, to: today)!
                let monday = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: weekStart))!
                let sunday = calendar.date(byAdding: .day, value: 6, to: monday)!
                let formatter = DateFormatter()
                formatter.dateFormat = "MMM d"
                return (formatDate(monday), formatDate(sunday), "\(formatter.string(from: monday)) – \(formatter.string(from: sunday))")
            }
        case .month:
            if selectedOffset == 0 {
                let start = calendar.date(byAdding: .day, value: -29, to: today)!
                return (formatDate(start), formatDate(today), "Past 30 days")
            } else {
                let monthStart = calendar.date(byAdding: .month, value: -selectedOffset, to: today)!
                let start = calendar.date(from: calendar.dateComponents([.year, .month], from: monthStart))!
                let range = calendar.range(of: .day, in: .month, for: start)!
                let end = calendar.date(byAdding: .day, value: range.count - 1, to: start)!
                let formatter = DateFormatter()
                formatter.dateFormat = "MMMM yyyy"
                return (formatDate(start), formatDate(end), formatter.string(from: start))
            }
        case .year:
            let year = calendar.component(.year, from: today) - selectedOffset
            var components = DateComponents()
            components.year = year
            components.month = 1
            components.day = 1
            let start = calendar.date(from: components)!
            components.month = 12
            components.day = 31
            let end = calendar.date(from: components)!
            return (formatDate(start), formatDate(end), String(year))
        }
    }

    private var periodOptions: [(offset: Int, label: String)] {
        switch periodType {
        case .week:
            var options = [(0, "Past 7 days")]
            for i in 1...12 {
                let calendar = Calendar.current
                let today = calendar.startOfDay(for: Date())
                let weekStart = calendar.date(byAdding: .weekOfYear, value: -i, to: today)!
                let monday = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: weekStart))!
                let sunday = calendar.date(byAdding: .day, value: 6, to: monday)!
                let formatter = DateFormatter()
                formatter.dateFormat = "MMM d"
                options.append((i, "\(formatter.string(from: monday)) – \(formatter.string(from: sunday))"))
            }
            return options
        case .month:
            var options = [(0, "Past 30 days")]
            let formatter = DateFormatter()
            formatter.dateFormat = "MMMM yyyy"
            for i in 1...12 {
                let calendar = Calendar.current
                let today = Date()
                let monthStart = calendar.date(byAdding: .month, value: -i, to: today)!
                options.append((i, formatter.string(from: monthStart)))
            }
            return options
        case .year:
            let currentYear = Calendar.current.component(.year, from: Date())
            return (0..<5).map { ($0, String(currentYear - $0)) }
        }
    }

    private var canSendEmail: Bool {
        MFMailComposeViewController.canSendMail()
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Period Type", selection: $periodType) {
                        ForEach(PeriodType.allCases, id: \.self) { type in
                            Text(type.rawValue).tag(type)
                        }
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: periodType) { _, _ in
                        selectedOffset = 0
                        exportText = ""
                    }

                    Picker("Select Period", selection: $selectedOffset) {
                        ForEach(periodOptions, id: \.offset) { option in
                            Text(option.label).tag(option.offset)
                        }
                    }
                    .onChange(of: selectedOffset) { _, _ in
                        exportText = ""
                    }
                }

                Section {
                    // Share as Text button
                    Button {
                        exportFormat = .text
                        Task {
                            await generateExport(action: .share)
                        }
                    } label: {
                        HStack {
                            Image(systemName: "doc.text")
                            Text("Share as Text")
                            Spacer()
                            if isExporting && exportFormat == .text {
                                ProgressView()
                                    .scaleEffect(0.8)
                            }
                        }
                    }
                    .disabled(isExporting)

                    // Share as PDF button
                    Button {
                        exportFormat = .pdf
                        Task {
                            await generateExport(action: .share)
                        }
                    } label: {
                        HStack {
                            Image(systemName: "doc.richtext")
                            Text("Share as PDF")
                            Spacer()
                            if isExporting && exportFormat == .pdf {
                                ProgressView()
                                    .scaleEffect(0.8)
                            }
                        }
                    }
                    .disabled(isExporting)

                    // Email button
                    Button {
                        Task {
                            await generateExport(action: .email)
                        }
                    } label: {
                        HStack {
                            Image(systemName: "envelope")
                            Text("Send via Email")
                            Spacer()
                            if !canSendEmail {
                                Text("Not available")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .disabled(isExporting || !canSendEmail)
                } header: {
                    Text("Export Options")
                } footer: {
                    if !canSendEmail {
                        Text("Email is not available. Please configure Mail in Settings.")
                    }
                }

                if !exportText.isEmpty {
                    Section("Preview") {
                        Text(exportText)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Export Statistics")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .sheet(isPresented: $showShareSheet) {
                if exportFormat == .pdf, let pdfData = pdfData {
                    ShareSheet(items: [pdfData])
                } else {
                    ShareSheet(items: [exportText])
                }
            }
            .sheet(isPresented: $showEmailSheet) {
                if exportFormat == .pdf, let pdfData = pdfData {
                    MailView(
                        subject: "72 Blocks Statistics - \(dateRange.label)",
                        body: "Please find attached my 72 Blocks statistics report.",
                        attachmentData: pdfData,
                        attachmentMimeType: "application/pdf",
                        attachmentFileName: "72blocks-stats-\(dateRange.label.replacingOccurrences(of: " ", with: "-")).pdf"
                    )
                } else {
                    MailView(
                        subject: "72 Blocks Statistics - \(dateRange.label)",
                        body: exportText,
                        attachmentData: nil,
                        attachmentMimeType: nil,
                        attachmentFileName: nil
                    )
                }
            }
        }
    }

    enum ExportAction {
        case share
        case email
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    private func generateExport(action: ExportAction) async {
        isExporting = true

        let range = dateRange
        let calendar = Calendar.current
        var dates: [String] = []

        // Generate all dates in range
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        if let start = formatter.date(from: range.start),
           let end = formatter.date(from: range.end) {
            var current = start
            while current <= end {
                dates.append(formatDate(current))
                current = calendar.date(byAdding: .day, value: 1, to: current)!
            }
        }

        // Load blocks
        blocks = await blockManager.loadBlocksForDateRange(dates: dates, onlyWithActivity: true)

        // Generate report
        let report = generateReport(periodLabel: range.label, blocks: blocks, dates: dates)
        exportText = report

        // Generate PDF if needed
        if exportFormat == .pdf {
            pdfData = generatePDF(report: report, periodLabel: range.label)
        }

        isExporting = false

        switch action {
        case .share:
            showShareSheet = true
        case .email:
            showEmailSheet = true
        }
    }

    private func generatePDF(report: String, periodLabel: String) -> Data {
        let pageWidth: CGFloat = 612
        let pageHeight: CGFloat = 792
        let margin: CGFloat = 50

        let pdfRenderer = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: pageWidth, height: pageHeight))

        let data = pdfRenderer.pdfData { context in
            context.beginPage()

            var yPosition: CGFloat = margin

            // Title
            let titleFont = UIFont.boldSystemFont(ofSize: 24)
            let titleAttributes: [NSAttributedString.Key: Any] = [
                .font: titleFont,
                .foregroundColor: UIColor.label
            ]
            let title = "72 Blocks Statistics"
            title.draw(at: CGPoint(x: margin, y: yPosition), withAttributes: titleAttributes)
            yPosition += 35

            // Subtitle
            let subtitleFont = UIFont.systemFont(ofSize: 16)
            let subtitleAttributes: [NSAttributedString.Key: Any] = [
                .font: subtitleFont,
                .foregroundColor: UIColor.secondaryLabel
            ]
            let subtitle = "Period: \(periodLabel)"
            subtitle.draw(at: CGPoint(x: margin, y: yPosition), withAttributes: subtitleAttributes)
            yPosition += 20

            let dateStr = "Generated: \(DateFormatter.localizedString(from: Date(), dateStyle: .long, timeStyle: .short))"
            dateStr.draw(at: CGPoint(x: margin, y: yPosition), withAttributes: subtitleAttributes)
            yPosition += 40

            // Body content
            let bodyFont = UIFont.monospacedSystemFont(ofSize: 11, weight: .regular)
            let bodyAttributes: [NSAttributedString.Key: Any] = [
                .font: bodyFont,
                .foregroundColor: UIColor.label
            ]

            // Split report into lines and draw
            let lines = report.components(separatedBy: "\n")
            let lineHeight: CGFloat = 16

            for line in lines {
                // Skip title lines we already drew
                if line.contains("72 BLOCKS") || line.contains("====") || line.starts(with: "Period:") || line.starts(with: "Generated:") {
                    continue
                }

                // Check if we need a new page
                if yPosition + lineHeight > pageHeight - margin {
                    context.beginPage()
                    yPosition = margin
                }

                // Section headers
                if line.contains("📈") || line.contains("📁") || line.contains("📅") {
                    yPosition += 10
                    let headerFont = UIFont.boldSystemFont(ofSize: 14)
                    let headerAttributes: [NSAttributedString.Key: Any] = [
                        .font: headerFont,
                        .foregroundColor: UIColor.label
                    ]
                    line.draw(at: CGPoint(x: margin, y: yPosition), withAttributes: headerAttributes)
                    yPosition += lineHeight + 5
                } else if line.starts(with: "---") || line.starts(with: "---") {
                    // Divider lines
                    yPosition += 5
                } else {
                    line.draw(at: CGPoint(x: margin, y: yPosition), withAttributes: bodyAttributes)
                    yPosition += lineHeight
                }
            }
        }

        return data
    }

    private func generateReport(periodLabel: String, blocks: [Block], dates: [String]) -> String {
        var lines: [String] = []

        lines.append("📊 72 BLOCKS - STATISTICS REPORT")
        lines.append("================================")
        lines.append("Period: \(periodLabel)")
        lines.append("Generated: \(DateFormatter.localizedString(from: Date(), dateStyle: .long, timeStyle: .short))")
        lines.append("")

        // Calculate stats
        let doneBlocks = blocks.filter { $0.status == .done }
        let totalCompleted = doneBlocks.count
        let totalSeconds = doneBlocks.reduce(0) { total, block in
            let workProgress = block.progress / 100.0
            let breakProgress = block.breakProgress / 100.0
            let workPortion = 1.0 - breakProgress
            return total + Int(20 * 60 * workProgress * workPortion)
        }
        let totalSets = totalCompleted / 12

        lines.append("📈 SUMMARY")
        lines.append("----------")
        lines.append("Blocks Completed: \(totalCompleted)")
        lines.append("Time Worked: \(formatDuration(totalSeconds))")
        lines.append("Sets Completed: \(totalSets)")

        // Days with activity
        let uniqueDates = Set(doneBlocks.map { $0.date })
        lines.append("Active Days: \(uniqueDates.count)")
        if uniqueDates.count > 0 {
            lines.append("Average Blocks/Day: \(totalCompleted / uniqueDates.count)")
        }
        lines.append("")

        // Category breakdown
        let categoryStats = calculateCategoryStats(blocks: doneBlocks)
        if !categoryStats.isEmpty {
            lines.append("📁 BY CATEGORY")
            lines.append("--------------")
            for stat in categoryStats {
                let percentage = totalSeconds > 0 ? Int(Double(stat.seconds) / Double(totalSeconds) * 100) : 0
                lines.append("\(stat.category.label): \(formatDuration(stat.seconds)) (\(percentage)%)")

                // Labels under category
                for label in stat.labels {
                    lines.append("  • \(label.label): \(formatDuration(label.seconds))")
                }
            }
            lines.append("")
        }

        // Daily/Weekly/Monthly breakdown based on period type
        switch periodType {
        case .week:
            lines.append("📅 DAILY BREAKDOWN")
            lines.append("------------------")
            let formatter = DateFormatter()
            formatter.dateFormat = "EEE, MMM d"
            for date in dates {
                let dayBlocks = blocks.filter { $0.date == date && $0.status == .done }
                let completed = dayBlocks.count
                let seconds = dayBlocks.reduce(0) { total, block in
                    let workProgress = block.progress / 100.0
                    let breakProgress = block.breakProgress / 100.0
                    let workPortion = 1.0 - breakProgress
                    return total + Int(20 * 60 * workProgress * workPortion)
                }
                if let d = parseDate(date) {
                    lines.append("\(formatter.string(from: d)): \(completed) blocks, \(formatDuration(seconds))")
                }
            }

        case .month:
            lines.append("📅 WEEKLY BREAKDOWN")
            lines.append("-------------------")
            // Group by week
            let calendar = Calendar.current
            var weeklyData: [(week: String, completed: Int, seconds: Int)] = []
            var currentWeekBlocks: [Block] = []
            var currentWeekStart: Date?

            for dateString in dates {
                guard let date = parseDate(dateString) else { continue }
                let dayBlocks = blocks.filter { $0.date == dateString }

                if currentWeekStart == nil {
                    currentWeekStart = date
                }

                if let start = currentWeekStart,
                   calendar.component(.weekOfYear, from: date) != calendar.component(.weekOfYear, from: start) {
                    let completed = currentWeekBlocks.filter { $0.status == .done }.count
                    let seconds = currentWeekBlocks.filter { $0.status == .done }.reduce(0) { total, block in
                        let workProgress = block.progress / 100.0
                        let breakProgress = block.breakProgress / 100.0
                        return total + Int(20 * 60 * workProgress * (1.0 - breakProgress))
                    }
                    let formatter = DateFormatter()
                    formatter.dateFormat = "MMM d"
                    weeklyData.append((formatter.string(from: start), completed, seconds))
                    currentWeekBlocks = []
                    currentWeekStart = date
                }

                currentWeekBlocks.append(contentsOf: dayBlocks)
            }

            // Last week
            if let start = currentWeekStart, !currentWeekBlocks.isEmpty {
                let completed = currentWeekBlocks.filter { $0.status == .done }.count
                let seconds = currentWeekBlocks.filter { $0.status == .done }.reduce(0) { total, block in
                    let workProgress = block.progress / 100.0
                    let breakProgress = block.breakProgress / 100.0
                    return total + Int(20 * 60 * workProgress * (1.0 - breakProgress))
                }
                let formatter = DateFormatter()
                formatter.dateFormat = "MMM d"
                weeklyData.append((formatter.string(from: start), completed, seconds))
            }

            for week in weeklyData {
                lines.append("Week of \(week.week): \(week.completed) blocks, \(formatDuration(week.seconds))")
            }

        case .year:
            lines.append("📅 MONTHLY BREAKDOWN")
            lines.append("--------------------")
            let calendar = Calendar.current
            let formatter = DateFormatter()
            formatter.dateFormat = "MMMM"

            for month in 1...12 {
                let monthBlocks = blocks.filter { block in
                    guard let date = parseDate(block.date) else { return false }
                    return calendar.component(.month, from: date) == month
                }
                let completed = monthBlocks.filter { $0.status == .done }.count
                let seconds = monthBlocks.filter { $0.status == .done }.reduce(0) { total, block in
                    let workProgress = block.progress / 100.0
                    let breakProgress = block.breakProgress / 100.0
                    return total + Int(20 * 60 * workProgress * (1.0 - breakProgress))
                }

                var components = DateComponents()
                components.month = month
                if let date = calendar.date(from: components) {
                    lines.append("\(formatter.string(from: date)): \(completed) blocks, \(formatDuration(seconds))")
                }
            }
        }

        lines.append("")
        lines.append("---")
        lines.append("Exported from 72 Blocks iOS")

        return lines.joined(separator: "\n")
    }

    private func parseDate(_ dateString: String) -> Date? {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: dateString)
    }

    private func formatDuration(_ seconds: Int) -> String {
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }
        return "\(minutes)m"
    }

    private func calculateCategoryStats(blocks: [Block]) -> [CategoryWithLabels] {
        var stats: [String: (count: Int, seconds: Int, labels: [String: Int])] = [:]

        for block in blocks {
            let catId = block.category ?? "uncategorized"
            let labelKey = block.label ?? "Unlabelled"
            let workProgress = block.progress / 100.0
            let breakProgress = block.breakProgress / 100.0
            let seconds = Int(20 * 60 * workProgress * (1.0 - breakProgress))

            var current = stats[catId] ?? (0, 0, [:])
            current.0 += 1
            current.1 += seconds
            current.2[labelKey, default: 0] += seconds
            stats[catId] = current
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
            } else if let cat = blockManager.categories.first(where: { $0.id == catId }) {
                category = cat
            } else {
                return nil
            }

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
}

// MARK: - Share Sheet

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

// MARK: - Mail View

struct MailView: UIViewControllerRepresentable {
    let subject: String
    let body: String
    let attachmentData: Data?
    let attachmentMimeType: String?
    let attachmentFileName: String?

    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> MFMailComposeViewController {
        let mailVC = MFMailComposeViewController()
        mailVC.mailComposeDelegate = context.coordinator
        mailVC.setSubject(subject)
        mailVC.setMessageBody(body, isHTML: false)

        if let data = attachmentData,
           let mimeType = attachmentMimeType,
           let fileName = attachmentFileName {
            mailVC.addAttachmentData(data, mimeType: mimeType, fileName: fileName)
        }

        return mailVC
    }

    func updateUIViewController(_ uiViewController: MFMailComposeViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(dismiss: dismiss)
    }

    class Coordinator: NSObject, MFMailComposeViewControllerDelegate {
        let dismiss: DismissAction

        init(dismiss: DismissAction) {
            self.dismiss = dismiss
        }

        func mailComposeController(_ controller: MFMailComposeViewController, didFinishWith result: MFMailComposeResult, error: Error?) {
            controller.dismiss(animated: true)
        }
    }
}

#Preview {
    StatsExportView()
        .environmentObject(BlockManager())
}
