//
//  Date.swift
//  DevinoSDK
//
//  Created by Maria on 16.10.2019.
//  Copyright © 2019 Devino. All rights reserved.
//

import Foundation

extension Date {
    static func ISOStringFromDate(date: Date) -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSS"
        dateFormatter.timeZone = TimeZone(abbreviation: "UTC")
        return dateFormatter.string(from: date).appending("Z")
    }
    
    static func getLogTime() -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "dd.MM.yy - HH:mm:ss"//"HH:mm:ss"
        dateFormatter.timeZone = TimeZone.current// (abbreviation: "UTC")
        return dateFormatter.string(from: Date())
    }
}
