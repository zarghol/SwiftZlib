//
//  Checksum.swift
//  Zipper
//
//  Created by Clément Nonn on 04/11/2016.
//  Copyright © 2016 Clément Nonn. All rights reserved.
//

import Foundation

protocol Checksum {
    mutating func update(buf: [UInt8], index: Int, length: Int)
    mutating func reset()
    mutating func reset(initValue: Int)
    mutating func getValue() -> Int
}
