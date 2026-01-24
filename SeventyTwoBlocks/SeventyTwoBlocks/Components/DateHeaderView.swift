import SwiftUI

struct DateHeaderView: View {
    @Binding var selectedDate: Date

    private var isToday: Bool {
        Calendar.current.isDateInToday(selectedDate)
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
