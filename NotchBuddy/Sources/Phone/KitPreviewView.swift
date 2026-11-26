import SwiftUI

/// Step 3 check: CoucouKit (Mochi, pills, diff, models) drawn on the iPhone
/// with the Mac's own code.
struct KitPreviewView: View {
    private let poses: [(BotState, EyeShape?, String)] = [
        (.idle, nil, "idle"),
        (.working, nil, "working"),
        (.approval, nil, "approval"),
        (.question, nil, "question"),
        (.finished, .happy, "finished"),
        (.error, nil, "error"),
        (.sleeping, .closed, "sleeping"),
        (.thinking, nil, "thinking"),
    ]

    private let sampleDiff = DiffEngine.fromEdit(
        old: "func greet() {\n    print(\"Hello\")\n}\n",
        new: "func greet(name: String) {\n    print(\"Coucou \\(name)\")\n}\n",
        path: "/coucou/Greeting.swift")

    var body: some View {
        List {
            Section {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 72))], spacing: 12) {
                    ForEach(Array(poses.enumerated()), id: \.offset) { index, pose in
                        VStack(spacing: 4) {
                            MochiStill(state: pose.0, eye: pose.1)
                                .padding(6)
                                .frame(width: 64, height: 64)
                                .background(tileColor(index), in: RoundedRectangle(cornerRadius: Pace.rIslandCard, style: .continuous))
                            Text(pose.2).font(.caption2).foregroundStyle(Pace.ink3)
                        }
                    }
                }
                .padding(.vertical, 6)
            } header: {
                Text("Mochi — fixed poses").textCase(nil)
            }

            ForEach(PillCategory.allCases, id: \.self) { category in
                Section {
                    ForEach(PillCatalog.all.filter { $0.category == category }, id: \.id) { pill in
                        HStack(spacing: 12) {
                            MochiStill()
                                .padding(3)
                                .frame(width: 30, height: 30)
                                .background(Color.mochiTile(hex: pill.color), in: RoundedRectangle(cornerRadius: Pace.rCtrl, style: .continuous))
                            VStack(alignment: .leading) {
                                Text(pill.name).foregroundStyle(Pace.ink)
                                Text(pill.id).font(.caption2.monospaced()).foregroundStyle(Pace.ink3)
                            }
                            Spacer()
                            Text(pill.subtitle).font(.caption).foregroundStyle(Pace.ink3)
                        }
                    }
                } header: {
                    Text(category.title).textCase(nil)
                }
            }

            Section {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(sampleDiff.hunks.flatMap(\.lines).enumerated()), id: \.offset) { _, line in
                        Text(prefix(line.kind) + line.text)
                            .font(.caption.monospaced())
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 6)
                            .background(lineColor(line.kind))
                    }
                }
            } header: {
                Text("Diff — \(sampleDiff.name) +\(sampleDiff.added) −\(sampleDiff.removed)")
                    .monospacedDigit()
                    .textCase(nil)
            }
        }
        .scrollContentBackground(.hidden)
        .background(Pace.ground)
        .navigationTitle("CoucouKit")
    }

    private func tileColor(_ index: Int) -> Color {
        let pills = PillCatalog.all
        return Color(hex: pills[index % pills.count].color)
    }

    private func prefix(_ kind: DiffLine.Kind) -> String {
        switch kind {
        case .added: "+ "
        case .removed: "− "
        case .context: "  "
        }
    }

    private func lineColor(_ kind: DiffLine.Kind) -> Color {
        switch kind {
        case .added: Pace.mint.opacity(0.18)
        case .removed: Pace.fail.opacity(0.18)
        case .context: .clear
        }
    }
}
