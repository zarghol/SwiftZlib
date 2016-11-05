//
//  File.swift
//  Zipper
//
//  Created by Clément Nonn on 04/11/2016.
//  Copyright © 2016 Clément Nonn. All rights reserved.
//

import Foundation

struct TreeStatic {
    static let maxBits = 15
    static let blCodes = 19
    static let dCodes = 30
    static let literals = 256
    static let lengthCodes = 29
    static let lCodes = TreeStatic.literals + 1 + TreeStatic.lengthCodes
    static let heapSize = 2 * TreeStatic.lCodes + 1
    
    // Bit length codes must not exceed MAX_BL_BITS bits
    static let maxBlBits = 7
}

final class Tree {
    
    // end of block literal code
    static let endBlock = 256
    
    // repeat previous bit length 3-6 times (2 bits of repeat count)
    static let rep_3_6 = 16
    
    // repeat a zero length 3-10 times  (3 bits of repeat count)
    static let repz_3_10 = 17
    
    // repeat a zero length 11-138 times  (7 bits of repeat count)
    static let repz_11_138 = 18
    
    // extra bits for each length code
    static let extra_lbits = [ 0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 2, 2, 2, 2, 3, 3, 3, 3, 4, 4, 4, 4, 5, 5, 5, 5, 0 ]
    
    // extra bits for each distance code
    static let extra_dbits = [ 0, 0, 0, 0, 1, 1, 2, 2, 3, 3, 4, 4, 5, 5, 6, 6, 7, 7, 8, 8, 9, 9, 10, 10, 11, 11, 12, 12, 13, 13 ]
    
    // extra bits for each bit length code
    static let extra_blbits = [ 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 2, 3, 7 ]
    
    static let bl_order = [ 16, 17, 18, 0, 8, 7, 9, 6, 10, 5, 11, 4, 12, 3, 13, 2, 14, 1, 15 ]
    
    // The lengths of the bit length codes are sent in order of decreasing
    // probability, to avoid transmitting the lengths for unused bit
    // length codes.
    
    static let Buf_size = 8 * 2
    
    // see definition of array dist_code below
    static let distCodeLength = 512
    
    static let dist_code = [
    0,  1,  2,  3,  4,  4,  5,  5,  6,  6,  6,  6,  7,  7,  7,  7,  8,  8,  8,  8,
    8,  8,  8,  8,  9,  9,  9,  9,  9,  9,  9,  9, 10, 10, 10, 10, 10, 10, 10, 10,
    10, 10, 10, 10, 10, 10, 10, 10, 11, 11, 11, 11, 11, 11, 11, 11, 11, 11, 11, 11,
    11, 11, 11, 11, 12, 12, 12, 12, 12, 12, 12, 12, 12, 12, 12, 12, 12, 12, 12, 12,
    12, 12, 12, 12, 12, 12, 12, 12, 12, 12, 12, 12, 12, 12, 12, 12, 13, 13, 13, 13,
    13, 13, 13, 13, 13, 13, 13, 13, 13, 13, 13, 13, 13, 13, 13, 13, 13, 13, 13, 13,
    13, 13, 13, 13, 13, 13, 13, 13, 14, 14, 14, 14, 14, 14, 14, 14, 14, 14, 14, 14,
    14, 14, 14, 14, 14, 14, 14, 14, 14, 14, 14, 14, 14, 14, 14, 14, 14, 14, 14, 14,
    14, 14, 14, 14, 14, 14, 14, 14, 14, 14, 14, 14, 14, 14, 14, 14, 14, 14, 14, 14,
    14, 14, 14, 14, 14, 14, 14, 14, 14, 14, 14, 14, 15, 15, 15, 15, 15, 15, 15, 15,
    15, 15, 15, 15, 15, 15, 15, 15, 15, 15, 15, 15, 15, 15, 15, 15, 15, 15, 15, 15,
    15, 15, 15, 15, 15, 15, 15, 15, 15, 15, 15, 15, 15, 15, 15, 15, 15, 15, 15, 15,
    15, 15, 15, 15, 15, 15, 15, 15, 15, 15, 15, 15, 15, 15, 15, 15,  0,  0, 16, 17,
    18, 18, 19, 19, 20, 20, 20, 20, 21, 21, 21, 21, 22, 22, 22, 22, 22, 22, 22, 22,
    23, 23, 23, 23, 23, 23, 23, 23, 24, 24, 24, 24, 24, 24, 24, 24, 24, 24, 24, 24,
    24, 24, 24, 24, 25, 25, 25, 25, 25, 25, 25, 25, 25, 25, 25, 25, 25, 25, 25, 25,
    26, 26, 26, 26, 26, 26, 26, 26, 26, 26, 26, 26, 26, 26, 26, 26, 26, 26, 26, 26,
    26, 26, 26, 26, 26, 26, 26, 26, 26, 26, 26, 26, 27, 27, 27, 27, 27, 27, 27, 27,
    27, 27, 27, 27, 27, 27, 27, 27, 27, 27, 27, 27, 27, 27, 27, 27, 27, 27, 27, 27,
    27, 27, 27, 27, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28,
    28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28,
    28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28,
    28, 28, 28, 28, 28, 28, 28, 28, 29, 29, 29, 29, 29, 29, 29, 29, 29, 29, 29, 29,
    29, 29, 29, 29, 29, 29, 29, 29, 29, 29, 29, 29, 29, 29, 29, 29, 29, 29, 29, 29,
    29, 29, 29, 29, 29, 29, 29, 29, 29, 29, 29, 29, 29, 29, 29, 29, 29, 29, 29, 29,
    29, 29, 29, 29, 29, 29, 29, 29, 29, 29, 29, 29
    ]
    
