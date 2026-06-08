//
// NotificationService.swift
// schat
//
// This is free and unencumbered software released into the public domain.
// For more information, see <https://unlicense.org>
//

import Foundation
import UserNotifications
#if os(iOS)
@preconcurrency import UIKit
#elseif os(macOS)
@preconcurrency import AppKit
#endif

class NotificationService {
    nonisolated(unsafe) static let shared = NotificationService()
    
    private init() {}
    
    func requestAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
            if granted {
                // Permission granted
            }
        }
    }
    
    @MainActor func sendLocalNotification(title: String, body: String, identifier: String) {
        // Check if app is in foreground
        #if os(iOS)
        guard UIApplication.shared.applicationState != .active else {
            // App is active/foreground, skipping notification
            return
        }
        // App state checked, sending notification
        #elseif os(macOS)
        // On macOS, check if app is active
        guard !NSApplication.shared.isActive else {
            // App is active/foreground, skipping notification
            return
        }
        // App is not active, sending notification
        #endif
        
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        
        let request = UNNotificationRequest(
            identifier: identifier,
            content: content,
            trigger: nil // Deliver immediately
        )
        
        UNUserNotificationCenter.current().add(request) { _ in
            // Notification added
        }
    }
    
    @MainActor func sendMentionNotification(from sender: String, message: String) {
        let title = "＠🫵 you were mentioned by \(sender)"
        let body = message
        let identifier = "mention-\(UUID().uuidString)"
        
        sendLocalNotification(title: title, body: body, identifier: identifier)
    }
    
    @MainActor func sendPrivateMessageNotification(from sender: String, message: String) {
        let title = "🔒 private message from \(sender)"
        let body = message
        let identifier = "private-\(UUID().uuidString)"
        
        sendLocalNotification(title: title, body: body, identifier: identifier)
    }
    
    @MainActor func sendFavoriteOnlineNotification(nickname: String) {
        let title = "⭐ \(nickname) is online"
        let body = "wanna get in there?"
        let identifier = "favorite-online-\(UUID().uuidString)"
        
        sendLocalNotification(title: title, body: body, identifier: identifier)
    }
}

