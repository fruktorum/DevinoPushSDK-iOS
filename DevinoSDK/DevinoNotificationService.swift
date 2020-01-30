//
//  DevinoNotificationService.swift
//  DevinoSDK
//
//  Created by Герасимов Тимофей Владимирович on 21/10/2019.
//  Copyright © 2019 Devino. All rights reserved.
//

import UserNotifications

open class DevinoNotificationService: UNNotificationServiceExtension {

    private var contentHandler: ((UNNotificationContent) -> Void)?
    private var bestAttemptContent: UNMutableNotificationContent?

    override open func didReceive(_ request: UNNotificationRequest, withContentHandler contentHandler: @escaping (UNNotificationContent) -> Void) {
        self.contentHandler = contentHandler
        bestAttemptContent = (request.content.mutableCopy() as? UNMutableNotificationContent)
        defer {
            contentHandler(bestAttemptContent ?? request.content)
        }

        guard let attachment = request.attachment else { return }

        bestAttemptContent?.attachments = [attachment]
    }
    
    override open func serviceExtensionTimeWillExpire() {
        // Called just before the extension will be terminated by the system.
        // Use this as an opportunity to deliver your "best attempt" at modified content, otherwise the original push payload will be used.
        if let contentHandler = contentHandler, let bestAttemptContent = bestAttemptContent {
            contentHandler(bestAttemptContent)
        }
    }
}

extension UNNotificationRequest {
    var attachment: UNNotificationAttachment? {
        guard let attachmentURL = content.userInfo["linkToMedia"] as? String, let imageData = try? Data(contentsOf: URL(string: attachmentURL)!) else {
            return nil
        }
        let format = getFormat(url: attachmentURL)
            return try? UNNotificationAttachment(data: imageData, options: nil, format: format)
        }
        
        private func getFormat(url: String) -> String {
            let formats = [".aiff", ".wav", ".mp3", ".m4a", ".jpg", ".jpeg", ".gif", ".png", ".mpg", ".mpeg", ".mpeg2", ".mp4", ".avi"]
            var format = ".jpg"
            let suffixUrl = url.suffix(5)
            formats.forEach{ formatName in
                if suffixUrl.contains(formatName) {
                    format = formatName
                }
            }
            return format
        }
}

extension UNNotificationAttachment {

    convenience init(data: Data, options: [AnyHashable: Any]?, format: String) throws {
        let fileManager = FileManager.default
        let temporaryFolderName = ProcessInfo.processInfo.globallyUniqueString
        let temporaryFolderURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(temporaryFolderName, isDirectory: true)
        try fileManager.createDirectory(at: temporaryFolderURL, withIntermediateDirectories: true, attributes: nil)
        let imageFileIdentifier = UUID().uuidString + format
        let fileURL = temporaryFolderURL.appendingPathComponent(imageFileIdentifier)
        try data.write(to: fileURL)
        try self.init(identifier: imageFileIdentifier, url: fileURL, options: options)
    }
}
