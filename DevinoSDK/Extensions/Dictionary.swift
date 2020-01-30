//
//  Dictionary.swift
//  DevinoSDK
//
//  Created by Maria on 16.10.2019.
//  Copyright © 2019 Devino. All rights reserved.
//

import Foundation

extension Dictionary where Key: ExpressibleByStringLiteral, Value: Any  {
    func string(_ key: Key) -> String? {
        guard let val = self[key] as? String else { return nil }
        return val
    }
}
