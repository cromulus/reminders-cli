import EventKit
import Foundation
import MCP

public final class ReminderResourceNotifier {
    private let reminders: Reminders
    private let server: Server
    private let verbose: Bool

    private var calendarsSnapshot: Set<String>
    private var observer: NSObjectProtocol?
    private let debounceQueue = DispatchQueue(label: "com.reminders.mcp.resource-updates")
    private var pendingWorkItem: DispatchWorkItem?

    init(reminders: Reminders, server: Server, verbose: Bool) {
        self.reminders = reminders
        self.server = server
        self.verbose = verbose
        self.calendarsSnapshot = Set(reminders.getCalendars().map { $0.calendarIdentifier })

        observer = NotificationCenter.default.addObserver(
            forName: NSNotification.Name.EKEventStoreChanged,
            object: reminders.store,
            queue: nil
        ) { [weak self] _ in
            self?.scheduleNotificationEmission()
        }
    }

    deinit {
        stop()
    }

    public func stop() {
        if let observer {
            NotificationCenter.default.removeObserver(observer)
        }
        observer = nil
        pendingWorkItem?.cancel()
        pendingWorkItem = nil
    }

    private func scheduleNotificationEmission() {
        debounceQueue.async {
            self.pendingWorkItem?.cancel()
            let workItem = DispatchWorkItem { [weak self] in
                Task { await self?.emitNotifications() }
            }
            self.pendingWorkItem = workItem
            self.debounceQueue.asyncAfter(deadline: .now() + .milliseconds(250), execute: workItem)
        }
    }

    private func emitNotifications() async {
        let calendars = reminders.getCalendars()
        let identifiers = Set(calendars.map { $0.calendarIdentifier })
        let listChanged = identifiers != calendarsSnapshot
        calendarsSnapshot = identifiers

        if listChanged {
            log("Lists changed; notifying subscribers")
            do {
                try await server.notify(ResourceListChangedNotification.message())
            } catch {
                log("Failed to notify list change: \(error)")
            }
        }

        await notifyUpdated(uri: "reminders://lists")

        for calendar in calendars {
            let uri = "reminders://list/\(calendar.calendarIdentifier)"
            await notifyUpdated(uri: uri)
        }
    }

    private func notifyUpdated(uri: String) async {
        do {
            try await server.notify(
                ResourceUpdatedNotification.message(.init(uri: uri))
            )
            log("Sent resource update for \(uri)")
        } catch {
            log("Failed to send resource update for \(uri): \(error)")
        }
    }

    private func log(_ message: String) {
        guard verbose else { return }
        fputs("[ReminderResourceNotifier] \(message)\n", stderr)
    }
}
