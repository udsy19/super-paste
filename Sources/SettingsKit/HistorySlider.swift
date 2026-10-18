import AppKit
import SwiftUI
import SuperPasteCore

/// What Keep History reads as: "3 days", "2 weeks", "1 month", "1 year", "Forever" (behaviour.md §2.9).
public enum HistoryLabel {
    public static func text(forDays days: Int) -> String {
        func count(_ n: Int, _ unit: String) -> String { "\(n) \(unit)\(n == 1 ? "" : "s")" }
        switch days {
        case ...0: return Strings.General.forever
        case 1..<7: return count(days, "day")
        case 7..<30: return count(days / 7, "week")
        case 30..<365: return count(days / 30, "month")
        default: return count(days / 365, "year")
        }
    }
}

/// What letting go of the Keep History slider does.
public enum RetentionChange: Equatable {
    case none
    case apply(days: Int)
    /// The new limit is shorter and `count` unpinned items are older than it: ask before deleting them.
    case confirmPrune(days: Int, count: Int)

    /// `prunable` counts the unpinned history items older than a limit (`ItemStoring.prunableCount`).
    public static func evaluate(from old: Int, to new: Int, prunable: (Int) -> Int) -> RetentionChange {
        guard new != old else { return .none }
        let shorter = new > 0 && (old <= 0 || new < old)
        if shorter {
            let count = prunable(new)
            if count > 0 { return .confirmPrune(days: new, count: count) }
        }
        return .apply(days: new)
    }
}

/// The Keep History slider: 1…5 with a tick at each whole number and the current value as text. Lowering the limit
/// below items that exist asks before deleting them; Forever shows the disk-space hint.
struct HistorySlider: View {
    @Default(.historyRetentionDays) private var days
    /// The slider position while dragging; nil shows the stored value.
    @State private var dragging: Double?

    var body: some View {
        let shown = dragging.map(HistoryRetention.days(forSlider:)) ?? days
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Spacer()
                if shown == HistoryRetention.forever {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.yellow)
                        .help(Strings.General.unlimitedTooltip)
                }
                Text(HistoryLabel.text(forDays: shown))
                    .font(.sp(.callout)).foregroundStyle(.secondary).monospacedDigit()
            }
            TickSlider(value: dragging ?? HistoryRetention.sliderValue(forDays: days),
                       range: HistoryRetention.sliderRange, ticks: 5,
                       onChange: { dragging = $0 }, onCommit: commit)
        }
    }

    private func commit(_ value: Double) {
        let change = RetentionChange.evaluate(from: days, to: HistoryRetention.days(forSlider: value)) { limit in
            Services.store?.prunableCount(retentionDays: limit, now: Date()) ?? 0
        }
        switch change {
        case .none: break
        case .apply(let new): days = new
        case .confirmPrune(let new, _):
            if Alerts.confirm(Strings.General.reduceTitle, info: Strings.General.eraseText,
                              confirmTitle: Strings.Action.delete, destructive: true) {
                days = new
                do { try Services.store?.prune(retentionDays: new, now: Date()) } catch {
                    Alerts.error(Strings.General.reduceTitle, error)
                }
            }
        }
        dragging = nil
    }
}

/// An `NSSlider` with tick marks (SwiftUI's continuous slider has none on macOS 14). `onChange` follows the knob;
/// `onCommit` fires when the mouse goes up or a key moved it.
struct TickSlider: NSViewRepresentable {
    var value: Double
    var range: ClosedRange<Double>
    var ticks: Int
    var onChange: (Double) -> Void
    var onCommit: (Double) -> Void

    func makeNSView(context: Context) -> NSSlider {
        let slider = NSSlider(value: value, minValue: range.lowerBound, maxValue: range.upperBound,
                              target: context.coordinator, action: #selector(Coordinator.moved(_:)))
        slider.numberOfTickMarks = ticks
        slider.tickMarkPosition = .below
        slider.allowsTickMarkValuesOnly = false
        slider.isContinuous = true
        slider.controlSize = .small
        return slider
    }

    func updateNSView(_ slider: NSSlider, context: Context) {
        context.coordinator.parent = self
        if slider.doubleValue != value { slider.doubleValue = value }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    @MainActor final class Coordinator: NSObject {
        var parent: TickSlider
        init(_ parent: TickSlider) { self.parent = parent }

        @objc func moved(_ slider: NSSlider) {
            let dragging = NSApp.currentEvent.map { $0.type == .leftMouseDragged || $0.type == .leftMouseDown } ?? false
            if dragging {
                parent.onChange(slider.doubleValue)
            } else {
                parent.onCommit(slider.doubleValue)
            }
        }
    }
}
