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

enum Method: Int {
    case stored = 0
    case deflated = 8
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
    
    private static let presetDict = 0x20
    
    
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
    
    var stream: ZStream?        // pointer back to this zlib stream
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
    
    var head: [Int] // Heads of the hash chains or NIL.
    
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
    var strategy: Strategy // favor or force Huffman coding
    
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
    var blCount = [Int]()
    // working area to be used in Tree#gen_codes()
    var nextCode = [Int]()
    
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
    
    var optLength: Int        // bit length of current block with optimal trees
    var staticLength: Int     // bit length of current block with static trees
    var matches: Int        // number of string matches in current block
    var last_eob_len: Int   // bit length of EOB code for last block
    
    // Output buffer. bits are inserted starting at the bottom (least
    // significant bits).
    var bi_buf: Int
    
    // Number of valid bits in bi_buf.  All bits above the last valid bit
    // are always zero.
    var bi_valid: Int
    
    lazy var gheader: GZIPHeader = GZIPHeader()
    
    
    convenience init(stream: ZStream? = nil, level: Int, bits: Int = Deflate.maxWBits, memlevel: Int = Deflate.defMemLevel) throws {
        try self.init(stream: stream, level: level, method: Method.deflated, windowBits: bits, memLevel: memlevel, strategy: Strategy.defaultStrat)
    }
    
    private init(stream: ZStream?, level: Int, method: Method, windowBits: Int, memLevel: Int, strategy: Strategy) throws {
        var wrap = 1
        stream.msg = nil

        self.stream = stream
        //    byte[] my_version=ZLIB_VERSION;
        
        //
        //  if (version == null || version[0] != my_version[0]
        //  || stream_size != sizeof(z_stream)) {
        //  return Z_VERSION_ERROR;
        //  }
        
        
        if level == Deflate.zDefaultCompression {
            self.level = 6
        } else {
            self.level = level
        }
        
        if windowBits < 0 { // undocumented feature: suppress zlib header
            wrap = 0
            self.windowBits = -windowBits
        } else if windowBits > 15 {
            wrap = 2
            self.windowBits -= 16
            stream.adler = CRC32()
        }
        
        // check MemLevel
        guard memLevel > 0 && memLevel < Deflate.maxMemLevel else {
            throw ZError.streamError
        }
        // check method ????
        guard method == .deflated else {
            throw ZError.streamError
        }
        // check windowBits
        guard windowBits > 8 && windowBits < 16 else {
            throw ZError.streamError
        }
        // check level
        guard level >= 0 && level < 10 else {
            throw ZError.streamError
        }
        
        stream.dstate = self
        
        self.wrap = wrap
        self.windowSize = 1 << windowBits
        self.windowMask = self.windowSize - 1
        
        hash_bits = memLevel + 7
        hash_size = 1 << hash_bits
        hash_mask = hash_size - 1
        hash_shift = (hash_bits + Deflate.minMatch - 1) / Deflate.minMatch
        
        window = [UInt8]() // size : windowSize * 2
        prev = [UInt8]() // size : windowSize
        head = [Int]() // size: hash_size
        
        lit_bufsize = 1 << (memLevel + 6) // 16K elements by default
        
        // We overlay pending_buf and d_buf+l_buf. This works since the average
        // output size for (length,distance) codes is <= 24 bits.
        pendingBuf =  [UInt8]() // size : lit_bufsize * 3
//        pending_buf_size = lit_bufsize*3;
        
        d_buf = lit_bufsize
        l_buf = [Int]() // size : lit_bufsize
        
        
        self.strategy = strategy
        self.method = method
        
        deflateReset()

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
        // TODO: init Trees
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
        optLength = 0
        staticLength = 0
        last_lit = 0
        matches = 0
    }
    
    func deflateReset() {
        stream.total_out = 0
        stream.total_in  = 0
        stream.msg = nil
        stream.data_type = BlockType.unknown
    
        pending = 0
        pendingOut = 0
    
        if wrap < 0 {
            wrap = -wrap
        }
        status = wrap == 0 ? .busy : .initialisation
        stream.adler.reset()
    
        lastFlush = Flush.no
    
        trInit()
        lmInit()
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
        bl_desc.buildTree(deflate: self)
        // optLength now includes the length of the tree representations, except
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
        // Update optLength to include the bit length tree and counts
        optLength += 3 * (maxBlindexResult + 1) + 5 + 5 + 4
        return maxBlindexResult
    }
   
