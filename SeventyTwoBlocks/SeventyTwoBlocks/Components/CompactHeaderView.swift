import SwiftUI

struct CompactHeaderView: View {
    @Binding var selectedDate: Date
    @Binding var showSettings: Bool
    @State private var showDatePicker = false
    @AppStorage("appearanceMode") private var appearanceMode: Int = 2  // 1 = light, 2 = dark

    private var isToday: Bool {
        Calendar.current.isDateInToday(selectedDate)
    }

    private var dateLabel: String {
        if isToday {
            return "Today"
        }
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return formatter.string(from: selectedDate)
    }

    private var fullDateLabel: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE, MMM d"
        return formatter.string(from: selectedDate)
    }

    var body: some View {
        ZStack {
            // Date navigation - true center, constrained width to match block grid center column
            HStack(spacing: 4) {
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        selectedDate = Calendar.current.date(byAdding: .day, value: -1, to: selectedDate) ?? selectedDate
                    }
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.primary)
                        .frame(width: 44, height: 44)  // Larger tap target
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                VStack(spacing: 1) {
                    Text(dateLabel)
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.primary)

                    Text(fullDateLabel)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                .frame(minWidth: 80)
                .onTapGesture {
                    // Tap on date to jump to today
                    if !isToday {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            selectedDate = Date()
                        }
                    }
                }

                Button {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        selectedDate = Calendar.current.date(byAdding: .day, value: 1, to: selectedDate) ?? selectedDate
                    }
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.primary)
                        .frame(width: 44, height: 44)  // Larger tap target
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }

            // Left and right items
            HStack(spacing: 16) {
                // Logo - "72 Blocks" in small caps, rectangle like a block
                ZStack {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.orange)
                        .frame(height: 26)

                    Text("72 Blocks")
                        .font(.system(size: 11, weight: .semibold, design: .rounded).smallCaps())
                        .foregroundStyle(.black)
                        .padding(.horizontal, 8)
                }
                .fixedSize()
                .padding(.leading, 2)

                Spacer()

                // Light/Dark mode toggle
                Button {
                    // Toggle between light (1) and dark (2)
                    appearanceMode = appearanceMode == 1 ? 2 : 1
                } label: {
                    Image(systemName: appearanceMode == 1 ? "sun.max.fill" : "moon.fill")
                        .font(.subheadline)
                        .foregroundColor(appearanceMode == 1 ? .orange : .indigo)
                }
                .buttonStyle(.plain)

                // Calendar picker button
                Button {
                    showDatePicker = true
                } label: {
                    Image(systemName: "calendar")
                        .font(.subheadline)
                        .foregroundColor(.primary)
                }
                .buttonStyle(.plain)

                // Settings button
                Button {
                    showSettings = true
                } label: {
                    Image(systemName: "gearshape")
                        .font(.subheadline)
                        .foregroundColor(.primary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 20)  // Align with cards (which have extra padding vs blocks)
        .padding(.vertical, 10)
        .sheet(isPresented: $showDatePicker) {
            DatePickerSheet(selectedDate: $selectedDate, isPresented: $showDatePicker)
        }
    }
}

// MARK: - Date Picker Sheet

struct DatePickerSheet: View {
    @Binding var selectedDate: Date
    @Binding var isPresented: Bool

    var body: some View {
        NavigationStack {
            VStack {
                DatePicker(
                    "Select Date",
                    selection: $selectedDate,
                    displayedComponents: .date
                )
                .datePickerStyle(.graphical)
                .padding()

                Spacer()
            }
            .navigationTitle("Jump to Date")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Today") {
                        selectedDate = Date()
                        isPresented = false
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        isPresented = false
                    }
                    .fontWeight(.semibold)
                }
            }
        }
        .presentationDetents([.medium])
    }
}

#Preview {
    VStack {
        CompactHeaderView(selectedDate: .constant(Date()), showSettings: .constant(false))
        Spacer()
    }
}
