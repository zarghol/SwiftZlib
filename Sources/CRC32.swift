//
//  File.swift
//  Zipper
//
//  Created by Clément Nonn on 04/11/2016.
//  Copyright © 2016 Clément Nonn. All rights reserved.
//

import Foundation

public struct CRC32: Checksum {
    private static let gf2Dim = 32
    
    public static let crcTable: [UInt32] = {
        var table = [UInt32]()
        for n in 0..<256 {
            var c = UInt32(n)
            for _ in 0..<8 {
                if (c & 1) != 0 {
                    c = 0xedb88320 ^ (c >> 1)
                } else {
                    c = c >> 1
                }
            }
            table.append(c)
        }
        return table
    }()
    
    
    public func compute(value: UInt32, buffer: [UInt8]) -> UInt32 {
        var crc = ~value
        for index in 0..<buffer.count {
            let crcTableIndex = Int((crc ^ UInt32(buffer[index])) & 0xff)
            crc = CRC32.crcTable[crcTableIndex] ^ (crc >> 8)
        }
        return ~crc
    }
    
    private static func gf2_matrix_times(matrix: [UInt32], vector: UInt32) -> UInt32 {
        var sum: UInt32 = 0
        var index = 0
        var parcours = vector
        
        while parcours > 0 {
            // si le bit courant est 1
            if parcours & 1 != 0 {
                sum ^= matrix[index]
            }
            index += 1
            parcours >>= 1
        }
        return sum
    }
    
    private static func gf2_matrix_square(square: [UInt32]) -> [UInt32] {
        var result = [UInt32]()
        for n in 0..<CRC32.gf2Dim {
            result.append(gf2_matrix_times(matrix: square, vector: square[n]))
        }
        return result
    }
    
    public func combine(value1: UInt32, value2: UInt32, length: UInt32) -> UInt32 {
        var odd = [UInt32]()
        var even = [UInt32]()
        
        odd[0] = 0xedb88320
        
        var row: UInt32 = 1
        for _ in 1..<CRC32.gf2Dim {
            odd.append(row)
            row <<= 1
        }
        
        /* put operator for two zero bits in even */
        even = CRC32.gf2_matrix_square(square: odd)
        
        /* put operator for four zero bits in odd */
        odd = CRC32.gf2_matrix_square(square: even)
        
        /* apply len2 zeros to crc1 (first square will put the operator for one
         zero byte, eight zero bits, in even) */
        
        var parcours = length
        var crc1 = value1
        repeat {
            /* apply zeros operator for this bit of len2 */
            even = CRC32.gf2_matrix_square(square: odd)
            if parcours & 1 != 0 {
                crc1 = CRC32.gf2_matrix_times(matrix: even, vector: crc1)
            }
            
            parcours >>= 1
            
            /* if no more bits set, then done */
            if (parcours == 0) {
                break
            }
            
            /* another iteration of the loop with odd and even swapped */
            odd = CRC32.gf2_matrix_square(square: even)
            if parcours & 1 != 0 {
                crc1 = CRC32.gf2_matrix_times(matrix: odd, vector: crc1)
            }
            parcours >>= 1
            
            /* if no more bits set, then done */
        } while parcours > 0
        
        return crc1 ^ value2
    }
}