    static let length_code = [
    0,  1,  2,  3,  4,  5,  6,  7,  8,  8,  9,  9, 10, 10, 11, 11, 12, 12, 12, 12,
    13, 13, 13, 13, 14, 14, 14, 14, 15, 15, 15, 15, 16, 16, 16, 16, 16, 16, 16, 16,
    17, 17, 17, 17, 17, 17, 17, 17, 18, 18, 18, 18, 18, 18, 18, 18, 19, 19, 19, 19,
    19, 19, 19, 19, 20, 20, 20, 20, 20, 20, 20, 20, 20, 20, 20, 20, 20, 20, 20, 20,
    21, 21, 21, 21, 21, 21, 21, 21, 21, 21, 21, 21, 21, 21, 21, 21, 22, 22, 22, 22,
    22, 22, 22, 22, 22, 22, 22, 22, 22, 22, 22, 22, 23, 23, 23, 23, 23, 23, 23, 23,
    23, 23, 23, 23, 23, 23, 23, 23, 24, 24, 24, 24, 24, 24, 24, 24, 24, 24, 24, 24,
    24, 24, 24, 24, 24, 24, 24, 24, 24, 24, 24, 24, 24, 24, 24, 24, 24, 24, 24, 24,
    25, 25, 25, 25, 25, 25, 25, 25, 25, 25, 25, 25, 25, 25, 25, 25, 25, 25, 25, 25,
    25, 25, 25, 25, 25, 25, 25, 25, 25, 25, 25, 25, 26, 26, 26, 26, 26, 26, 26, 26,
    26, 26, 26, 26, 26, 26, 26, 26, 26, 26, 26, 26, 26, 26, 26, 26, 26, 26, 26, 26,
    26, 26, 26, 26, 27, 27, 27, 27, 27, 27, 27, 27, 27, 27, 27, 27, 27, 27, 27, 27,
    27, 27, 27, 27, 27, 27, 27, 27, 27, 27, 27, 27, 27, 27, 27, 28
    ]
    
    static let base_length = [
    0, 1, 2, 3, 4, 5, 6, 7, 8, 10, 12, 14, 16, 20, 24, 28, 32, 40, 48, 56,
    64, 80, 96, 112, 128, 160, 192, 224, 0
    ]
    
    static let base_dist = [
    0,   1,      2,     3,     4,    6,     8,    12,    16,     24,
    32,  48,     64,    96,   128,  192,   256,   384,   512,    768,
    1024, 1536,  2048,  3072,  4096,  6144,  8192, 12288, 16384, 24576
    ]
    
    // Mapping from a distance to a distance code. dist is the distance - 1 and
    // must not have side effects. _dist_code[256] and _dist_code[257] are never
    // used.
    
    static func dCode(dist: Int) -> Int{
        return dist < 256 ? dist_code[dist] : dist_code[256 + (dist >> 7)]
    }
    
    var dynTree: [Int]        // the dynamic tree
    var maxCode: Int          // largest code with non zero frequency
    var statDesc: StaticTree  // the corresponding static tree

