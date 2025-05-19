//
//  Item.swift
//  foodPlanner
//
//  Created by Roman Bystriakov on 19/5/25.
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
