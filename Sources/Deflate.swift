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

enum Status: Int {
    case needMore = 0      // block not completed, need more input or more output
    case blockDone = 1     // block flush performed
    case finishStarted = 2 // finish started, need only more output at next deflate
    case finishDone = 3    // finish done, accept no more input or output
}

enum BlockType {
    case binary
    case ascii
    case unknown
}

enum State: Int {
    case initialisation = 42
    case busy = 113
    case finish = 666
}

enum Flush: Int {
    case no = 0
    case partial = 1
    case sync = 2
    case full = 3
    case finish = 4
}

enum Strategy: Int {
    case defaultStrat = 0
    case filtered = 1
    case huffmanOnly = 2
}

enum Method {
    case stored
    case deflated
}

enum TreeType: Int {
    case storedBlock = 0
    case staticTrees = 1
    case dynamicTrees = 2
}

class Deflate {
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
    
    private static let minMatch = 3
    private static let maxMatch = 258
    private static let minLookAhead = Deflate.minMatch + Deflate.maxMatch + 1
    
    var stream: ZStream        // pointer back to this zlib stream
    var status: State        // as the name implies
    var pendingBuf: [UInt8]  // output still pending
//    int pending_buf_size;  // size of pending_buf
    var pendingOut: Int      // next pending byte to output to the stream
    var pending: Int         // nb of bytes in the pending buffer
    var wrap = 1
    var dataType: BlockType  // UNKNOWN, BINARY or ASCII
    var method: Method       // STORED (for zip only) or DEFLATED
    var lastFlush: Flush     // value of flush param for previous deflate call
    
    var windowSize: Int          // LZ77 window size (32K by default)
    var windowBits: Int          // log2(w_size)  (8..16)
    var windowMask: Int          // w_size - 1

    
    var window: [UInt8]
    // Sliding window. Input bytes are read into the second half of the window,
    // and move to the first half later to keep a dictionary of at least windowSize
    // bytes. With this organization, matches are limited to a distance of
    // windowSize-maxMatch bytes, but this ensures that IO is always
    // performed with a length multiple of the block size. Also, it limits
    // the window size to 64K, which is quite useful on MSDOS.
    // To do: use the user input buffer as sliding window.
    
    var currentWindowSize: Int
    // Actual size of window: 2*wSize, except when the user input buffer
    // is directly used as sliding window.
    
    var prev: [UInt8]
    // Link to older string with same hash index. To limit the size of this
    // array to 64K, this link is maintained only for the last 32K strings.
    // An index in this array is thus a window index modulo 32K.
    
    var head: [Int]? // Heads of the hash chains or NIL.
    
    var ins_h: Int     // hash index of string to be inserted
    var hash_size: Int // number of elements in hash table
    var hash_bits: Int // log2(hash_size)
    var hash_mask: Int // hash_size-1
    
    // Number of bits by which ins_h must be shifted at each input
    // step. It must be such that after MIN_MATCH steps, the oldest
    // byte no longer takes part in the hash key, that is:
    // hash_shift * MIN_MATCH >= hash_bits
    var hash_shift: Int
    
    // Window position at the beginning of the current output block. Gets
    // negative when the window is moved backwards.
    
    var block_start: Int
    
    var match_length: Int     // length of best match
    var prev_match: Int       // previous match
    var match_available: Int  // set if previous match exists
    var strstart: Int         // start of string to insert
    var match_start: Int      // start of matching string
    var lookahead: Int        // number of valid bytes ahead in window
    
    // Length of the best match at previous step. Matches not greater than this
    // are discarded. This is used in the lazy match evaluation.
    var prev_length: Int
    
    // To speed up deflation, hash chains are never searched beyond this
    // length.  A higher limit improves compression ratio but degrades the speed.
    var maxChainLength: Int
    
    // Attempt to find a better match only when the current match is strictly
    // smaller than this value. This mechanism is used only for compression
    // levels >= 4.
    var maxLazyMatch: Int
    
    // Insert new strings in the hash table only if the match length is not
    // greater than this length. This saves time but degrades compression.
    // max_insert_length is used only for compression levels <= 3.
    
    var level: Int    // compression level (1..9)
    var strategy: Int // favor or force Huffman coding
    
    // Use a faster search when the previous match is longer than this
    var goodMatch: Int
    
    // Stop searching when current match exceeds this
    var niceMatch: Int
    
    var dyn_ltree = [Int]() // literal and length tree
    var dyn_dtree = [Int]() // distance tree
    var bl_tree = [Int]()   // Huffman tree for bit lengths
    
