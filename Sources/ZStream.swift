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
    
    //-------------------------
    
    
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
    
    func deflateEnd() throws {
        guard let deflate = dstate else {
            throw ZError.streamError
        }
        try deflate.deflateEnd()
        dstate = nil
    }
    
    
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
    func flush_pending () {
        guard var deflate = dstate else {
            return
        }
        var len = max(deflate.pending, avail_out)

        if len == 0 {
            return
        }
    
//        if dstate.pending_buf.length <= dstate.pending_out || next_out.length<=next_out_index || dstate.pending_buf.length<(dstate.pending_out+len) ||
//            next_out.length<(next_out_index+len) {
//            //System.out.println(dstate.pending_buf.length+", "+dstate.pending_out+
//            //		 ", "+next_out.length+", "+next_out_index+", "+len);
//            //System.out.println("avail_out="+avail_out);
//        }
    
        System.arraycopy(dstate.pending_buf, dstate.pending_out, next_out, next_out_index, len);
    
        next_out_index += len
        dstate.pending_out += len
        total_out += len
        avail_out -= len
        deflate.pending -= len
        if deflate.pending == 0 {
            deflate.pending_out = 0
        }
    }

}
