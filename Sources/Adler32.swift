//
//  Adler32.swift
//  Zipper
//
//  Created by Clément Nonn on 04/11/2016.
//  Copyright © 2016 Clément Nonn. All rights reserved.
//

import Foundation

public struct Adler32: Checksum {
    // largest prime smaller than 65536
    private static let base = 65521
    // NMAX is the largest n such that 255n(n+1)/2 + (n+1)(BASE-1) <= 2^32-1
    private static let nmax = 5552
    
    private var s1 = 1; // 1L
    private var s2 = 0 // 0L
    
    mutating func reset(initValue: Int) {
        s1 = initValue & 0xffff
        s2 = (initValue >> 16) & 0xffff
    }
    
    mutating func reset() {
        s1 = 1
        s2 = 0
    }
    
    func getValue() -> Int {
        return (s2 << 16) | s1
    }
    
    mutating func update(buf: [UInt8], index: Int, length: Int) {
        if length == 1 {
            s1 += Int(buf[index]) & 0xff // index++
            s2 += s1
            s1 %= Adler32.base
            s2 %= Adler32.base
            return
        }
        
        let length1 = length / Adler32.nmax
        let length2 = length % Adler32.nmax
        
        var index = index
        var length = length
        
        for _ in 0..<length1 {
            length -= Adler32.nmax
            
            for _ in 0..<Adler32.nmax {
                s1 += Int(buf[index]) & 0xff
                s2 += s1
                index += 1
            }
            s1 %= Adler32.base
            s2 %= Adler32.base
        }
        
        length -= length2
        for _ in 0..<length2 {
            s1 += Int(buf[index]) & 0xff
            s2 += s1
            index += 1
        }
        s1 %= Adler32.base
        s2 %= Adler32.base
    }
    
    // Logic for zlib1.2
    static func combine(adler1: Int, adler2: Int, length2: Int) -> Int {

        let rem = length2 % Adler32.base
        var sum1 = adler1 & 0xffff
        var sum2 = rem * sum1
        sum2 %= Adler32.base
        sum1 += (adler2 & 0xffff) + Adler32.base - 1
        sum2 += ((adler1 >> 16) & 0xffff) + ((adler2 >> 16) & 0xffff) + Adler32.base - rem
        for _ in 0..<2 {
            if sum1 >= Adler32.base {
                sum1 -= Adler32.base
            }
        }
        if sum2 >= (Adler32.base << 1) {
            sum2 -= Adler32.base << 1
        }
        if sum2 >= Adler32.base {
            sum2 -= Adler32.base
        }
        return sum1 | (sum2 << 16)
    }
}
