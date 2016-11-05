//
//  Constants.swift
//  SwiftZlib
//
//  Created by Clément Nonn on 05/11/2016.
//
//

import Foundation

struct Constants {
    static let maxBits = 15
    static let blCodes = 19
    static let dCodes = 30
    static let literals = 256
    static let lengthCodes = 29
    static let lCodes = Constants.literals + 1 + Constants.lengthCodes
    static let heapSize = 2 * Constants.lCodes + 1
    
    // repeat previous bit length 3-6 times (2 bits of repeat count)
    static let rep_3_6 = 16
    
    // repeat a zero length 3-10 times  (3 bits of repeat count)
    static let repz_3_10 = 17
    
    // repeat a zero length 11-138 times  (7 bits of repeat count)
    static let repz_11_138 = 18
    
    // Bit length codes must not exceed MAX_BL_BITS bits
    static let maxBlBits = 7
    
    // The lengths of the bit length codes are sent in order of decreasing
    // probability, to avoid transmitting the lengths for unused bit
    // length codes.
    
    static let Buf_size = 8 * 2
    
    // end of block literal code
    static let endBlock = 256
}
