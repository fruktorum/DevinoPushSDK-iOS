//
//  String.swift
//  DevinoSDK
//
//  Created by Maria on 17.10.2019.
//  Copyright © 2019 Devino. All rights reserved.
//

import Foundation

extension String {
    func convert() -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSZ"
        if let date = dateFormatter.date(from: self) {
            dateFormatter.dateFormat = "dd.MM.yy hh:mm:ss"
            return dateFormatter.string(from: date)
        } else {
            return "01.01.2000 12:12:12"
        }
    }
}
