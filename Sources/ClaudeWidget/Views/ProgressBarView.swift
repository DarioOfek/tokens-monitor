import SwiftUI

struct LimitBar: View {
    let limit: UsageLimit

    private var color: Color {
        switch limit.clampedUsedPercent {
        case 90...: .red
        case 70..<90: .orange
        default: Color(red: 0.35, green: 0.80, blue: 0.63)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(limit.label)
                    .foregroundStyle(.white.opacity(0.84))
                Spacer()
                Text("\(Int(limit.clampedUsedPercent.rounded()))% used")
                    .fontWeight(.semibold)
                    .foregroundStyle(color)
            }
            .font(.system(size: 11))

            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.14))
                    Capsule().fill(color)
                        .frame(width: geometry.size.width * limit.clampedUsedPercent / 100)
                }
            }
            .frame(height: 6)

            if let resetAt = limit.resetAt {
                Text("Resets \(resetAt.formatted(date: .abbreviated, time: .shortened))")
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.53))
            } else if let description = limit.resetDescription {
                Text(description)
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.53))
            }
        }
        .accessibilityElement(children: .combine)
    }
}
