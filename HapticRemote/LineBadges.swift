//
//  LineBadges.swift
//  HapticRemote (iPhone)
//
//  A stop's lines as small badges in their own colours ("Tram ② ④ · Metro ⑤②"),
//  on the home screen's card and in search. The colours come from the
//  timetable (Transit): GVB's metro lines have theirs; lines without one
//  (GVB's trams, NS's trains) get the place's own quiet badge.
//

import SwiftUI

struct LineBadges: View {
    let lines: Transit.Lines
    /// For a line without colours, and the "Tram", "Metro" words.
    var textColor: Color = Palette.text
    var badgeColor: Color = Palette.text.opacity(0.14)
    /// Trams, metros and trains each on a line of their own, instead of
    /// one after the other.
    var separateModes = false
    /// "Metro", the widest of the words, at the current text size.
    @ScaledMetric(relativeTo: .subheadline) private var modeWidth: CGFloat = 48

    var body: some View {
        Group {
            if separateModes {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(lines.groups.enumerated()), id: \.offset) { _, group in
                        FlowLayout(spacing: 6, lineSpacing: 6) {
                            groupContent(group, isFirst: true, alignsBadges: true)
                        }
                    }
                }
            } else {
                FlowLayout(spacing: 6, lineSpacing: 6) {
                    ForEach(Array(lines.groups.enumerated()), id: \.offset) { index, group in
                        groupContent(group, isFirst: index == 0)
                    }
                }
            }
        }
        // VoiceOver reads the lines from the row's own label.
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private func groupContent(_ group: (mode: Transit.Mode, lines: [Transit.Line]), isFirst: Bool,
                              alignsBadges: Bool = false) -> some View {
        // A mode a line: the words as wide as "Metro", so the badges start in a column.
        Text(isFirst ? group.mode.name : "· \(group.mode.name)")
            .font(.atkinson(15, .medium, relativeTo: .subheadline))
            .foregroundStyle(textColor)
            .frame(minWidth: alignsBadges ? modeWidth : nil, alignment: .leading)
        ForEach(group.lines) { line in
            badge(line)
        }
    }

    private func badge(_ line: Transit.Line) -> some View {
        Text(line.name)
            .font(.atkinson(14, .bold, relativeTo: .footnote))
            .monospacedDigit()
            .foregroundStyle(line.textColor.map { Color(hex: $0) } ?? textColor)
            .padding(.horizontal, 6)
            .frame(minWidth: 24, minHeight: 22)
            .background(line.color.map { Color(hex: $0) } ?? badgeColor,
                        in: RoundedRectangle(cornerRadius: 6))
    }
}

/// Lays its views out in a row, wrapping onto the next line when the row is full.
private struct FlowLayout: Layout {
    var spacing: CGFloat
    var lineSpacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(subviews, width: proposal.width ?? .infinity)
        let width = rows.map(\.width).max() ?? 0
        let height = rows.map(\.height).reduce(0, +) + lineSpacing * CGFloat(max(0, rows.count - 1))
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in arrange(subviews, width: bounds.width) {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                // Centred in the row's height, so words and badges line up.
                subviews[index].place(at: CGPoint(x: x, y: y + (row.height - size.height) / 2),
                                      proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.height + lineSpacing
        }
    }

    private struct Row {
        var indices: [Int] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func arrange(_ subviews: Subviews, width: CGFloat) -> [Row] {
        var rows: [Row] = [Row()]
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let extra = rows[rows.count - 1].indices.isEmpty ? size.width : spacing + size.width
            if rows[rows.count - 1].width + extra > width, !rows[rows.count - 1].indices.isEmpty {
                rows.append(Row())
            }
            let isFirst = rows[rows.count - 1].indices.isEmpty
            rows[rows.count - 1].indices.append(index)
            rows[rows.count - 1].width += isFirst ? size.width : spacing + size.width
            rows[rows.count - 1].height = max(rows[rows.count - 1].height, size.height)
        }
        return rows
    }
}