    var l_desc  = Tree()  // desc for literal tree
    var d_desc  = Tree()  // desc for distance tree
    var bl_desc = Tree()  // desc for bit length tree
    
    // number of codes at each bit length for an optimal tree
    var bl_count = [Int]()
    // working area to be used in Tree#gen_codes()
    var next_code = [Int]()
    
    // heap used to build the Huffman trees
    var heap = [Int]()
    
//    var int heap_len;  // number of elements in the heap
    var heapMax: Int     // element of largest frequency
    // The sons of heap[n] are heap[2*n] and heap[2*n+1]. heap[0] is not used.
    // The same heap array is used to build all trees.
    
    // Depth of each subtree used as tie breaker for trees of equal frequency
    var depth = [UInt8]()
    
    var l_buf = [Int]() // index for literals or lengths
    
    // Size of match buffer for literals/lengths.  There are 4 reasons for
    // limiting lit_bufsize to 64K:
    //   - frequencies can be kept in 16 bit counters
    //   - if compression is not successful for the first block, all input
    //     data is still in the window so we can still emit a stored block even
    //     when input comes from standard input.  (This can also be done for
    //     all blocks if lit_bufsize is not greater than 32K.)
    //   - if compression is not successful for a file smaller than 64K, we can
    //     even emit a stored file instead of a stored block (saving 5 bytes).
    //     This is applicable only for zip (not gzip or zlib).
    //   - creating new Huffman trees less frequently may not provide fast
    //     adaptation to changes in the input data statistics. (Take for
    //     example a binary file with poorly compressible code followed by
    //     a highly compressible string table.) Smaller buffer sizes give
    //     fast adaptation but have of course the overhead of transmitting
    //     trees more frequently.
    //   - I can't count above 4
    var lit_bufsize: Int
    
    var last_lit: Int     // running index in l_buf
    
    // Buffer for distances. To simplify the code, d_buf and l_buf have
    // the same number of elements. To use different lengths, an extra flag
    // array would be necessary.
    
    var d_buf: Int         // index of pendig_buf
    
    var opt_len: Int        // bit length of current block with optimal trees
    var static_len: Int     // bit length of current block with static trees
    var matches: Int        // number of string matches in current block
    var last_eob_len: Int   // bit length of EOB code for last block
    
    // Output buffer. bits are inserted starting at the bottom (least
    // significant bits).
    var bi_buf: Int
    
    // Number of valid bits in bi_buf.  All bits above the last valid bit
    // are always zero.
    var bi_valid: Int
    
    var gheader: GZIPHeader? = nil
    
    init(stream: ZStream) {
        self.stream = stream
    }
    
    func lmInit() {
        currentWindowSize = 2 * windowSize
        head = [Int](repeating: 0, count: hash_size)
        
        // Set the default configuration parameters:
        maxLazyMatch   = Deflate.configTable[level].maxLazy
        goodMatch      = Deflate.configTable[level].goodLength
        niceMatch      = Deflate.configTable[level].niceLength
        maxChainLength = Deflate.configTable[level].maxChain
        
        strstart = 0
        block_start = 0
        lookahead = 0
        match_length = Deflate.minMatch - 1
        prev_length = Deflate.minMatch - 1
        match_available = 0
        ins_h = 0
    }
    
    // Initialize the tree data structures for a new zlib stream.
    func trInit() {
//        l_desc.dyn_tree = dyn_ltree;
//        l_desc.stat_desc = StaticTree.static_l_desc;
//        
//        d_desc.dyn_tree = dyn_dtree;
//        d_desc.stat_desc = StaticTree.static_d_desc;
//        
//        bl_desc.dyn_tree = bl_tree;
//        bl_desc.stat_desc = StaticTree.static_bl_desc;

        
        bi_buf = 0
        bi_valid = 0
        last_eob_len = 8 // enough lookahead for inflate
        
        initBlock()
    }
    
    func initBlock() {
        // Initialize the trees.
        for i in 0..<Constants.lCodes {
            dyn_ltree[i * 2] = 0
        }
        for i in 0..<Constants.dCodes {
            dyn_dtree[i * 2] = 0
        }
        for i in 0..<Constants.blCodes {
            bl_tree[i * 2] = 0
        }
        
        dyn_ltree[Constants.endBlock * 2] = 1
        opt_len = 0
        static_len = 0
        last_lit = 0
        matches = 0
    }
    
