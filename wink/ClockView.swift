//
//  ClockView.swift
//  wink
//

import SwiftUI

/// The current time with the AM/PM label on the same baseline. Updates every second.
struct ClockLabel: View {
    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let clock = ClockText(date: context.date)

            HStack(alignment: .firstTextBaseline, spacing: pt(8)) {
                Text(clock.time)
                    .font(.wink(72))
                    .tracking(pt(-1.5))
                    .monospacedDigit()
                    .foregroundStyle(WinkTheme.primaryText)

                if !clock.period.isEmpty {
                    Text(clock.period)
                        .font(.wink(20))
                        .foregroundStyle(WinkTheme.secondaryText)
                }
            }
        }
    }
}

/// Hours and minutes with no leading zero, plus the AM/PM symbol (empty in 24-hour locales).
struct ClockText {
    let time: String
    let period: String

    init(date: Date, locale: Locale = .current, calendar: Calendar = .current) {
        let hour = calendar.component(.hour, from: date)
        let minute = calendar.component(.minute, from: date)
        let minuteText = minute < 10 ? "0\(minute)" : "\(minute)"

        switch locale.hourCycle {
        case .zeroToEleven, .oneToTwelve:
            let twelveHour = hour % 12 == 0 ? 12 : hour % 12
            time = "\(twelveHour):\(minuteText)"
            period = hour < 12 ? calendar.amSymbol : calendar.pmSymbol
        default:
            time = "\(hour):\(minuteText)"
            period = ""
        }
    }
}

#Preview {
    ClockLabel()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.black)
}