    // Send the header for a block using dynamic Huffman trees: the counts, the
    // lengths of the bit length codes, the literal tree and the distance tree.
    // IN assertion: lcodes >= 257, dcodes >= 1, blcodes >= 4.
    func sendAllTrees(lCodes: Int, dCodes: Int, blCodes: Int) {
        sendBits(value: lCodes - 257, length: 5) // not +255 as stated in appnote.txt
        sendBits(value: dCodes -   1, length: 5)
        sendBits(value: blCodes -  4, length: 4) // not -3 as stated in appnote.txt
        
        for rank in 0..<blCodes {
            sendBits(value: bl_tree[Tree.bl_order[rank] * 2 + 1], length: 3)
        }
        
        sendTree(tree: dyn_ltree, maxCode: lCodes - 1) // literal tree
        sendTree(tree: dyn_dtree, maxCode: dCodes - 1) // distance tree
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
                    sendCode(code: currentLength, tree: bl_tree)
                }
                count = 0
            } else if currentLength != 0 {
                if currentLength != previousLength {
                    sendCode(code: currentLength, tree: bl_tree)
                    count -= 1
                }
                sendCode(code: Constants.rep_3_6, tree: bl_tree)
                sendBits(value: count - 3, length: 2)
            } else if count <= 10 {
                sendCode(code: Constants.repz_3_10, tree: bl_tree)
                sendBits(value: count - 3, length: 3)
            } else {
                sendCode(code: Constants.repz_11_138, tree: bl_tree)
                sendBits(value: count - 11, length: 7)
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
    
    // Save the match info and tally the frequency counts. Return true if
    // the current block must be flushed.
    func _tr_tally(dist: Int, lc: Int) -> Bool {
        var dist = dist
        let uintDist = UInt8(truncatingBitPattern: dist)
        
        pendingBuf[d_buf + last_lit * 2] = uintDist >> 8
        pendingBuf[d_buf + last_lit * 2 + 1] = uintDist
        l_buf[last_lit] = lc
        last_lit += 1
        
        if dist == 0 {
            // lc is the unmatched char
            dyn_ltree[lc * 2] += 1
        } else {
            matches += 1
            // Here, lc is the match length - MIN_MATCH
            dist -= 1 // dist = match distance - 1
            
            dyn_ltree[(Tree.length_code[lc] + Constants.literals + 1) * 2] += 1
            dyn_dtree[Tree.dCode(dist: dist) * 2] += 1
        }
        
        if (last_lit & 0x1fff) == 0 && level > 2 {
            // Compute an upper bound for the compressed length
            var out_length = last_lit * 8
            let in_length = strstart - block_start
            for dcode in 0..<Constants.dCodes {
                out_length += dyn_dtree[dcode * 2] * (5 + Tree.extra_dbits[dcode])
            }
            out_length >>= 3
            if matches < (last_lit / 2) && out_length < in_length / 2 {
                return true
            }
        }
        
        return last_lit == lit_bufsize - 1
        // We avoid equality with lit_bufsize because of wraparound at 64K
        // on 16 bit machines and because stored blocks are restricted to
        // 64K-1 bytes.
    }
    
    // Send the block data compressed using the given Huffman trees
    func compress_block(ltree: [Int], dtree: [Int]) {
        var lx = 0     // running index in l_buf
        
        if last_lit != 0 {
            repeat {
                // distance of matched string
                var dist = Int(((pendingBuf[d_buf + lx * 2] << 8) & 0xff00) | (pendingBuf[d_buf + lx * 2 + 1] & 0xff))
                // match length or unmatched char (if dist == 0)
                var lc = l_buf[lx] & 0xff
                lx += 1
                
                if dist == 0 {
                    sendCode(code: lc, tree: ltree) // send a literal byte
                } else {
                    // Here, lc is the match length - MIN_MATCH
                    // the code to send
                    var code = Tree.length_code[lc]
                    
                    sendCode(code: code + Constants.literals + 1, tree: ltree) // send the length code
                    // number of extra bits to send
                    var extra = Tree.extra_lbits[code]
                    if extra != 0 {
                        lc -= Tree.base_length[code]
                        sendBits(value: lc, length: extra)     // send the extra length bits
                    }
                    dist -= 1 // dist is now the match distance - 1
                    code = Tree.dCode(dist: dist)
                    
                    sendCode(code: code, tree: dtree)       // send the distance code
                    extra = Tree.extra_dbits[code]
                    if extra != 0 {
                        dist -= Tree.base_dist[code]
                        sendBits(value: dist, length: extra)   // send the extra distance bits
                    }
                } // literal or match pair ?
                
                // Check that the overlay between pending_buf and d_buf+l_buf is ok:
            } while lx < last_lit
        }
        sendCode(code: Constants.endBlock, tree: ltree)
        last_eob_len = ltree[Constants.endBlock * 2 + 1]
    }
    
    // Set the data type to ASCII or BINARY, using a crude approximation:
    // binary if more than 20% of the bytes are <= 6 or >= 128, ascii otherwise.
    // IN assertion: the fields freq of dyn_ltree are set and the total of all
    // frequencies does not exceed 64K (to fit in an int on 16 bit machines).
    func set_data_type() {
        var n = 0
        var ascii_freq = 0
        var bin_freq = 0
        while n < 7 {
            bin_freq += dyn_ltree[n * 2]
            n += 1
        }
        while n < 128 {
            ascii_freq += dyn_ltree[n * 2]
            n += 1
        }
        while n < Constants.literals {
            bin_freq += dyn_ltree[n * 2]
            n += 1
        }
        dataType = bin_freq > (ascii_freq >> 2) ? BlockType.binary : BlockType.ascii
    }
    
    // Flush the bit buffer, keeping at most 7 bits in it.
    func bi_flush() {
        if bi_valid == 16 {
            putInt(w: bi_buf)
            bi_buf = 0
            bi_valid = 0
        } else if bi_valid >= 8 {
            let byte = UInt8(truncatingBitPattern: bi_buf)
            putByte(byte: byte)
            bi_buf >>= 8
            bi_valid -= 8
        }
    }
    
    // Flush the bit buffer and align the output on a byte boundary
    func bi_windup() {
        if bi_valid > 8 {
            putInt(w: bi_buf)
        } else if bi_valid > 0 {
            let byte = UInt8(truncatingBitPattern: bi_buf)
            putByte(byte: byte)
        }
        bi_buf = 0
        bi_valid = 0
    }
    
    // Copy a stored block, storing first the length and its
    // one's complement if requested.
    func copy_block(buf: Int, length: Int, header: Bool) {
//        var index = 0
        bi_windup()      // align on byte boundary
        last_eob_len = 8 // enough lookahead for inflate
    
        if header {
            putInt(w: length)
            putInt(w: ~length)
        }
    
        //  while(len--!=0) {
        //    put_byte(window[buf+index]);
        //    index++;
        //  }
        putByte(bytes: window, start: buf, length: length);
    }
    
    
    func flush_block_only(eof: Bool) {
        let start = block_start >= 0 ? block_start : -1
        _tr_flush_block(buf: start, stored_len: strstart - block_start, eof: eof)
        block_start = strstart
        stream.flush_pending()
    }
    
    // Copy without compression as much as possible from the input stream, return
    // the current block state.
    // This function does not insert new strings in the dictionary since
    // uncompressible data is probably not useful. This function is used
    // only for the level=0 compression option.
    // NOTE: this function should be optimized to avoid extra copying from
    // window to pending_buf.
    func deflate_stored(flush: Flush) -> Status {
        // Stored blocks are limited to 0xffff bytes, pending_buf is limited
        // to pending_buf_size, and each stored block has a 5 byte header:
        
        var max_block_size = 0xffff
//        int max_start;

        if max_block_size > pendingBuf.count - 5 {
            max_block_size = pendingBuf.count - 5
        }
        
        // Copy as much as possible from input to output:
        while true {
            // Fill the window as much as possible:
            if lookahead <= 1 {
                fill_window()
                if lookahead == 0 && flush == Flush.no {
                    return Status.needMore
                }
                if lookahead == 0 {
                    break // flush the current block
                }
            }
            
            strstart += lookahead
            lookahead = 0
            
            // Emit a stored block if pending_buf will be full:
            var max_start = block_start + max_block_size
            if strstart == 0 || strstart >= max_start {
                // strstart == 0 is possible when wraparound on 16-bit machine
                lookahead = strstart - max_start
                strstart = max_start
                
                flush_block_only(eof: false)
                if stream.avail_out == 0 {
                    return .needMore
                }
            }
            
            // Flush if we may have to slide, otherwise block_start may become
            // negative and the data will be gone:
            if strstart - block_start >= windowSize - Deflate.minLookAhead {
                flush_block_only(eof: false)
                if stream.avail_out == 0 {
                    return .needMore
                }
            }
        }
        
        flush_block_only(eof: flush == .finish)
        if stream.avail_out == 0 {
            return flush == .finish ? .finishStarted : .needMore
        }
        
        
        return flush == .finish ? .finishDone : .blockDone
    }
    
    // Send a stored block
    func _tr_stored_block(buf: Int, stored_len: Int, eof: Bool) {
        sendBits(value: (TreeType.storedBlock.rawValue << 1) + (eof ? 1 : 0), length: 3)  // send block type
        copy_block(buf: buf, length: stored_len, header: true)  // with header
    }
    
    // Determine the best encoding for the current block: dynamic trees, static
    // trees or store, and output the encoded block to the zip file.
    func _tr_flush_block(buf: Int, stored_len: Int, eof: Bool) {
        var currentOptLength: Int
        var currentStaticLength: Int // optLength and staticLength in bytes
        var max_blindex = 0      // index of last bit length code of non zero freq
    
        // Build the Huffman trees unless a stored block is forced
        if level > 0 {
            // Check if the file is ascii or binary
            if dataType == .unknown {
                set_data_type()
            }
    
            // Construct the literal and distance trees
            l_desc.buildTree(deflate: self)
    
            d_desc.buildTree(deflate: self)
    
            // At this point, optLength and staticLength are the total bit lengths of
            // the compressed block data, excluding the tree representations.
    
            // Build the bit length tree for the above two trees, and get the index
            // in bl_order of the last bit length code to send.
            max_blindex = buildBlTree()
    
            // Determine the best encoding. Compute first the block length in bytes
            currentOptLength = (optLength + 3 + 7) >> 3
            currentStaticLength = (staticLength + 3 + 7) >> 3
    
            if currentStaticLength <= currentOptLength {
                currentOptLength = currentStaticLength
            }
        } else {
            currentStaticLength = stored_len + 5
            currentOptLength = currentStaticLength // force a stored block
        }
        
        if stored_len + 4 <= currentOptLength && buf != -1 {
            // 4: two words for the lengths
            // The test buf != NULL is only necessary if LIT_BUFSIZE > WSIZE.
            // Otherwise we can't have processed more than WSIZE input bytes since
            // the last block flush, because compression would have been
            // successful. If LIT_BUFSIZE <= WSIZE, it is never too late to
            // transform a block into a stored block.
            _tr_stored_block(buf: buf, stored_len: stored_len, eof: eof)
        } else if currentStaticLength == currentOptLength {
            sendBits(value: (TreeType.staticTrees.rawValue << 1) + (eof ? 1 : 0), length: 3)
            compress_block(ltree: StaticTree.staticLTree, dtree: StaticTree.staticDTree)
        } else {
            sendBits(value: (TreeType.dynamicTrees.rawValue << 1) + (eof ? 1 : 0), length: 3)
            sendAllTrees(lCodes: l_desc.maxCode + 1, dCodes: d_desc.maxCode + 1, blCodes: max_blindex + 1)
            compress_block(ltree: dyn_ltree, dtree: dyn_dtree)
        }
        
        // The above check is made mod 2^32, for files larger than 512 MB
        // and uLong implemented on 32 bits.
        
        initBlock()
        
        if eof {
            bi_windup()
        }
    }
    
    // Fill the window when the lookahead becomes insufficient.
    // Updates strstart and lookahead.
    //
    // IN assertion: lookahead < MIN_LOOKAHEAD
    // OUT assertions: strstart <= window_size-MIN_LOOKAHEAD
    //    At least one byte has been read, or avail_in == 0; reads are
    //    performed for at least two bytes (required for the zip translate_eol
    //    option -- not supported here).
    func fill_window() {
//        int n, m;
//        int p;
//        int more;
        
        repeat {
            // Amount of free space at the end of the window.
            var more = currentWindowSize - lookahead - strstart
            
            // Deal with !@#$% 64K limit:
            if more == 0 && strstart == 0 && lookahead == 0 {
                more = windowSize
            } else if more == -1 {
                // Very unlikely, but possible on 16 bit machine if strstart == 0
                // and lookahead == 1 (input done one byte at time)
                more -= 1
                
                // If the window is almost full and there is insufficient lookahead,
                // move the upper half to the lower one to make room in the upper half.
            } else if strstart >= windowSize + windowSize - Deflate.minLookAhead {
                for i in 0..<windowSize {
                    window[i] = window[i + windowSize]
                }
                match_start -= windowSize
                strstart -= windowSize // we now have strstart >= MAX_DIST
                block_start -= windowSize
                
                // Slide the hash table (could be avoided with 32 bit values
                // at the expense of memory usage). We slide even when level == 0
                // to keep the hash table consistent if we switch back to level > 0
                // later. (Using level 0 permanently is not an optimal usage of
                // zlib, so we don't care about this pathological case.)
                
                var p = windowSize
                
                for _ in (0...hash_size).reversed() {
                    p -= 1
                    let m = head[p] & 0xffff
                    head[p] = max(m - windowSize, 0)
                }
                
                p = windowSize
                
                for _ in (0...hash_size).reversed() {
                    p -= 1
                    let m = prev[p] & 0xffff
                    
                    let prev = UInt8(truncatingBitPattern: max(m - windowSize, 0))
                    prev[p] = prev
                    // If n is not on any hash chain, prev[n] is garbage but
                    // its value will never be used.                
                }
                
                more += windowSize
            }
            
            if stream.avail_in == 0 {
                return
            }
            
            // If there was no sliding:
            //    strstart <= WSIZE+MAX_DIST-1 && lookahead <= MIN_LOOKAHEAD - 1 &&
            //    more == window_size - lookahead - strstart
            // => more >= window_size - (MIN_LOOKAHEAD-1 + WSIZE + MAX_DIST-1)
            // => more >= window_size - 2*WSIZE + 2
            // In the BIG_MEM or MMAP case (not yet supported),
            //   window_size == input_size + MIN_LOOKAHEAD  &&
            //   strstart + s->lookahead <= input_size => more >= MIN_LOOKAHEAD.
            // Otherwise, window_size == 2*WSIZE so more >= 2.
            // If there was sliding, more >= WSIZE. So in all cases, more >= 2.
            
            lookahead += stream.read_buf(window, strstart + lookahead, more)
            
            // Initialize the hash value now that we have some input:
            if lookahead >= Deflate.minMatch {
                ins_h = Int(window[strstart]) & 0xff
                ins_h = (((ins_h) << hash_shift) ^ Int(window[strstart + 1] & 0xff)) & hash_mask
            }
            // If the whole input has less than MIN_MATCH bytes, ins_h is garbage,
            // but this is not important since only literal bytes will be emitted.
        } while lookahead < Deflate.minLookAhead && stream.avail_in != 0
    }
    
    // Compress as much as possible from the input stream, return the current
    // block state.
    // This function does not perform lazy evaluation of matches and inserts
    // new strings in the dictionary only for unmatched strings or for short
    // matches. It is used only for the fast compression options.
    func deflate_fast(flush: Flush) -> Status {
        //    short hash_head = 0; // head of the hash chain
        var hash_head = 0 // head of the hash chain
//        boolean bflush;      // set if current block must be flushed
        
        while true {
            // Make sure that we always have enough lookahead, except
            // at the end of the input file. We need MAX_MATCH bytes
            // for the next match, plus MIN_MATCH bytes to insert the
            // string following the next match.
            if lookahead < Deflate.minLookAhead {
                fill_window()
                if lookahead < Deflate.minLookAhead && flush == .no {
                    return .needMore
                }
                if lookahead == 0 {
                    break // flush the current block
                }
            }
            
            // Insert the string window[strstart .. strstart+2] in the
            // dictionary, and set hash_head to the head of the hash chain:
            if lookahead >= Deflate.minMatch {
                ins_h = ((ins_h << hash_shift) ^ (Int(window[strstart + Deflate.minMatch - 1]) & 0xff)) & hash_mask
                
                //	prev[strstart&w_mask]=hash_head=head[ins_h];
                hash_head = head[ins_h] & 0xffff
                prev[strstart & windowMask] = UInt8(head[ins_h])
                head[ins_h] = strstart
            }
            
            // Find the longest match, discarding those <= prev_length.
            // At this point we have always match_length < MIN_MATCH
            
            if hash_head != 0 && (strstart - hash_head) & 0xffff <= windowSize - Deflate.minLookAhead {
                // To simplify the code, we prevent matches with the string
                // of window index 0 (in particular we have to avoid a match
                // of the string with itself at the start of the input file).
                if strategy != Strategy.huffmanOnly {
                    match_length = longest_match(cur_match: hash_head)
                }
                // longest_match() sets match_start
                if match_length <= 5 && (strategy == .filtered || (match_length == Deflate.minMatch && strstart - match_start > 4096)) {
                    
                    // If prev_match is also MIN_MATCH, match_start is garbage
                    // but we will ignore the current match anyway.
                    match_length = Deflate.minMatch - 1
                }
            }
            
            // If there was a match at the previous step and the current
            // match is not better, output the previous match:
            if prev_length >= Deflate.minMatch && match_length <= prev_length {
                var max_insert = strstart + lookahead - Deflate.minMatch
                // Do not insert strings in hash table beyond this.
                
                //          check_match(strstart-1, prev_match, prev_length);
                
                var bflush = _tr_tally(dist: strstart - 1 - prev_match, lc: prev_length - Deflate.minMatch)
                
                // Insert in hash table all strings up to the end of the match.
                // strstart-1 and strstart are already inserted. If there is not
                // enough lookahead, the last two strings are not inserted in
                // the hash table.
                lookahead -= prev_length - 1
                prev_length -= 2
                
                for _ in 0..<prev_length {
                    strstart += 1
                    if strstart <= max_insert {
                        ins_h = ((ins_h << hash_shift) ^ (Int(window[strstart + Deflate.minMatch - 1]) & 0xff)) & hash_mask
                        //prev[strstart&w_mask]=hash_head=head[ins_h];
                        hash_head = head[ins_h] & 0xffff
                        prev[strstart & windowMask] = UInt8(head[ins_h])
                        head[ins_h] = strstart
                    }
                }
                prev_length = 0
                match_available = 0
                match_length = Deflate.minMatch - 1
                strstart += 1
                
                if bflush {
                    flush_block_only(eof: false)
                    if stream.avail_out == 0 {
                         return Status.needMore
                    }
                }
            } else if match_available != 0 {
                
                // If there was no match at the previous position, output a
                // single literal. If there was a match but the current match
                // is longer, truncate the previous match to a single literal.
                
                var bflush = _tr_tally(dist: 0, lc: Int(window[strstart - 1]) & 0xff)
                
                if bflush {
                    flush_block_only(eof: false)
                }
                strstart += 1
                lookahead -= 1
                if stream.avail_out == 0 {
                    return .needMore
                }
            } else {
                // There is no previous match to compare with, wait for
                // the next step to decide.
                
                match_available = 1
                strstart += 1
                lookahead -= 1
            }
            if match_length <= 5 && (strategy == .filtered || (match_length == Deflate.minMatch && strstart - match_start > 4096)) {
                
                // If prev_match is also MIN_MATCH, match_start is garbage
                // but we will ignore the current match anyway.
                match_length = Deflate.minMatch - 1
            }
            
            // If there was a match at the previous step and the current
            // match is not better, output the previous match:
            if prev_length >= Deflate.minMatch && match_length <= prev_length {
                var max_insert = strstart + lookahead - Deflate.minMatch
                // Do not insert strings in hash table beyond this.
                
                //          check_match(strstart-1, prev_match, prev_length);
                
                var bflush = _tr_tally(dist: strstart - 1 - prev_match, lc: prev_length - Deflate.minMatch)
                
                // Insert in hash table all strings up to the end of the match.
                // strstart-1 and strstart are already inserted. If there is not
                // enough lookahead, the last two strings are not inserted in
                // the hash table.
                lookahead -= prev_length - 1
                prev_length -= 2
                for _ in 0..<prev_length {
                    strstart += 1
                    if strstart <= max_insert {
                        ins_h = ((ins_h << hash_shift) ^ (Int(window[strstart + Deflate.minMatch - 1]) & 0xff)) & hash_mask
                        //prev[strstart&w_mask]=hash_head=head[ins_h];
                        hash_head = head[ins_h] & 0xffff
                        prev[strstart & windowMask] = UInt8(head[ins_h])
                        head[ins_h] = strstart
                    }
                }
                prev_length = 0
                match_available = 0
                match_length = Deflate.minMatch - 1
                strstart += 1
                
                if bflush {
                    flush_block_only(eof: false)
                    if stream.avail_out == 0 {
                        return .needMore
                    }
                }
            } else if match_available != 0 {
                
                // If there was no match at the previous position, output a
                // single literal. If there was a match but the current match
                // is longer, truncate the previous match to a single literal.
                
                var bflush = _tr_tally(dist: 0, lc: Int(window[strstart - 1]) & 0xff)
                
                if bflush {
                    flush_block_only(eof: false)
                }
                strstart += 1
                lookahead -= 1
                if stream.avail_out == 0 {
                    return .needMore
                }
            } else {
                // There is no previous match to compare with, wait for
                // the next step to decide.
                
                match_available = 1
                strstart += 1
                lookahead -= 1
            }
        }
        
        if match_available != 0  {
            /* var bflush */ _ = _tr_tally(dist: 0, lc:Int(window[strstart - 1]) & 0xff)
            match_available = 0
        }
        flush_block_only(eof: flush == .finish)
        
        if stream.avail_out == 0 {
            if (flush == .finish) {
                return .finishStarted
            } else {
                return .needMore
            }
        }
        
        return flush == .finish ? .finishDone : .blockDone
    }
    
    func longest_match(cur_match: Int) -> Int {
        var cur_match = cur_match
        var chain_length = maxChainLength // max hash chain length
        var scan = strstart                 // current string
//        int match;                           // matched string
//        int len;                             // length of current match
        var best_len = prev_length          // best match length so far
        let limit = max(strstart - windowSize + Deflate.minLookAhead, 0)
        var nice_match = self.niceMatch
    
        // Stop when cur_match becomes <= limit. To simplify the code,
        // we prevent matches with the string of window index 0.
        
        let strend = strstart + Deflate.maxMatch
        var scan_end1 = window[scan + best_len - 1]
        var scan_end = window[scan + best_len]
    
        // The code is optimized for HASH_BITS >= 8 and MAX_MATCH-2 multiple of 16.
        // It is easy to get rid of this optimization if necessary.
    
        // Do not waste too much time if we already have a good match:
        if prev_length >= goodMatch {
            chain_length >>= 2
        }
    
        // Do not look for matches beyond the end of the input. This is necessary
        // to make deflate deterministic.
        if nice_match > lookahead {
            nice_match = lookahead
        }
    
        repeat {
            var match = cur_match
    
            // Skip to next match if the match length cannot increase
            // or if the match length is less than 2:
            if window[match + best_len]     != scan_end  ||
               window[match + best_len - 1] != scan_end1 ||
               window[match]                != window[scan] {
                match += 1
                if window[match] != window[scan + 1] {
                    continue
                }
            }
    
            // The check at best_len-1 can be removed because it will be made
            // again later. (This heuristic is not always a win.)
            // It is not necessary to compare scan[2] and match[2] since they
            // are always equal when the other bytes match, given that
            // the hash keys are equal and that HASH_BITS >= 8.
            scan += 2
            match += 1
    
            // We check for insufficient lookahead only every 8th comparison;
            // the 256th check will be made at strstart+258.
            repeat {
                scan += 1
                match += 1
            } while window[scan] == window[match] && scan < strend
            
            let len = Deflate.maxMatch - strend + scan
            scan = strend - Deflate.maxMatch
    
            if len > best_len {
                match_start = cur_match
                best_len = len
                if len >= nice_match {
                    break
                }
                scan_end1 = window[scan + best_len - 1]
                scan_end  = window[scan + best_len]
            }
            cur_match = Int(prev[cur_match & windowMask]) & 0xffff
            if cur_match > limit {
                chain_length -= 1
            }
        } while cur_match > limit && chain_length != 0
    
        return min(lookahead, best_len)
    }
    
//    func deflateEnd() throws {
//        // Deallocate in reverse order of allocations:
//        pendingBuf = nil
//        l_buf = nil
//        head = nil
//        prev = nil
//        window = nil
//        // free
//        // dstate=null;
//        if status == .busy {
//            throw ZError.dataError
//        }
//    }
    
    func deflateParams(level: Int, strategy: Strategy) throws {
        var level = level
        if level == Deflate.zDefaultCompression {
            level = 6
        }
    
        guard level >= 0 && level < 10 else {
            throw ZError.streamError
        }
        let config = Deflate.configTable[level]
        if config.funcVal != Deflate.configTable[self.level].funcVal && stream!.total_in != 0 {
            // Flush the last buffer:
            try stream?.deflate(Flush.partial)
        }
    
        if self.level != level {
            self.level = level
            self.maxLazyMatch   = config.maxLazy
            self.goodMatch      = config.goodLength
            self.niceMatch      = config.niceLength
            self.maxChainLength = config.maxChain
        }
        self.strategy = strategy
    }
    
    func deflateSetDictionary (dictionary: [UInt8], dictLength: Int) throws {
        var length = dictLength
        var index = 0
        
        guard status == .initialisation else {
            throw ZError.streamError
        }
        stream.adler.update(dictionary, 0, dictLength)
    
        if length < Deflate.minMatch {
            return
        }
        
        if length > windowSize - Deflate.minMatch {
            length = windowSize - Deflate.minLookAhead
            index = dictLength - length // use the tail of the dictionary
        }
        for i in 0..<length {
            window[i] = dictionary[index + i]
        }

        strstart = length
        block_start = length
    
        // Insert all strings in the hash table (except for the last two bytes).
        // s->lookahead stays null, so s->ins_h will be recomputed at the next
        // call of fill_window.
    
        ins_h = Int(window[0]) & 0xff
        ins_h = ((ins_h << hash_shift) ^ (Int(window[1]) & 0xff)) & hash_mask
    
        for n in 0..<length-Deflate.minMatch {
            ins_h = ((ins_h << hash_shift) ^ (Int(window[n + Deflate.minMatch - 1]) & 0xff)) & hash_mask
            prev[n & windowMask] = UInt8(head[ins_h])
            head[ins_h] = n
        }
    }
    
    func deflate(flush: Flush) throws {
    
        guard stream.next_out != nil else {
            throw ZError.streamError
        }
        
        guard stream.next_in != nil || stream.avail_in == 0 else {
            throw ZError.streamError
        }
        
        guard status != .finish || flush == .finish else {
            throw ZError.streamError
        }
        
        if stream.avail_out == 0 {
//            stream.msg = z_errmsg[Z_NEED_DICT-(Z_BUF_ERROR)];
            throw ZError.bufferError
        }
    
        var old_flush = lastFlush
        lastFlush = flush
    
        // Write the zlib header
        if status == .initialisation {
            if wrap == 2 {
                gheader.put(self)
                status = .busy
                stream.adler.reset()
            } else {
                var header = (Method.deflated.rawValue + ((windowBits - 8) << 4)) << 8
                var level_flags = ((level - 1) & 0xff) >> 1
    
                level_flags = min(level_flags, 3)
                
                header |= level_flags << 6
                if strstart != 0 {
                    header |= Deflate.presetDict
                }
                header += 31 - (header % 31)
    
                status = .busy
                putIntMSB(w: header)
    
    
                // Save the adler32 of the preset dictionary:
                if strstart != 0 {
                    var adler = stream.adler.getValue()
                    putIntMSB(adler >>> 16)
                    putIntMSB(adler & 0xffff)
                }
                stream.adler.reset()
            }
        }
    
        // Flush as much pending output as possible
        if pending != 0 {
            stream.flush_pending()
            if stream.avail_out == 0 {
                // Since avail_out is 0, deflate will be called again with
                // more output space, but possibly with both pending and
                // avail_in equal to zero. There won't be anything to do,
                // but this is not an error situation so make sure we
                // return OK instead of BUF_ERROR at next call of deflate:
                lastFlush = Flush.no
                return
            }
    
            // Make sure there is something to do and avoid duplicate consecutive
            // flushes. For repeated and useless calls with Z_FINISH, we keep
            // returning Z_STREAM_END instead of Z_BUFF_ERROR.
        } else if stream.avail_in == 0 && flush.rawValue <= old_flush.rawValue && flush != .finish {
//            strm.msg = z_errmsg[Z_NEED_DICT - Z_BUF_ERROR]
            throw ZError.bufferError
        }
    
        // User must not provide more input after the first FINISH:
        if status == .finish && stream.avail_in != 0 {
//            strm.msg = z_errmsg[Z_NEED_DICT - Z_BUF_ERROR]
            throw ZError.bufferError
        }
    
        // Start a new block or continue the current one.
        if stream.avail_in != 0 || lookahead != 0 || (flush != .no && status != .finish) {
            var bstate: Status
            
            switch Deflate.configTable[level].funcVal {
                case .stored:
                    bstate = deflate_stored(flush: flush)

                case .fast:
                    bstate = deflate_fast(flush: flush)

                case .slow:
                    bstate = deflate_slow(flush: flush)
            }
    
            if bstate == .finishStarted || bstate == .finishDone {
                status = .finish
            }
            if bstate == .needMore || bstate == .finishStarted {
                if stream.avail_out == 0 {
                    lastFlush = .no // avoid BUF_ERROR next call, see above
                }
                return
                // If flush != Z_NO_FLUSH && avail_out == 0, the next call
                // of deflate should use the same flush parameter to make sure
                // that the flush is complete. So we don't have to output an
                // empty block here, this will be done at next call. This also
                // ensures that for a very small output buffer, we emit at most
                // one empty block.
            }
    
            if bstate == .blockDone {
                if flush == .partial {
                    _tr_align()
                } else { // FULL_FLUSH or SYNC_FLUSH
                    _tr_stored_block(buf: 0, stored_len: 0, eof: false)
                    // For a full flush, this empty block will be recognized
                    // as a special marker by inflate_sync().
                    if flush == .full {
                        //state.head[s.hash_size-1]=0;
                        for i in 0..<hash_size { // forget history
                            head[i] = 0
                        }
                    }
                }
                stream.flush_pending()
                if stream.avail_out == 0 {
                    lastFlush = .no // avoid BUF_ERROR at next call, see above
                    return
                }
            }
        }
    
        if flush != .finish {
            return
        }
        
        if wrap <= 0 {
            throw ZError.streamEnd
        }
    
        if wrap == 2 {
            var adler = stream.adler.getValue()
            putByte(byte: adler & 0xff)
            putByte(byte: (adler >> 8) & 0xff)
            putByte(byte: (adler >> 16) & 0xff)
            putByte(byte: (adler >> 24) & 0xff)
            putByte(byte: stream.total_in & 0xff)
            putByte(byte: (stream.total_in >> 8) & 0xff)
            putByte(byte: (stream.total_in >> 16) & 0xff)
            putByte(byte: (stream.total_in >> 24) & 0xff)
    
            gheader.setCRC(adler)
        } else {
            // Write the zlib trailer (adler32)
            var adler = stream.adler.getValue()
            putIntMSB(adler >> 16)
            putIntMSB(adler & 0xffff)
        }
    
        stream.flush_pending()
    
        // If avail_out is zero, the application will call deflate again
        // to flush the rest.
        
        if wrap > 0 {
            wrap = -wrap // write the trailer only once!
        }
        if pending == 0 {
            throw ZError.streamEnd
        }
    }
    
    static func deflateCopy(dest: ZStream, src: ZStream) throws {
    
        guard src.dstate != nil else {
            throw ZError.streamError
        }
    
        if src.next_in != nil {
//            dest.next_in = [UInt8]() // size : src.next_in.length
            dest.next_in = src.next_in
        }
        dest.next_in_index = src.next_in_index
        dest.avail_in = src.avail_in
        dest.total_in = src.total_in
    
        if src.next_out != nil {
//            dest.next_out = new byte[src.next_out.length];
            dest.next_out = src.next_out
        }
    
        dest.next_out_index = src.next_out_index
        dest.avail_out = src.avail_out
        dest.total_out = src.total_out
    
        dest.msg = src.msg;
        dest.data_type = src.data_type
        dest.adler = src.adler.copy()
    
        dest.dstate = src.dstate.clone()
        dest.dstate.strm = dest;
    }
}