    // Restore the heap property by moving down the tree starting at node k,
    // exchanging a node with the smallest of its two sons if necessary, stopping
    // when the heap property is re-established (each father smaller than its
    // two sons).
    func pqDownHeap(tree: [Int], k: Int) {
        var k = k
        let v = heap[k]
        var j = k << 1  // left son of k
        
        while j <= heap.count {
            // Set j to the smallest of the two sons:
            if j < heap.count && Deflate.isSmaller(tree: tree, n: heap[j + 1], m: heap[j], depth: depth) {
                j += 1
            }
            // Exit if v is smaller than both sons

            if Deflate.isSmaller(tree: tree, n: v, m: heap[j], depth: depth) {
                break
            }
            // Exchange v with the smallest son
            heap[k] = heap[j]
            k = j;
            // And continue down the tree, setting j to the left son of k
            j <<= 1;
        }
        heap[k] = v
    }
    
    static func isSmaller(tree: [Int], n: Int, m: Int, depth: [UInt8]) -> Bool {
        let tn2 = tree[n * 2]
        let tm2 = tree[m * 2]
        return tn2 < tm2 || (tn2 == tm2 && depth[n] <= depth[m])
    }
    
    // Scan a literal or distance tree to determine the frequencies of the codes
    // in the bit length tree.
    func scanTree(tree: [Int], maxCode: Int) -> [Int] {
        var tree = tree
        var previousLength = -1   // last emitted length

        var count = 0;            // repeat count of the current code
        var maxCount: Int         // max repeat count
        var minCount: Int         // min repeat count
        
        var nextLength = tree[1]  // length of next code

        if nextLength == 0 {
            maxCount = 138
            minCount = 3
        } else {
            maxCount = 7
            minCount = 4
        }

        tree[(maxCode + 1) * 2 + 1] = 0xffff; // guard
        
        for n in 0...maxCode {
            let currentLength = nextLength // length of current code
            nextLength = tree[(n + 1) * 2 + 1]
            count += 1
            if count < maxCount && currentLength == nextLength {
                continue
            } else if count < minCount {
                bl_tree[currentLength * 2] += count
            } else if currentLength != 0 {
                if currentLength != previousLength {
                    bl_tree[currentLength * 2] += 1
                }
                bl_tree[Constants.rep_3_6 * 2] += 1
            } else if count <= 10 {
                bl_tree[Constants.repz_3_10 * 2] += 1
            } else {
                bl_tree[Constants.repz_11_138 * 2] += 1
            }
            count = 0
            previousLength = currentLength
            if nextLength == 0 {
                maxCount = 138
                minCount = 3
            } else if currentLength == nextLength {
                maxCount = 6
                minCount = 3
            } else {
                maxCount = 7
                minCount = 4
            }
        }
        
        return tree
    }
    
    // Construct the Huffman tree for the bit lengths and return the index in
    // bl_order of the last bit length code to send.
    func buildBlTree() -> Int {
        var maxBlindexResult = 3 // index of last bit length code of non zero freq
        
        // Determine the bit length frequencies for literal and distance trees
        dyn_ltree = scanTree(tree: dyn_ltree, maxCode: l_desc.maxCode)
        dyn_dtree = scanTree(tree: dyn_dtree, maxCode: l_desc.maxCode)
        
        // Build the bit length tree:
        bl_desc.build_tree(self)
        // opt_len now includes the length of the tree representations, except
        // the lengths of the bit lengths codes and the 5+5+4 bits for the counts.
        
        // Determine the number of bit length codes to send. The pkzip format
        // requires that at least 4 bit length codes be sent. (appnote.txt says
        // 3 but the actual value used is 4.)
        for max_blindex in (3...Constants.blCodes-1).reversed() {
            if bl_tree[Tree.bl_order[max_blindex] * 2 + 1] != 0 {
                maxBlindexResult = max_blindex
                break
            }
        }
        // Update opt_len to include the bit length tree and counts
        opt_len += 3 * (maxBlindexResult + 1) + 5 + 5 + 4
        return maxBlindexResult
    }
   