    // Compute the optimal bit lengths for a tree and update the total bit length
    // for the current block.
    // IN assertion: the fields freq and dad are set, heap[heap_max] and
    //    above are the tree nodes sorted by increasing frequency.
    // OUT assertions: the field len is set to the optimal bit length, the
    //     array bl_count contains the frequencies for each bit length.
    //     The length opt_len is updated; static_len is also updated if stree is
    //     not null.
    
    func genBitLen(deflate: Deflate) {
        var tree = dynTree
        var extra = statDesc.extraBits
        var base = statDesc.extraBase
        var maxLength = statDesc.maxLength
        
//        int h;              // heap index
//        int n, m;           // iterate over the tree elements
//        int bits;           // bit length
//        int xbits;          // extra bits
//        short f;            // frequency

        var heapIndex: Int
        var overflow = 0 // number of elements with bit length too large
        
        for bits in 0..<TreeStatic.maxBits {
            deflate.blCount[bits] = 0
        }
        
        // In a first pass, compute the optimal bit lengths (which may
        // overflow in the case of the bit length tree).
        tree[deflate.heap[deflate.heapMax] * 2 + 1] = 0 // root of the heap
        
        for heapIndex = deflate.heapMax + 1; heapIndex < TreeStatic.heapSize; heapIndex += 1 {
            let n = deflate.heap[heapIndex]
            var bitLength = tree[tree[n * 2 + 1] * 2 + 1] + 1
            if bitLength > maxLength {
                bitLength = maxLength
                overflow += 1
            }
            tree[n * 2 + 1] = bitLength
            // We overwrite tree[n*2+1] which is no longer needed
            
            if n > Tree.maxCode {
                continue  // not a leaf node
            }
            
            deflate.blCount[bitLength] += 1
            var extraBits = 0
            if n >= base {
                extraBits = extra[n - base]
            }
            var frequency = tree[n * 2]
            deflate.optLength += frequency * (bitLength + extraBits)
            if let stree = statDesc.staticTree {
                deflate.staticLength += frequency * (stree[n * 2 + 1] + extraBits)
            }
        }
        
        if overflow == 0 {
            return
        }
        
        // This happens for example on obj2 and pic of the Calgary corpus
        // Find the first bit length which could increase:
        repeat {
            var bitLength = maxLength - 1
            while deflate.blCount[bitLength] == 0 {
                bitLength -= 1
            }
            deflate.blCount[bitLength] -= 1     // move one leaf down the tree
            deflate.blCount[bitLength + 1] += 2 // move one overflow item as its brother
            deflate.blCount[maxLength] -= 1
            // The brother of the overflow item also moves one step up,
            // but this does not affect bl_count[max_length]
            overflow -= 2
        } while overflow > 0
        
        
        for bitLength in (1...maxLength).reversed() {
            var n = deflate.blCount[bitLength]
            while n > 0 {
                heapIndex -= 1
                var m = deflate.heap[heapIndex]
                if m > maxCode {
                    continue
                }
                if tree[m * 2 + 1] != bitLength {
                    deflate.optLength += (bitLength - tree[m * 2 + 1]) * tree[m * 2]
                    tree[m * 2 + 1] = bitLength
                }
                n -= 1
            }
        }
    }
    
