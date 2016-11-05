//
//  File.swift
//  Zipper
//
//  Created by Clément Nonn on 04/11/2016.
//  Copyright © 2016 Clément Nonn. All rights reserved.
//

import Foundation

// TODO: dont forget to check bitwise operator java and swift
public struct CRC32: Checksum {
    // The following logic has come from RFC1952.
    private var v = 0
    static let crcTable: [Int] = {
        var table = [Int]()
        for n in 0..<256 {
            var c = n
            for _ in 0..<8 {
                if (c & 1) != 0 {
                    c = 0xedb88320 ^ (c >> 1)
                } else {
                    c = c >> 1
                }
            }
            table[n] = c
        }
        return table
    }()
    
    public mutating func reset() {
        v = 0
    }
    
    public mutating func reset(initValue: Int) {
        v = initValue & 0xffffffff
    }
    
    public mutating func update(buf: [UInt8], index: Int, length: Int) {
        var c = ~v
        for _ in 0..<length {
            let crcTableIndex = (c ^ Int(buf[index])) & 0xff
            c = CRC32.crcTable[crcTableIndex] ^ (c >> 8)
        }
        v = ~c
    }

    func getValue() -> Int {
        return v & 0xffffffff
    }
    
    // The following logic has come from zlib.1.2.
    private static let gf2Dim = 32
    
    static func combine(crc1: Int, crc2: Int, length2: Int) -> Int {
        // degenerate case (also disallow negative lengths)
        guard length2 > 0 else {
            return crc1
        }
        
        var odd = [Int]()
        // put operator for one zero bit in odd
        odd[0] = 0xedb88320 // CRC-32 polynomial
        
        var row = 1
        
        for n in 1..<gf2Dim {
            odd[n] = row
            row <<= 1
        }
        
        // put operator for two zero bits in even
        var even = gf2_matrix_square(mat: odd)

        // put operator for four zero bits in odd
        odd = gf2_matrix_square(mat: even)

        // apply len2 zeros to crc1 (first square will put the operator for one
        // zero byte, eight zero bits, in even)
        var length2 = length2
        var crc1 = crc1
        repeat {
            // apply zeros operator for this bit of len2
            even = gf2_matrix_square(mat: odd)
            if length2 & 1 != 0 {
                crc1 = gf2_matrix_times(mat: even, vec: crc1)
            }
            length2 >>= 1

//          if no more bits set, then done
            if length2 == 0 {
                break
            }
//          another iteration of the loop with odd and even swapped
            odd = gf2_matrix_square(mat: even)
            if length2 & 1 != 0 {
                crc1 = gf2_matrix_times(mat: odd, vec: crc1)
            }
            length2 >>= 1
            // if no more bits set, then done
        } while length2 != 0
        
        /* return combined crc */
        return crc1 ^ crc2
        
    }
    
    private static func gf2_matrix_times(mat: [Int], vec: Int) -> Int {
        var sum = 0
        var index = 0
        var decrement = vec
        
        while decrement != 0 {
            if vec & 1 != 0 {
                sum ^= mat[index]
                decrement >>= 1
                index += 1
            }
        }
        return sum;
    }
    
    private static func gf2_matrix_square(mat: [Int]) -> [Int] {
        var result = [Int](repeating: 0, count: gf2Dim)
        for n in 0..<gf2Dim {
            result[n] = gf2_matrix_times(mat: mat, vec: mat[n])
        }
        return result
    }
    
    
}
