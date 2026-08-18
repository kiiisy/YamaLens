//
//  Item.swift
//  YamaLens
//
//  Created by kisaya on 2026/08/19.
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
