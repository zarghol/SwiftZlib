//
//  Deflate.swift
//  Zipper
//
//  Created by Clément Nonn on 05/11/2016.
//  Copyright © 2016 Clément Nonn. All rights reserved.
//

import Foundation


struct Config {
    var goodLength: Int // reduce lazy search above this match length
    var maxLazy: Int    // do not perform lazy search above this match length
    var niceLength: Int // quit search above this match length
    var maxChain: Int
    var funcVal: Speed
}

enum Speed: Int {
    case stored = 0
    case fast = 1
    case slow = 2
}

enum ZError: Error {
    case needDictionary      // Z_NEED_DICT       2
    case streamEnd           // Z_STREAM_END      1
    case fileError           // Z_ERRNO         (-1)
    case streamError         // Z_STREAM_ERROR  (-2)
    case dataError           // Z_DATA_ERROR    (-3)
    case insufficientMemory  // Z_MEM_ERROR     (-4)
    case bufferError         // Z_BUF_ERROR     (-5)
    case incompatibleVersion // Z_VERSION_ERROR (-6)
    
}

enum State: Int {
    case needMore = 0      // block not completed, need more input or more output
    case blockDone = 1     // block flush performed
    case finishStarted = 2 // finish started, need only more output at next deflate
    case finishDone = 3    // finish done, accept no more input or output
}


struct Deflate {
    private static let maxMemLevel = 9
    
    private static let zDefaultCompression = -1
    
    private static let maxWBits = 15 // 32K LZ77 window
    private static let defMemLevel = 8
    
    
    private static let configTable: [Config] = {
        var table = [Config]()
        table.append(Config(goodLength:  0, maxLazy:   0, niceLength:   0, maxChain:    0, funcVal: .stored))
        table.append(Config(goodLength:  4, maxLazy:   4, niceLength:   8, maxChain:    4, funcVal: .fast))
        table.append(Config(goodLength:  4, maxLazy:   5, niceLength:  16, maxChain:    8, funcVal: .fast))
        table.append(Config(goodLength:  4, maxLazy:   6, niceLength:  32, maxChain:   32, funcVal: .fast))
        
        table.append(Config(goodLength:  4, maxLazy:   4, niceLength:  16, maxChain:   16, funcVal: .slow))
        table.append(Config(goodLength:  8, maxLazy:  16, niceLength:  32, maxChain:   32, funcVal: .slow))
        table.append(Config(goodLength:  8, maxLazy:  16, niceLength: 128, maxChain:  128, funcVal: .slow))
        table.append(Config(goodLength:  8, maxLazy:  32, niceLength: 128, maxChain:  256, funcVal: .slow))
        table.append(Config(goodLength: 32, maxLazy: 128, niceLength: 258, maxChain: 1024, funcVal: .slow))
        table.append(Config(goodLength: 32, maxLazy: 258, niceLength: 258, maxChain: 4096, funcVal: .slow))

        return table
    }()
}
