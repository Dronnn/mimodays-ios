//
//  Item.swift
//  MimoDays
//
//  Created by andreas maier on 11.11.2026.
//

import Foundation
import SwiftData

@Model
final class Item {
    var timestamp: Date
    
    init(timestamp: Date) {
        self.timestamp = timestamp
    }
}
