import Foundation

/// Minimal ZIP reader (stored + deflate, ZIP64), no dependencies.
/// Only the central directory and the requested entries are read, so a
/// multi-GB Instagram export with media is fine.
public final class MiniZip {
    public struct Entry: Equatable, Sendable {
        public var name: String
        public var method: UInt16
        public var compSize: UInt64
        public var size: UInt64
        public var localOffset: UInt64
        public var crc: UInt32
        public var modified: Date?

        /// Last path component, lowercased.
        public var baseName: String {
            (name.split(separator: "/").last.map(String.init) ?? name).lowercased()
        }
    }

    public enum ZipError: Error, Equatable {
        case notZip
        case unreadable
    }

    private let source: Source
    public private(set) var entries: [Entry] = []

    private enum Source {
        case file(FileHandle, UInt64)
        case data(Data)
    }

    public convenience init(url: URL) throws {
        guard let handle = try? FileHandle(forReadingFrom: url) else { throw ZipError.unreadable }
        let size = (try? handle.seekToEnd()) ?? 0
        try self.init(source: .file(handle, size))
    }

    public convenience init(data: Data) throws {
        try self.init(source: .data(data))
    }

    private init(source: Source) throws {
        self.source = source
        try readDirectory()
    }

    deinit {
        if case .file(let h, _) = source { try? h.close() }
    }

    private var totalSize: UInt64 {
        switch source {
        case .file(_, let s): return s
        case .data(let d): return UInt64(d.count)
        }
    }

    private func read(at offset: UInt64, count: Int) -> [UInt8] {
        guard count > 0 else { return [] }
        switch source {
        case .file(let h, _):
            do {
                try h.seek(toOffset: offset)
                return [UInt8](try h.read(upToCount: count) ?? Data())
            } catch {
                return []
            }
        case .data(let d):
            guard offset < UInt64(d.count) else { return [] }
            let start = d.startIndex + Int(offset)
            let end = min(d.endIndex, start + count)
            return [UInt8](d[start..<end])
        }
    }

    private func readDirectory() throws {
        let size = totalSize
        let tail = min(size, 65536 + 22)
        let end = read(at: size - tail, count: Int(tail))
        guard end.count >= 22 else { throw ZipError.notZip }
        var eocd = -1
        var i = end.count - 22
        while i >= 0 {
            if u32(end, i) == 0x06054b50 { eocd = i; break }
            i -= 1
        }
        guard eocd >= 0 else { throw ZipError.notZip }
        var count = UInt64(u16(end, eocd + 10))
        var cdSize = UInt64(u32(end, eocd + 12))
        var cdOffset = UInt64(u32(end, eocd + 16))
        if eocd >= 20, u32(end, eocd - 20) == 0x07064b50 {
            let z64 = u64(end, eocd - 20 + 8)
            let rec = read(at: z64, count: 56)
            if rec.count == 56, u32(rec, 0) == 0x06064b50 {
                count = u64(rec, 32)
                cdSize = u64(rec, 40)
                cdOffset = u64(rec, 48)
            }
        }
        let cd = read(at: cdOffset, count: Int(min(cdSize, 512 * 1024 * 1024)))
        var pos = 0
        var n: UInt64 = 0
        while n < count && pos + 46 <= cd.count {
            guard u32(cd, pos) == 0x02014b50 else { break }
            let flags = u16(cd, pos + 8)
            let method = u16(cd, pos + 10)
            let modified = dosDate(time: u16(cd, pos + 12), date: u16(cd, pos + 14))
            let crc = u32(cd, pos + 16)
            var compSize = UInt64(u32(cd, pos + 20))
            var usize = UInt64(u32(cd, pos + 24))
            let nameLen = Int(u16(cd, pos + 28))
            let extraLen = Int(u16(cd, pos + 30))
            let commentLen = Int(u16(cd, pos + 32))
            var localOffset = UInt64(u32(cd, pos + 42))
            guard pos + 46 + nameLen + extraLen <= cd.count else { break }
            let rawName = Array(cd[(pos + 46)..<(pos + 46 + nameLen)])
            let name = (flags & 0x800 != 0 ? String(bytes: rawName, encoding: .utf8) : nil)
                ?? String(bytes: rawName, encoding: .utf8)
                ?? String(bytes: rawName, encoding: .isoLatin1) ?? ""
            let x = pos + 46 + nameLen
            var k = 0
            while k + 4 <= extraLen {
                let id = u16(cd, x + k), len = Int(u16(cd, x + k + 2))
                if id == 0x0001 {
                    var q = x + k + 4
                    let limit = x + k + 4 + len
                    if usize == 0xFFFFFFFF && q + 8 <= limit { usize = u64(cd, q); q += 8 }
                    if compSize == 0xFFFFFFFF && q + 8 <= limit { compSize = u64(cd, q); q += 8 }
                    if localOffset == 0xFFFFFFFF && q + 8 <= limit { localOffset = u64(cd, q) }
                }
                k += 4 + len
            }
            if !name.hasSuffix("/") {
                entries.append(Entry(name: name, method: method, compSize: compSize, size: usize,
                                     localOffset: localOffset, crc: crc, modified: modified))
            }
            pos += 46 + nameLen + extraLen + commentLen
            n += 1
        }
    }

