import SwiftUI

struct DateHeaderView: View {
    @Binding var selectedDate: Date
    @AppStorage("dayStartHour") private var dayStartHour = 6

    /// Whether selectedDate matches the "logical today" (accounting for dayStartHour)
    private var isToday: Bool {
        let now = Date()
        let calendar = Calendar.current
        let currentHour = calendar.component(.hour, from: now)

        // Calculate logical today
        let logicalToday: Date
        if currentHour < dayStartHour {
            logicalToday = calendar.date(byAdding: .day, value: -1, to: now) ?? now
        } else {
            logicalToday = now
        }

        // Compare date strings
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: selectedDate) == formatter.string(from: logicalToday)
    }

    var body: some View {
        HStack {
            Button {
                selectedDate = Calendar.current.date(byAdding: .day, value: -1, to: selectedDate) ?? selectedDate
            } label: {
                Image(systemName: "chevron.left")
                    .font(.title3)
            }

            Spacer()

            VStack(spacing: 4) {
                Text(selectedDate, format: .dateTime.weekday(.wide))
                    .font(.headline)

                Text(selectedDate, format: .dateTime.month().day().year())
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                selectedDate = Calendar.current.date(byAdding: .day, value: 1, to: selectedDate) ?? selectedDate
            } label: {
                Image(systemName: "chevron.right")
                    .font(.title3)
            }
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .overlay {
            if isToday {
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(.primary.opacity(0.3), lineWidth: 1)
            }
        }
    }
}

#Preview {
    DateHeaderView(selectedDate: .constant(Date()))
        .padding()
}
