//
//  CalendarApplet.swift
//  wink
//

import EventKit
import SwiftUI

/// The rest of today's events from all calendars.
@Observable
final class CalendarModel {
    nonisolated struct Event: Identifiable, Sendable {
        let id: String
        let title: String
        let start: Date
        let isAllDay: Bool
    }

    enum State {
        case loading
        case needsPermission
        case denied
        case loaded([Event])
    }

    private(set) var state: State = .loading
    private let store = EKEventStore()

    /// Shows the system prompt. Only call this after the user taps, since the case hides the prompt.
    func requestAccess() async {
        _ = try? await store.requestFullAccessToEvents()
        load()
    }

    func load() {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .notDetermined:
            state = .needsPermission
            return
        case .fullAccess:
            break
        default:
            state = .denied
            return
        }
        let now = Date.now
        let calendar = Calendar.current
        guard let endOfDay = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) else { return }

        // Events that end after now, so ones in progress still show.
        let predicate = store.predicateForEvents(withStart: now, end: endOfDay, calendars: nil)
        let events = store.events(matching: predicate)
            .sorted { $0.startDate < $1.startDate }
            .map { event in
                Event(
                    id: "\(event.calendarItemIdentifier)-\(event.startDate.timeIntervalSince1970)",
                    title: event.title ?? "",
                    start: event.startDate,
                    isAllDay: event.isAllDay
                )
            }
        state = .loaded(events)
    }
}

struct CalendarApplet: View {
    @State private var calendar = CalendarModel()

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.top, WinkLayout.islandClearance)
            .padding(.bottom, WinkLayout.bottomInset)
            .onAppear { calendar.load() }
    }

    @ViewBuilder
    private var content: some View {
        switch calendar.state {
        case .loading:
            ProgressView()
                .tint(WinkTheme.primaryText)
        case .needsPermission:
            PermissionPrompt(title: "Allow calendar access") {
                await calendar.requestAccess()
            }
        case .denied:
            message("Allow calendar access in Settings")
        case .loaded(let events) where events.isEmpty:
            message("Nothing else today")
        case .loaded(let events):
            ScrollView {
                VStack(alignment: .leading, spacing: pt(20)) {
                    ForEach(events) { event in
                        EventRow(event: event)
                    }
                }
                .padding(.horizontal, pt(44))
                .padding(.vertical, pt(12))
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollIndicators(.hidden)
        }
    }

    private func message(_ text: LocalizedStringKey) -> some View {
        Text(text)
            .font(.wink(26))
            .multilineTextAlignment(.center)
            .foregroundStyle(WinkTheme.secondaryText)
            .padding(.horizontal, pt(40))
    }
}

private struct EventRow: View {
    let event: CalendarModel.Event

    var body: some View {
        VStack(alignment: .leading, spacing: pt(2)) {
            Group {
                if event.isAllDay {
                    Text("All day")
                } else {
                    Text(event.start, format: .dateTime.hour().minute())
                }
            }
            .font(.wink(22, weight: .medium))
            .monospacedDigit()
            .foregroundStyle(WinkTheme.secondaryText)

            Text(event.title)
                .font(.wink(32))
                .foregroundStyle(WinkTheme.primaryText)
                .lineLimit(2)
        }
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    WindowPreview {
        CalendarApplet()
    }
}