    // Construct one Huffman tree and assigns the code bit strings and lengths.
    // Update the total bit length for the current block.
    // IN assertion: the field freq is set for all tree elements.
    // OUT assertions: the fields len and code are set to the optimal bit length
    //     and corresponding code. The length opt_len is updated; static_len is
    //     also updated if stree is not null. The field max_code is set.
    func buildTree(deflate: Deflate) {
        var tree = dynTree
        var elements = statDesc.elements
        
        var maxCode = -1 // largest code with non zero frequency
        
        // Construct the initial heap, with least frequent element in
        // heap[1]. The sons of heap[n] are heap[2*n] and heap[2*n+1].
        // heap[0] is not used.
        deflate.heapLength = 0
        deflate.heapMax = Tree.heapSize
        
        for n in 0..<elements {
            if tree[n * 2] != 0 {
                deflate.heapLength -= 1
                maxCode = n
                deflate.heap[deflate.heapLength] = n
                deflate.depth[n] = 0
            } else {
                tree[n * 2 + 1] = 0
            }
        }
        
        // The pkzip format requires that at least one distance code exists,
        // and that at least one bit should be sent even if there is only one
        // possible code. So to avoid special checks later on we force at least
        // two codes of non zero frequency.
        while deflate.heapLength < 2 {
            deflate.heapLength += 1
            var node: Int
            if maxCode < 2 {
                maxCode += 1
                node = maxCode
            } else {
                node = 0
            }
            deflate.heap[deflate.heapLength] = node
            tree[node * 2] = 1
            deflate.depth[node] = 0
            deflate.optLength -= 1
            if let stree = statDesc.staticTree {
                deflate.staticLength -= stree[node * 2 + 1]
            }
            // node is 0 or 1 so it does not have extra bits
        }
        self.maxCode = maxCode
        
        // The elements heap[heap_len/2+1 .. heap_len] are leaves of the tree,
        // establish sub-heaps of increasing lengths:
        
        
        for n in (1...deflate.heapLength / 2).reversed() {
            deflate.pqDownHeap(tree, n)
        }
        
        // Construct the Huffman tree by repeatedly combining the least two
        // frequent nodes.
        
        var node = elements                 // next internal node of the tree
        repeat {
            // n = node of least frequency
            var n = deflate.heap[1]
            deflate.heap_len -= 1
            deflate.heap[1] = deflate.heap[deflate.heap_len]
            deflate.pqDownHeap(tree, 1)
            
            // m = node of next least frequency
            var m = deflate.heap[1]
            deflate.heapMax -= 1
            deflate.heap[deflate.heapMax] = n // keep the nodes sorted by frequency
            deflate.heapMax -= 1
            deflate.heap[deflate.heapMax] = m
            
            // Create a new node father of n and m
            tree[node * 2] = tree[n * 2] + tree[m * 2]
            deflate.depth[node] = max(deflate.depth[n], deflate.depth[m]) + 1
            tree[m * 2 + 1] = node
            tree[n * 2 + 1] = node
            
            // and insert the new node in the heap
            node += 1
            deflate.heap[1] = node
            deflate.pqDownHeap(tree, 1)
        } while deflate.heapLength >= 2
        deflate.heapMax -= 1
        deflate.heap[deflate.heapMax] = deflate.heap[1]
        
        // At this point, the fields freq and dad are set. We can now
        // generate the bit lengths.
        
        genBitLen(deflate: deflate)
        
        // The field len is now set, we can generate the bit codes
        genCodes(tree: tree, maxCode: maxCode, blCount: deflate.blCount, nextCode: deflate.nextCode)// -> (tree: [Int], nextCode: [Int])

    }
    
    // Generate the codes for a given tree and bit counts (which need not be
    // optimal).
    // IN assertion: the array bl_count contains the bit length statistics for
    // the given tree and the field len is set for all tree elements.
    // OUT assertion: the field code is set for all tree elements of non
    //     zero code length.
    private static func genCodes(tree: [Int], maxCode: Int, blCount: [Int], nextCode: [Int]) -> (tree: [Int], nextCode: [Int]) {
        var code = 0 // running code value
        
        // The distribution counts are first used to generate the code values
        // without bit reversal.
        var nextCodes = nextCode
        var tree = tree
        nextCodes[0] = 0
        for bitsIndex in 1...TreeStatic.maxBits {
            code = (code + blCount[bitsIndex - 1]) << 1
            nextCodes[bitsIndex] = code
        }
        
        // Check that the bit counts in bl_count are consistent. The last code
        // must be all ones.
        //Assert (code + bl_count[MAX_BITS]-1 == (1<<MAX_BITS)-1,
        //        "inconsistent bit counts");
        //Tracev((stderr,"\ngen_codes: max_code %d ", max_code));
        for n in 0...maxCode {
            let length = tree[n * 2 + 1]
            if length == 0 {
                continue
            }
            // Now reverse the bits
            
            tree[n * 2] = biReverse(code: nextCodes[length], length: length)
            nextCodes[length] += 1
        }
    }
    
    // Reverse the first len bits of a code, using straightforward code (a faster
    // method would use a table)
    // IN assertion: 1 <= len <= 15
    private static func biReverse(code: Int, length: Int) -> Int {
        var res = 0
        var length = length
        var code = code
        repeat {
            res |= code & 1
            code >>= 1
            res <<= 1
            length -= 1
        } while length > 0
        return res >> 1
    }
}
