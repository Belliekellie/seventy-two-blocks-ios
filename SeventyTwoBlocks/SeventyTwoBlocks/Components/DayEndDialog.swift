import SwiftUI

struct DayEndDialog: View {
    let onStartNextDay: () -> Void
    let onContinueWorking: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            // Icon
            ZStack {
                Circle()
                    .fill(Color.orange.opacity(0.2))
                    .frame(width: 80, height: 80)

                Image(systemName: "sun.horizon.fill")
                    .font(.system(size: 40))
                    .foregroundStyle(.orange)
            }

            // Title + subtitle
            VStack(spacing: 8) {
                Text("Day Complete")
                    .font(.title2.bold())

                Text("Your assigned day has ended. Would you like to start a new day or keep working?")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }

            // Buttons
            VStack(spacing: 12) {
                Button(action: onStartNextDay) {
                    HStack {
                        Image(systemName: "sunrise.fill")
                        Text("Start Next Day")
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.blue)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }

                Button(action: onContinueWorking) {
                    HStack {
                        Image(systemName: "arrow.forward")
                        Text("Continue Working")
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.orange.opacity(0.15))
                    .foregroundStyle(.orange)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(Color.orange.opacity(0.3), lineWidth: 1)
                    )
                }
            }
        }
        .padding(24)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .shadow(color: .black.opacity(0.15), radius: 20, x: 0, y: 10)
        .padding(.horizontal, 24)
    }
}
