import SwiftUI

struct PushRow: View {
    let push: PushComment

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            Text(push.kind.rawValue)
                .font(.caption.bold())
                .foregroundStyle(color)
                .frame(width: 20)

            Text(push.author)
                .font(.caption.bold())
                .foregroundStyle(.primary)

            Text(push.content)
                .font(.caption)
                .foregroundStyle(.primary)

            Spacer(minLength: 4)

            Text(push.timestamp)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }

    private var color: Color {
        switch push.kind {
        case .push: return .green
        case .boo: return .blue
        case .arrow: return .secondary
        }
    }
}