    /// Uncompressed content, or nil when unreadable / corrupted.
    public func read(_ e: Entry) -> Data? {
        let hdr = read(at: e.localOffset, count: 30)
        guard hdr.count == 30, u32(hdr, 0) == 0x04034b50 else { return nil }
        let dataStart = e.localOffset + 30 + UInt64(u16(hdr, 26)) + UInt64(u16(hdr, 28))
        guard e.compSize < 1 << 31 else { return nil }
        let comp = read(at: dataStart, count: Int(e.compSize))
        guard comp.count == Int(e.compSize) else { return nil }
        let out: [UInt8]
        switch e.method {
        case 0: out = comp
        case 8:
            guard let inflated = Inflate.inflate(comp, expectedSize: Int(min(e.size, 1 << 31))) else { return nil }
            out = inflated
        default: return nil
        }
        guard CRC32.checksum(out) == e.crc else { return nil }
        return Data(out)
    }

    // MARK: Little-endian helpers

    @inline(__always) private func u16(_ b: [UInt8], _ i: Int) -> UInt16 {
        guard i + 2 <= b.count else { return 0 }
        return UInt16(b[i]) | UInt16(b[i + 1]) << 8
    }

    @inline(__always) private func u32(_ b: [UInt8], _ i: Int) -> UInt32 {
        guard i >= 0, i + 4 <= b.count else { return 0 }
        return UInt32(b[i]) | UInt32(b[i + 1]) << 8 | UInt32(b[i + 2]) << 16 | UInt32(b[i + 3]) << 24
    }

    @inline(__always) private func u64(_ b: [UInt8], _ i: Int) -> UInt64 {
        UInt64(u32(b, i)) | UInt64(u32(b, i + 4)) << 32
    }

    private func dosDate(time: UInt16, date: UInt16) -> Date? {
        var c = DateComponents()
        c.year = 1980 + Int(date >> 9)
        c.month = Int((date >> 5) & 0xF)
        c.day = Int(date & 0x1F)
        c.hour = Int(time >> 11)
        c.minute = Int((time >> 5) & 0x3F)
        c.second = Int(time & 0x1F) * 2
        guard c.month! >= 1, c.day! >= 1 else { return nil }
        return Calendar(identifier: .gregorian).date(from: c)
    }
}

// MARK: - CRC32

public enum CRC32 {
    static let table: [UInt32] = (0..<256).map { i -> UInt32 in
        var c = UInt32(i)
        for _ in 0..<8 { c = c & 1 != 0 ? 0xEDB88320 ^ (c >> 1) : c >> 1 }
        return c
    }

    public static func checksum(_ data: [UInt8]) -> UInt32 {
        var c: UInt32 = 0xFFFFFFFF
        data.withUnsafeBufferPointer { buf in
            for b in buf { c = table[Int((c ^ UInt32(b)) & 0xFF)] ^ (c >> 8) }
        }
        return c ^ 0xFFFFFFFF
    }
}

// MARK: - Inflate (RFC 1951), after Mark Adler's "puff"

public enum Inflate {
    struct Huffman {
        var count = [Int](repeating: 0, count: 16)
        var symbol = [Int](repeating: 0, count: 288)
    }

    struct State {
        let input: [UInt8]
        var inPos = 0
        var bitBuf: UInt32 = 0
        var bitCnt = 0
        var out: [UInt8] = []
        var bad = false

        mutating func bits(_ need: Int) -> Int {
            var val = bitBuf
            while bitCnt < need {
                guard inPos < input.count else { bad = true; return 0 }
                val |= UInt32(input[inPos]) << UInt32(bitCnt)
                inPos += 1
                bitCnt += 8
            }
            bitBuf = need >= 32 ? 0 : val >> UInt32(need)
            bitCnt -= need
            return Int(val & ((1 << UInt32(need)) - 1))
        }

        mutating func stored() -> Bool {
            bitBuf = 0
            bitCnt = 0
            guard inPos + 4 <= input.count else { return false }
            let len = Int(input[inPos]) | Int(input[inPos + 1]) << 8
            let nlen = Int(input[inPos + 2]) | Int(input[inPos + 3]) << 8
            inPos += 4
            guard len == (~nlen & 0xFFFF), inPos + len <= input.count else { return false }
            out.append(contentsOf: input[inPos..<(inPos + len)])
            inPos += len
            return true
        }

        mutating func decode(_ h: Huffman) -> Int {
            var code = 0, first = 0, index = 0
            for len in 1..<16 {
                code |= bits(1)
                if bad { return -1 }
                let count = h.count[len]
                if code - count < first { return h.symbol[index + (code - first)] }
                index += count
                first += count
                first <<= 1
                code <<= 1
            }
            return -1
        }

