import SwiftUI

struct ArticleRow: View {
    let article: ArticleSummary

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            pushBadge
                .frame(width: 34)

            VStack(alignment: .leading, spacing: 3) {
                Text(article.title)
                    .font(.subheadline)
                    .foregroundStyle(article.isDeleted ? .secondary : .primary)
                    .lineLimit(2)
                HStack(spacing: 6) {
                    Text(article.author.isEmpty ? "-" : article.author)
                    Text("·")
                    Text(article.date)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .opacity(article.isDeleted ? 0.5 : 1)
    }

    @ViewBuilder
    private var pushBadge: some View {
        let mark = article.pushMark
        Group {
            if mark == "爆" {
                Text("爆").foregroundStyle(.white).padding(.horizontal, 4).background(Color.red).clipShape(RoundedRectangle(cornerRadius: 4))
            } else if mark.hasPrefix("X") {
                Text(mark).foregroundStyle(.white).padding(.horizontal, 4).background(Color.blue).clipShape(RoundedRectangle(cornerRadius: 4))
            } else if let n = Int(mark), n > 0 {
                Text(mark).foregroundStyle(n >= 10 ? .white : .primary)
                    .padding(.horizontal, 4)
                    .background(n >= 10 ? Color.orange : Color.clear)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            } else {
                Text(" ")
            }
        }
        .font(.caption2.bold())
    }
}
