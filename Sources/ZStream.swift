//
//  File.swift
//  SwiftZlib
//
//  Created by Clément Nonn on 05/11/2016.
//
//

import Foundation

enum WrapperType {
    case none
    case gzip
    case zlib
    case any
}

class ZStream {
    private static let maxWBits = 15        // 32K LZ77 window
    private static let defWBits = ZStream.maxWBits
    
    var next_in: [UInt8]     // next input byte
    var next_in_index: Int
    var avail_in: Int       // number of bytes available at next_in
    var total_in: Int      // total nb of input bytes read so far
    
    var next_out: [UInt8]    // next output byte should be put there
    var next_out_index: Int
    var avail_out: Int      // remaining free space at next_out
    var total_out: Int     // total nb of bytes output so far
    
    var msg: String
    
    var dstate: Deflate?
    var istate: Inflate?
    
    var dataType: BlockType // best guess about the data type: ascii or binary
    
    var adler: Checksum
    
    init(adler: Checksum = Adler32()) {
        self.adler = adler
    }
    
    // MARK:- Inflate
    
    func inflateInit(wrapperType: WrapperType) throws {
        try inflateInit(w: ZStream.defWBits, wrapperType: wrapperType)
    }
    
    func inflateInit(w: Int, wrapperType: WrapperType) throws {
        var w = w
        var nowrap = false
        switch wrapperType {
        case .none:
            nowrap = true
        case .gzip:
            w += 16
        default:
            break
        }
        try inflateInit(w: w, nowrap: nowrap)
    }
    
    func inflateInit(w: Int = ZStream.defWBits, nowrap: Bool = false) throws {
        try istate = Inflate(self, nowrap ? -w : w)
    }
    
    func inflate(f: Int) throws {
        guard let inflate = istate else {
            throw ZError.streamError
        }
        try inflate.inflate(f)
    }
    
    func inflateEnd() throws {
        guard let inflate = istate else {
            throw ZError.streamError
        }
        try inflate.inflateEnd()
    }
    
    func inflateSync() throws {
        guard let inflate = istate else {
            throw ZError.streamError
        }
        
        try inflate.inflateSync()
    }
    
    func inflateSyncPoint() throws {
        guard let inflate = istate else {
            throw ZError.streamError
        }
        
        try inflate.inflateSyncPoint()
    }
    
    func inflateSetDictionary(dictionary: [UInt8], dictLength: Int) throws {
        guard let inflate = istate else {
            throw ZError.streamError
        }
        
        try inflate.inflateSetDictionary(dictionary, dictLength)
    }
    
    func inflateFinished() -> Bool {
        return istate?.mode == 12 /*DONE*/
    }
    
    // MARK:- Deflate
    
    
    func deflateInit(level: Int, bits: Int, memlevel: Int, wrapperType: WrapperType) throws {
        guard bits > 8 && bits < 16 else {
            throw ZError.streamError
        }
        
        var bits = bits
        switch wrapperType {
        case .none:
            bits *= -1
        case .gzip:
            bits += 16
        case .any:
            throw ZError.streamError
        default:
            break
        }
        try self.deflateInit(level: level, bits: bits, memlevel: memlevel)
    }
    
    func deflateInit(level: Int, bits: Int, memlevel: Int) throws {
        dstate = try Deflate(stream: self, level: level, bits: bits, memlevel: memlevel)
    }
    
    func deflateInit(level: Int, bits: Int = ZStream.maxWBits, nowrap: Bool = false) throws {
        dstate = try Deflate(stream: self, level: level, bits: nowrap ? -bits : bits)
    }
    
    func deflate(flush: Flush) throws {
        guard let deflate = dstate else {
            throw ZError.streamError
        }
        try deflate.deflate(flush: flush)
    }
    
//    func deflateEnd() throws {
//        guard let deflate = dstate else {
//            throw ZError.streamError
//        }
//        try deflate.deflateEnd()
//        dstate = nil
//    }
    
    
    func deflateParams(level: Int, strategy: Strategy) throws {
        guard let deflate = dstate else {
            throw ZError.streamError
        }
        try deflate.deflateParams(level: level, strategy: strategy)
    }
    
    func deflateSetDictionary (dictionary: [UInt8], dictLength: Int) throws {
        guard let deflate = dstate else {
            throw ZError.streamError
        }
        try deflate.deflateSetDictionary(dictionary: dictionary, dictLength: dictLength)
    }
    
    // Flush as much pending output as possible. All deflate() output goes
    // through this function so some applications may wish to modify it
    // to avoid allocating a large strm->next_out buffer and copying into it.
    // (See also read_buf()).
    func flush_pending() {
        guard let deflate = dstate else {
            return
        }
        let len = min(deflate.pending, avail_out)

        if len == 0 {
            return
        }
    
//        if dstate.pending_buf.length <= dstate.pending_out || next_out.length<=next_out_index || dstate.pending_buf.length<(dstate.pending_out+len) ||
//            next_out.length<(next_out_index+len) {
//            //System.out.println(dstate.pending_buf.length+", "+dstate.pending_out+
//            //		 ", "+next_out.length+", "+next_out_index+", "+len);
//            //System.out.println("avail_out="+avail_out);
//        }
    
        for i in 0..<len {
            next_out[next_out_index + i] = deflate.pendingBuf[deflate.pendingOut + i]
        }
    
        next_out_index += len
        deflate.pendingOut += len
        total_out += len
        avail_out -= len
        deflate.pending -= len
        if deflate.pending == 0 {
            deflate.pendingOut = 0
        }
    }
    
    // Read a new buffer from the current input stream, update the adler32
    // and total number of bytes read.  All deflate() input goes through
    // this function so some applications may wish to modify it to avoid
    // allocating a large strm->next_in buffer and copying from it.
    // (See also flush_pending()).
    func read_buf(buf: [UInt8], start: Int, size: Int) -> Int {
        // FIXME: weird things with buf... should be a pointer ??
        var buf = buf
        guard let deflate = dstate else {
            return 0
        }
        let len = min(avail_in, size)
        
        if len == 0 {
            return 0
        }
        avail_in -= len
    
        if deflate.wrap != 0 {
            adler.update(buf: next_in, index: next_in_index, length: len)
        }
        
        for i in 0..<len {
            buf[start + i] = next_in[next_in_index + i]
        }
        
        next_in_index  += len
        total_in += len
        return len
    }
    
    // MARK:- Others
    
    var adlerValue: Int {
        return self.adler.getValue()
    }
    
    func free() {
        next_in.removeAll()
        next_out.removeAll()
        msg = ""
    }
    
    func setOutput(buf: [UInt8]) {
        setOutput(buf: buf, offset: 0, length: buf.count)
    }
    
    func setOutput(buf: [UInt8], offset: Int, length: Int) {
        next_out = buf
        next_out_index = offset
        avail_out = length
    }
    
    func setInput(buf: [UInt8], offset: Int, length: Int, append: Bool) {
        // change || to && because nonsense of if
        guard length > 0 && append && next_in.count == 0 else {
            return
        }
    
        if avail_in > 0 && append {
            next_in.append(contentsOf: buf)
            next_in_index = 0
            avail_in += length
        } else {
            next_in = buf
            next_in_index = offset
            avail_in = length
        }
    }
}
