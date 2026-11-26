import SwiftUI

// MARK: - Markdown renderer for chat assistant messages

struct ChatMarkdownView: View {
    let markdown: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(ChatMarkdown.parse(markdown).enumerated()), id: \.offset) { _, block in
                blockView(block)
            }
        }
        .environment(\.openURL, OpenURLAction { url in
            guard let safe = safeWebURL(url.absoluteString) else { return .discarded }
            NSWorkspace.shared.open(safe)
            return .handled
        })
    }

    @ViewBuilder
    private func blockView(_ block: MDBlock) -> some View {
        switch block {
        case .heading(let level, let text):
            Text(inlineAttributed(text))
                .font(.system(size: level <= 2 ? 14 : 13, weight: level <= 2 ? .bold : .semibold))
                .foregroundColor(Pace.ink)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)

        case .paragraph(let text):
            Text(inlineAttributed(text))
                .font(.system(size: 12.5))
                .foregroundColor(Pace.body)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)

        case .codeBlock(_, let code):
            HStack(alignment: .top) {
                Text(code)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(Pace.ink2)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                CopyButton(text: code)
            }
            .padding(10)
            .background(Pace.ground)
            .clipShape(RoundedRectangle(cornerRadius: Pace.rCtrl, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Pace.rCtrl, style: .continuous).stroke(Pace.line, lineWidth: 1))

        case .listItem(let prefix, let text, let indent):
            HStack(alignment: .top, spacing: 6) {
                Text(prefix)
                    .font(.system(size: 12.5))
                    .foregroundColor(Pace.ink3)
                    .frame(minWidth: prefix.count > 2 ? 20 : 10, alignment: .leading)
                Text(inlineAttributed(text))
                    .font(.system(size: 12.5))
                    .foregroundColor(Pace.body)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }
            .padding(.leading, CGFloat(indent) * 12)

        case .quote(let text):
            HStack(alignment: .top, spacing: 8) {
                Rectangle()
                    .fill(Pace.lineCtrl)
                    .frame(width: 2)
                    .clipShape(Capsule())
                Text(inlineAttributed(text))
                    .font(.system(size: 12.5))
                    .foregroundColor(Pace.ink2)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }

        case .rule:
            Rectangle().fill(Pace.line).frame(height: 1)
        }
    }

    private func inlineAttributed(_ text: String) -> AttributedString {
        var options = AttributedString.MarkdownParsingOptions(
            interpretedSyntax: .inlineOnlyPreservingWhitespace)
        options.failurePolicy = .returnPartiallyParsedIfPossible
        return (try? AttributedString(markdown: text, options: options)) ?? AttributedString(text)
    }
}

// MARK: - Copy button

private struct CopyButton: View {
    let text: String
    @State private var copied = false

    var body: some View {
        Button {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
            withAnimation { copied = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                withAnimation { copied = false }
            }
        } label: {
            Image(systemName: copied ? "checkmark" : "doc.on.doc")
                .font(.system(size: 10))
                .foregroundColor(copied ? Pace.mint : Pace.ink3)
        }
        .buttonStyle(.plain)
        .frame(width: 22, height: 22)
        .background(Pace.raised)
        .clipShape(RoundedRectangle(cornerRadius: Pace.r, style: .continuous))
    }
}
