//
//  RemindersApplet.swift
//  wink
//

import EventKit
import SwiftUI

/// Incomplete reminders due today or overdue, matching the Reminders app's Today list.
@Observable
final class RemindersModel {
    nonisolated struct Reminder: Identifiable, Sendable {
        let id: String
        let title: String
    }

    enum State {
        case loading
        case needsPermission
        case denied
        case loaded
    }

    private(set) var state: State = .loading
    private(set) var reminders: [Reminder] = []
    private let store = EKEventStore()

    /// Shows the system prompt. Only call this after the user taps, since the case hides the prompt.
    func requestAccess() async {
        _ = try? await store.requestFullAccessToReminders()
        await load()
    }

    func load() async {
        switch EKEventStore.authorizationStatus(for: .reminder) {
        case .notDetermined:
            state = .needsPermission
            return
        case .fullAccess:
            break
        default:
            state = .denied
            return
        }
        let calendar = Calendar.current
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: .now))
        let predicate = store.predicateForIncompleteReminders(withDueDateStarting: nil, ending: endOfDay, calendars: nil)
        reminders = await Self.fetch(from: store, matching: predicate)
        state = .loaded
    }

    /// Marks a reminder done in the user's Reminders and drops it from the list.
    func complete(_ reminder: Reminder) {
        if let item = store.calendarItem(withIdentifier: reminder.id) as? EKReminder {
            item.isCompleted = true
            try? store.save(item, commit: true)
        }
        withAnimation(.smooth) {
            reminders.removeAll { $0.id == reminder.id }
        }
    }

    /// EventKit calls back on its own queue, so convert to plain values there.
    private nonisolated static func fetch(from store: EKEventStore, matching predicate: NSPredicate) async -> [Reminder] {
        await withCheckedContinuation { continuation in
            store.fetchReminders(matching: predicate) { items in
                let reminders = (items ?? []).map { Reminder(id: $0.calendarItemIdentifier, title: $0.title ?? "") }
                continuation.resume(returning: reminders)
            }
        }
    }
}

struct RemindersApplet: View {
    @State private var model = RemindersModel()
    /// Reminders that were just tapped, shown ticked for a moment before they disappear.
    @State private var ticked: Set<String> = []

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.top, WinkLayout.islandClearance)
            .padding(.bottom, WinkLayout.bottomInset)
            .task { await model.load() }
    }

    @ViewBuilder
    private var content: some View {
        switch model.state {
        case .loading:
            ProgressView()
                .tint(WinkTheme.primaryText)
        case .needsPermission:
            PermissionPrompt(title: "Allow reminders access") {
                await model.requestAccess()
            }
        case .denied:
            message("Allow reminders access in Settings")
        case .loaded where model.reminders.isEmpty:
            message("All done for today")
        case .loaded:
            ScrollView {
                VStack(alignment: .leading, spacing: pt(18)) {
                    ForEach(model.reminders) { reminder in
                        row(reminder)
                    }
                }
                .padding(.horizontal, pt(40))
                .padding(.vertical, pt(12))
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollIndicators(.hidden)
        }
    }

    private func row(_ reminder: RemindersModel.Reminder) -> some View {
        let isTicked = ticked.contains(reminder.id)

        return Button {
            tick(reminder)
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: pt(16)) {
                Image(systemName: isTicked ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: pt(30), weight: .regular))
                    .foregroundStyle(isTicked ? WinkTheme.primaryText : WinkTheme.secondaryText)
                Text(reminder.title)
                    .font(.wink(30))
                    .foregroundStyle(isTicked ? WinkTheme.secondaryText : WinkTheme.primaryText)
                    .strikethrough(isTicked)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(NoHighlightButtonStyle())
        .disabled(isTicked)
        .accessibilityLabel(reminder.title)
        .accessibilityHint("Marks as done")
    }

    private func tick(_ reminder: RemindersModel.Reminder) {
        withAnimation(.smooth(duration: 0.2)) { _ = ticked.insert(reminder.id) }
        Task {
            try? await Task.sleep(for: .milliseconds(500))
            model.complete(reminder)
            ticked.remove(reminder.id)
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

#Preview {
    WindowPreview {
        RemindersApplet()
    }
}
