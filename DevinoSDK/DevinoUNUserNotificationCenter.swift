//
//  DevinoUNUserNotificationCenter.swift
//  DevinoSDK
//
//  Created by Герасимов Тимофей Владимирович on 21/10/2019.
//  Copyright © 2019 Devino. All rights reserved.
//


import UIKit
import UserNotifications

open class DevinoUNUserNotificationCenter: UIResponder, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    
    private var actionForDismiss: () -> Void = {}
    private var actionForUrl: (String) -> Void = { _ in }
    private var actionForDefault: () -> Void = {}
    private var actionForCustomDefault: (String) -> Void = { _ in }
    
    open func setActionForUrl(_ actionForUrl: @escaping (String) -> Void) {
        self.actionForUrl = actionForUrl
    }
    
    open func setActionForDismiss(_ actionForDismiss: @escaping () -> Void) {
        self.actionForDismiss = actionForDismiss
    }
    
    open func setActionForDefault(_ actionForDefault: @escaping () -> Void) {
        self.actionForDefault = actionForDefault
    }
    
    open func setActionForCustomDefault(_ actionForCustomDefault: @escaping (String) -> Void) {
        self.actionForCustomDefault = actionForCustomDefault
    }
    
    public func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.alert, .badge, .sound])
    }

    
    public func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        let actionIdentifier = response.actionIdentifier
        /// Identify the action by matching its identifier.
        switch actionIdentifier {
        case UNNotificationDefaultActionIdentifier:
            Devino.shared.trackNotificationResponse(response)
            if let actionButton = response.notification.request.content.userInfo["action"] as? [String: String], let action = actionButton["action"] {
                actionForCustomDefault(action)
            } else {
                actionForDefault()
            }
            print("Action default")
        case UNNotificationDismissActionIdentifier:
            Devino.shared.trackNotificationResponse(response, actionIdentifier)
            actionForDismiss()
            print("Action dismiss")
        default:
            Devino.shared.trackNotificationResponse(response, actionIdentifier)
            actionForUrl(actionIdentifier)
            print("Action = \(actionIdentifier)")
        }
        completionHandler()
    }
}
