//
//  Adler32.swift
//  Zipper
//
//  Created by Clément Nonn on 04/11/2016.
//  Copyright © 2016 Clément Nonn. All rights reserved.
//

import Foundation

public struct Adler32: Checksum {
    static let base: UInt32 = 65521
    static let nmax: UInt32 = 5552
    static let nmax16 = Int(nmax / 16)
    // fast
    private func compute_1(adler: UInt32, byte: UInt8) -> UInt32 {
        var sum2 = (adler >> 16) & 0xffff
        var adl = adler & 0xffff
        
        adl += UInt32(byte)
        if adl >= Adler32.base {
            adl -= Adler32.base
        }
        sum2 += adl
        if sum2 >= Adler32.base {
            sum2 -= Adler32.base
        }
        return adl | (sum2 << 16)
    }
    
    // a little slower due to modulo for sum
    private func compute_16(adler: UInt32, buffer: [UInt8]) -> UInt32 {
        var sum2 = (adler >> 16) & 0xffff
        var adl = adler & 0xffff
        
        for byte in buffer {
            adl += UInt32(byte)
            sum2 += adl
            
        }
        if adl >= Adler32.base {
            adl -= Adler32.base
        }
        sum2 %= Adler32.base
        
        return adl | (sum2 << 16)
    }
    
    // slow due to modulo
    private func compute_x(adler: UInt32, buffer: [UInt8]) -> UInt32 {
        /* split Adler-32 into component sums */
        
        var sum2 = (adler >> 16) & 0xffff
        var adl = adler & 0xffff
        
        let times = buffer.count / Int(Adler32.nmax)
        
        for i in 0..<times {
            let range = i*Adler32.nmax16..<(i+1)*Adler32.nmax16
            for byte in buffer[range] {
                adl += UInt32(byte)
                sum2 += adl
            }
            adl %= Adler32.base
            sum2 %= Adler32.base
        }
        
        // pour les restants
        if buffer.count > times * Int(Adler32.nmax) {
            for byte in buffer[times*Int(Adler32.nmax)..<buffer.endIndex] {
                adl += UInt32(byte)
                sum2 += adl
            }
            adl %= Adler32.base
            sum2 %= Adler32.base
        }
        
        return adl | (sum2 << 16)
    }
    
    public func compute(value: UInt32, buffer: [UInt8]) -> UInt32 {
        
        switch buffer.count {
        case 0:
            return 1
            
        case 1:
            return compute_1(adler: value, byte: buffer[0])
            
        case 2..<16:
            return compute_16(adler: value, buffer: buffer)
            
        default:
            return compute_x(adler: value, buffer: buffer)
        }
    }
    
    public func combine(value1: UInt32, value2: UInt32, length: UInt32) -> UInt32 {
        /* the derivation of this formula is left as an exercise for the reader */
        let rem = length % Adler32.base
        
        var sum1 = value1 & 0xffff
        var sum2 = rem * sum1
        sum2 %= Adler32.base
        
        sum1 += (value2 & 0xffff) + Adler32.base - 1
        sum2 += ((value1 >> 16) & 0xffff) + ((value2 >> 16) & 0xffff) + Adler32.base - rem
        // Do the test twice
        for _ in 0..<2 {
            if sum1 >= Adler32.base {
                sum1 -= Adler32.base
            }
        }
        
        if sum2 >= (Adler32.base << 1) {
            sum2 -= (Adler32.base << 1)
        }
        
        if sum2 >= Adler32.base {
            sum2 -= Adler32.base
        }
        
        return sum1 | (sum2 << 16)
    }
}
