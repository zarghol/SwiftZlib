//
//  Checksum.swift
//  Zipper
//
//  Created by Clément Nonn on 04/11/2016.
//  Copyright © 2016 Clément Nonn. All rights reserved.
//

import Foundation

public protocol Checksum {
    func compute(value: UInt32, buffer: [UInt8]) -> UInt32
    func combine(value1: UInt32, value2: UInt32, length: UInt32) -> UInt32
}
