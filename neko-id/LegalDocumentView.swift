import SwiftUI

struct LegalDocument {
    enum Block {
        case paragraph(String)
        case subheading(String)
        case emphasis(String)
        case bullets([String])
        case numbered([String])
    }

    struct Section {
        let title: String
        let blocks: [Block]
    }

    let navigationTitle: String
    let title: String
    let updatedDate: String
    let effectiveDate: String
    let introduction: [String]
    let sections: [Section]
}

/// Legal documents ship with the app and remain readable without a network or an account.
struct LegalDocumentView: View {
    @Environment(\.dismiss) private var dismiss
    let document: LegalDocument

    var body: some View {
        ScrollView {
            LegalDocumentContent(document: document)
                .padding(.horizontal, 24)
                .padding(.top, 24)
                .padding(.bottom, 36)
                .frame(maxWidth: 680)
                .frame(maxWidth: .infinity)
        }
        .background(NekoBackground())
        .safeAreaInset(edge: .top, spacing: 0) {
            HStack {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(NekoTheme.menuIcon)
                        .frame(width: 44, height: 44)
                        .background(Color.white.opacity(0.82), in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("返回")

                Spacer()
                Text(document.navigationTitle)
                    .font(.headline)
                    .foregroundStyle(NekoTheme.ink)
                Spacer()
                Color.clear.frame(width: 44, height: 44)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 8)
            .background(.regularMaterial)
        }
        .toolbar(.hidden, for: .navigationBar)
        .navigationBarBackButtonHidden(true)
        .nekoEdgeSwipeBack { dismiss() }
    }
}

struct LegalDocumentContent: View {
    let document: LegalDocument

    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            VStack(alignment: .leading, spacing: 12) {
                Text(document.title)
                    .font(.title2.bold())
                    .accessibilityAddTraits(.isHeader)

                VStack(alignment: .leading, spacing: 6) {
                    Text("更新日期：\(document.updatedDate)")
                    Text("生效日期：\(document.effectiveDate)")
                }
                .font(.subheadline)
                .foregroundStyle(NekoTheme.inkSoft)
            }

            VStack(alignment: .leading, spacing: 14) {
                ForEach(document.introduction, id: \.self) { paragraph in
                    Text(paragraph)
                }
            }

            ForEach(document.sections, id: \.title) { section in
                VStack(alignment: .leading, spacing: 14) {
                    Text(section.title)
                        .font(.title3.bold())
                        .accessibilityAddTraits(.isHeader)

                    ForEach(section.blocks.indices, id: \.self) { index in
                        documentBlock(section.blocks[index])
                    }
                }
            }
        }
        .font(.body)
        .foregroundStyle(NekoTheme.ink)
        .lineSpacing(6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .textSelection(.enabled)
        .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder
    private func documentBlock(_ block: LegalDocument.Block) -> some View {
        switch block {
        case .paragraph(let text):
            Text(.init(text))
        case .subheading(let text):
            Text(text)
                .font(.headline)
                .padding(.top, 6)
                .accessibilityAddTraits(.isHeader)
        case .emphasis(let text):
            Text(text)
                .fontWeight(.semibold)
        case .bullets(let items):
            documentList(items, numbered: false)
        case .numbered(let items):
            documentList(items, numbered: true)
        }
    }

    private func documentList(_ items: [String], numbered: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(items.indices, id: \.self) { index in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(numbered ? "\(index + 1)." : "•")
                        .accessibilityHidden(!numbered)
                    Text(items[index])
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .accessibilityElement(children: .combine)
            }
        }
    }
}