    // Send the header for a block using dynamic Huffman trees: the counts, the
    // lengths of the bit length codes, the literal tree and the distance tree.
    // IN assertion: lcodes >= 257, dcodes >= 1, blcodes >= 4.
    func sendAllTrees(lCodes: Int, dCodes: Int, blCodes: Int) {
        sendBits(lCodes - 257, 5) // not +255 as stated in appnote.txt
        sendBits(dCodes -   1, 5)
        sendBits(blCodes -  4, 4) // not -3 as stated in appnote.txt
        
        for rank in 0..<blCodes {
            sendBits(bl_tree[Tree.bl_order[rank] * 2 + 1], 3)
        }
        
        sendTree(dyn_ltree, lCodes - 1) // literal tree
        sendTree(dyn_dtree, dCodes - 1) // distance tree
    }
    
    
    func sendTree(tree: [Int], maxCode: Int) {
        var previousLength = -1;          // last emitted length
        
        var count = 0;             // repeat count of the current code
        var maxCount: Int         // max repeat count
        var minCount: Int         // min repeat count
        
        var nextLength = tree[1] // length of next code
        
        if nextLength == 0 {
            maxCount = 138
            minCount = 3
        } else {
            maxCount = 7
            minCount = 4
        }
        
        for n in 0...maxCode {
            let currentLength = nextLength
            nextLength = tree[(n + 1) * 2 + 1]
            count += 1
            if count < maxCount && currentLength == nextLength {
                continue
            } else if count < minCount {
                for _ in 0..<count {
                    sendCode(currentLength, bl_tree)
                }
                count = 0
            } else if currentLength != 0 {
                if currentLength != previousLength {
                    sendCode(currentLength, bl_tree)
                    count -= 1
                }
                sendCode(Constants.rep_3_6, bl_tree)
                sendBits(count - 3, 2)
            } else if count <= 10 {
                sendCode(Constants.repz_3_10, bl_tree)
                sendBits(count - 3, 3)
            } else {
                sendCode(Constants.repz_11_138, bl_tree)
                sendBits(count - 11, 7)
            }
            count = 0
            previousLength = currentLength
            if nextLength == 0 {
                maxCount = 138
                minCount = 3
            } else if currentLength == nextLength {
                maxCount = 6
                minCount = 3
            } else {
                maxCount = 7
                minCount = 4
            }
        }
    }
    
    // Output a byte on the stream.
    // IN assertion: there is enough room in pending_buf.
    func putByte(bytes: [UInt8], start: Int, length: Int) {
        for i in 0..<length {
            let st = start + i
            let st2 = pending + i
            pendingBuf[st2] = bytes[st]
        }
        pending += length
    }
    
    func putByte(byte: UInt8) {
        pendingBuf[pending] = byte
        pending += 1
        
//        pendingBuf.append(byte)
    }
    
    func putInt(w: Int) {
        let byte = UInt8(truncatingBitPattern: w)
        putByte(byte: byte)
        let byte2 = byte >> 8
        putByte(byte: byte2)
    }
    
    func putIntMSB(w: Int) {
        let byte = UInt8(truncatingBitPattern: w)
        let byte2 = byte >> 8
        putByte(byte: byte2)
        putByte(byte: byte)
    }
    
    func sendCode(code: Int, tree: [Int]) {
        let c2 = code * 2
        sendBits(value: tree[c2] & 0xffff, length: tree[c2 + 1] & 0xffff)
    }
    
    func sendBits(value: Int, length: Int) {
        if bi_valid > Constants.Buf_size - length {
            bi_buf |= (value << bi_valid) & 0xffff
            putInt(w: bi_buf)
            bi_buf = value >> (Constants.Buf_size - bi_valid)
            bi_valid += length - Constants.Buf_size
        } else {
            bi_buf |= (value << bi_valid) & 0xffff
            bi_valid += length
        }
    }
    
    // Send one empty static block to give enough lookahead for inflate.
    // This takes 10 bits, of which 7 may remain in the bit buffer.
    // The current inflate code requires 9 bits of lookahead. If the
    // last two codes for the previous block (real code plus EOB) were coded
    // on 5 bits or less, inflate may have only 5+3 bits of lookahead to decode
    // the last real code. In this case we send two empty static blocks instead
    // of one. (There are no problems if the previous block is stored or fixed.)
    // To simplify the code, we assume the worst case of last real code encoded
    // on one bit only.
    func _tr_align() {
        sendBits(value: TreeType.staticTrees.rawValue << 1, length: 3)
        sendCode(code: Constants.endBlock, tree: StaticTree.staticLTree)
        bi_flush()
        
        // Of the 10 bits for the empty block, we have already sent
        // (10 - bi_valid) bits. The lookahead for the last real code (before
        // the EOB of the previous block) was thus at least one plus the length
        // of the EOB plus what we have just sent of the empty static block.
        if 1 + last_eob_len + 10 - bi_valid < 9 {
            sendBits(value: TreeType.staticTrees.rawValue << 1, length: 3)
            sendCode(code: Constants.endBlock, tree: StaticTree.staticLTree)
            bi_flush()
        }
        last_eob_len = 7
    }
    
    
}
