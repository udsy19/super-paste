import Foundation

/// The Keep History slider and its days (behaviour.md §2.9). The slider runs 1…5 with a stop at each whole number:
///
/// | slider `v`  | days stored                                              | reads as      |
/// |-------------|----------------------------------------------------------|---------------|
/// | 1 ≤ v < 2   | round((v−1)·6 + 1) → 1…7                                 | 1–6 days      |
/// | 2 ≤ v < 3   | round((v−2)·3 + 1)·7 → 7…28, above 27 snaps to 30        | 1–3 weeks     |
/// | 3 ≤ v < 4   | round((v−3)·11 + 1)·30 → 30…360, above 345 snaps to 365  | 1–11 months   |
/// | 4 ≤ v < 4.5 | 365                                                      | 1 year        |
/// | v ≥ 4.5     | 0                                                        | Forever       |
///
/// The spec gives only v = 4 → 365 and v = 5 → Forever; the 4…5 segment splits at its midpoint.
public enum HistoryRetention {
    public static let sliderRange: ClosedRange<Double> = 1...5
    /// The stored value for "Forever".
    public static let forever = 0

    public static func days(forSlider value: Double) -> Int {
        let v = min(max(value, sliderRange.lowerBound), sliderRange.upperBound)
        switch v {
        case ..<2: return Int(((v - 1) * 6 + 1).rounded())
        case ..<3:
            let days = Int(((v - 2) * 3 + 1).rounded()) * 7
            return days > 27 ? 30 : days
        case ..<4:
            let days = Int(((v - 3) * 11 + 1).rounded()) * 30
            return days > 345 ? 365 : days
        case ..<4.5: return 365
        default: return forever
        }
    }

    /// Where a stored value sits on the slider (the inverse of `days(forSlider:)` for every value it produces;
    /// other values land between stops).
    public static func sliderValue(forDays days: Int) -> Double {
        switch days {
        case ...0: return 5
        case 1..<7: return 1 + Double(days - 1) / 6
        case 7..<30: return 2 + (Double(days) / 7 - 1) / 3
        case 30..<360: return 3 + (Double(days) / 30 - 1) / 11
        default: return 4
        }
    }

    /// The moment before which unpinned history items are pruned; nil for Forever.
    public static func cutoff(days: Int, now: Date = Date()) -> Date? {
        days <= 0 ? nil : now.addingTimeInterval(-Double(days) * 86_400)
    }
}