        static let lbase = [3, 4, 5, 6, 7, 8, 9, 10, 11, 13, 15, 17, 19, 23, 27, 31, 35, 43, 51, 59, 67, 83, 99, 115, 131, 163, 195, 227, 258]
        static let lext = [0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 2, 2, 2, 2, 3, 3, 3, 3, 4, 4, 4, 4, 5, 5, 5, 5, 0]
        static let dbase = [1, 2, 3, 4, 5, 7, 9, 13, 17, 25, 33, 49, 65, 97, 129, 193, 257, 385, 513, 769, 1025, 1537, 2049, 3073, 4097, 6145, 8193, 12289, 16385, 24577]
        static let dext = [0, 0, 0, 0, 1, 1, 2, 2, 3, 3, 4, 4, 5, 5, 6, 6, 7, 7, 8, 8, 9, 9, 10, 10, 11, 11, 12, 12, 13, 13]

        mutating func codes(_ lencode: Huffman, _ distcode: Huffman) -> Bool {
            while true {
                var sym = decode(lencode)
                if sym < 0 { return false }
                if sym < 256 { out.append(UInt8(sym)); continue }
                if sym == 256 { return true }
                sym -= 257
                if sym >= 29 { return false }
                let len = State.lbase[sym] + bits(State.lext[sym])
                let dsym = decode(distcode)
                if dsym < 0 || dsym >= 30 { return false }
                let dist = State.dbase[dsym] + bits(State.dext[dsym])
                if bad || dist > out.count { return false }
                let from = out.count - dist
                for i in 0..<len { out.append(out[from + i]) }
            }
        }

        static let fixedTables: (Huffman, Huffman) = {
            var lengths = [Int](repeating: 0, count: 288)
            for s in 0..<144 { lengths[s] = 8 }
            for s in 144..<256 { lengths[s] = 9 }
            for s in 256..<280 { lengths[s] = 7 }
            for s in 280..<288 { lengths[s] = 8 }
            var l = Huffman(), d = Huffman()
            _ = build(&l, lengths, 0, 288)
            _ = build(&d, [Int](repeating: 5, count: 30), 0, 30)
            return (l, d)
        }()

        mutating func fixed() -> Bool {
            codes(State.fixedTables.0, State.fixedTables.1)
        }

        static let order = [16, 17, 18, 0, 8, 7, 9, 6, 10, 5, 11, 4, 12, 3, 13, 2, 14, 1, 15]

        mutating func dynamic() -> Bool {
            var lengths = [Int](repeating: 0, count: 320)
            let nlen = bits(5) + 257, ndist = bits(5) + 1, ncode = bits(4) + 4
            if bad || nlen > 286 || ndist > 30 { return false }
            for index in 0..<19 { lengths[State.order[index]] = index < ncode ? bits(3) : 0 }
            var lencode = Huffman(), distcode = Huffman()
            if State.build(&lencode, lengths, 0, 19) != 0 { return false }
            var index = 0
            while index < nlen + ndist {
                var sym = decode(lencode)
                if sym < 0 { return false }
                if sym < 16 { lengths[index] = sym; index += 1; continue }
                var len = 0
                if sym == 16 {
                    if index == 0 { return false }
                    len = lengths[index - 1]
                    sym = 3 + bits(2)
                } else if sym == 17 {
                    sym = 3 + bits(3)
                } else {
                    sym = 11 + bits(7)
                }
                if bad || index + sym > nlen + ndist { return false }
                for _ in 0..<sym { lengths[index] = len; index += 1 }
            }
            if lengths[256] == 0 { return false }
            let err = State.build(&lencode, lengths, 0, nlen)
            if err < 0 || (err > 0 && nlen - lencode.count[0] != 1) { return false }
            let derr = State.build(&distcode, lengths, nlen, ndist)
            if derr < 0 || (derr > 0 && ndist - distcode.count[0] != 1) { return false }
            return codes(lencode, distcode)
        }

        static func build(_ h: inout Huffman, _ length: [Int], _ offset: Int, _ n: Int) -> Int {
            for i in 0..<16 { h.count[i] = 0 }
            for s in 0..<n { h.count[length[offset + s]] += 1 }
            if h.count[0] == n { return 0 }
            var left = 1
            for len in 1..<16 {
                left <<= 1
                left -= h.count[len]
                if left < 0 { return left }
            }
            var offs = [Int](repeating: 0, count: 16)
            for len in 1..<15 { offs[len + 1] = offs[len] + h.count[len] }
            for s in 0..<n where length[offset + s] != 0 {
                let l = length[offset + s]
                h.symbol[offs[l]] = s
                offs[l] += 1
            }
            return left
        }

        mutating func run() -> Bool {
            var last = 0
            repeat {
                last = bits(1)
                let type = bits(2)
                if bad { return false }
                let ok: Bool
                switch type {
                case 0: ok = stored()
                case 1: ok = fixed()
                case 2: ok = dynamic()
                default: ok = false
                }
                if !ok || bad { return false }
            } while last == 0
            return true
        }
    }

    /// Raw DEFLATE decompression; nil when the data is corrupted.
    public static func inflate(_ input: [UInt8], expectedSize: Int = 0) -> [UInt8]? {
        var s = State(input: input)
        if expectedSize > 0 { s.out.reserveCapacity(expectedSize) }
        return s.run() ? s.out : nil
    }
}
