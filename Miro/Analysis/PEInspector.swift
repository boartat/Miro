//
//  PEInspector.swift
//  Miro
//
//  Reads the import tables of Windows executables so Miro can tell which DLLs a game needs.
//

import Foundation

struct PEInfo: Sendable, Hashable {
    enum Arch: String, Sendable { case x86 = "32-bit", x64 = "64-bit", arm64 = "ARM64", unknown = "알 수 없음" }

    var arch: Arch = .unknown
    /// Lower-cased DLL names from the import table (required to start)
    var imports: [String] = []
    /// Lower-cased DLL names from the delay-import table (loaded on first use, often optional)
    var delayImports: [String] = []
    /// The executable is a .NET (managed) assembly
    var isDotNet = false
    /// CLR metadata version, e.g. `v4.0.30319`
    var clrVersion: String?
    /// Managed assemblies referenced by name (only the ones Miro cares about)
    var referencesXNA = false
}

enum PEInspector {
    static func inspect(_ url: URL) -> PEInfo? {
        guard let data = try? Data(contentsOf: url, options: [.alwaysMapped]) else { return nil }
        return inspect(data)
    }

    // swiftlint:disable:next cyclomatic_complexity function_body_length
    static func inspect(_ data: Data) -> PEInfo? {
        let reader = ByteReader(data: data)
        guard reader.u16(0) == 0x5A4D, let peOffset = reader.u32(0x3C).map(Int.init),
              reader.u32(peOffset) == 0x0000_4550 else { return nil }

        var info = PEInfo()
        let machine = reader.u16(peOffset + 4) ?? 0
        switch machine {
        case 0x14c: info.arch = .x86
        case 0x8664: info.arch = .x64
        case 0xAA64: info.arch = .arm64
        default: info.arch = .unknown
        }

        let numberOfSections = Int(reader.u16(peOffset + 6) ?? 0)
        let sizeOfOptionalHeader = Int(reader.u16(peOffset + 20) ?? 0)
        let optional = peOffset + 24
        guard let magic = reader.u16(optional) else { return info }
        let isPE32Plus = magic == 0x20B
        let imageBase: UInt64 = isPE32Plus ? (reader.u64(optional + 24) ?? 0) : UInt64(reader.u32(optional + 28) ?? 0)
        let rvaCountOffset = optional + (isPE32Plus ? 108 : 92)
        let dirOffset = optional + (isPE32Plus ? 112 : 96)
        let rvaCount = Int(reader.u32(rvaCountOffset) ?? 0)

        func directory(_ index: Int) -> (rva: Int, size: Int)? {
            guard index < rvaCount, let rva = reader.u32(dirOffset + index * 8),
                  let size = reader.u32(dirOffset + index * 8 + 4), rva != 0 else { return nil }
            return (Int(rva), Int(size))
        }

        // Section table → RVA mapping
        struct SectionMap { let virtualAddress: Int; let virtualSize: Int; let rawPointer: Int; let rawSize: Int }
        var sections: [SectionMap] = []
        let sectionTable = optional + sizeOfOptionalHeader
        for index in 0..<min(numberOfSections, 96) {
            let base = sectionTable + index * 40
            guard let vsize = reader.u32(base + 8), let vaddr = reader.u32(base + 12),
                  let rawSize = reader.u32(base + 16), let rawPtr = reader.u32(base + 20) else { break }
            sections.append(SectionMap(virtualAddress: Int(vaddr), virtualSize: Int(vsize),
                                       rawPointer: Int(rawPtr), rawSize: Int(rawSize)))
        }
        func offset(rva: Int) -> Int? {
            for section in sections {
                let span = max(section.virtualSize, section.rawSize)
                if rva >= section.virtualAddress && rva < section.virtualAddress + span {
                    return rva - section.virtualAddress + section.rawPointer
                }
            }
            return nil
        }

        var names: [String] = []
        var delayNames: [String] = []
        var seen = Set<String>()
        func add(_ name: String?, delayed: Bool = false) {
            guard let name = name?.lowercased(), !name.isEmpty, name.count < 128, !seen.contains(name) else { return }
            seen.insert(name)
            if delayed { delayNames.append(name) } else { names.append(name) }
        }

        // Import table (descriptor = 20 bytes, name RVA at +12)
        if let importDir = directory(1), var cursor = offset(rva: importDir.rva) {
            for _ in 0..<2048 {
                guard let nameRVA = reader.u32(cursor + 12), let firstThunk = reader.u32(cursor + 16) else { break }
                if nameRVA == 0 && firstThunk == 0 { break }
                if let nameOffset = offset(rva: Int(nameRVA)) { add(reader.cString(nameOffset)) }
                cursor += 20
            }
        }

        // Delay import table (descriptor = 32 bytes, name at +4)
        if let delayDir = directory(13), var cursor = offset(rva: delayDir.rva) {
            for _ in 0..<1024 {
                guard let attributes = reader.u32(cursor), let nameField = reader.u32(cursor + 4) else { break }
                if nameField == 0 { break }
                var rva = Int(nameField)
                if attributes & 1 == 0, UInt64(nameField) > imageBase { rva = Int(UInt64(nameField) - imageBase) }
                if let nameOffset = offset(rva: rva) { add(reader.cString(nameOffset), delayed: true) }
                cursor += 32
            }
        }
        info.imports = names
        info.delayImports = delayNames

        // CLR header (.NET)
        if let clrDir = directory(14), let clrOffset = offset(rva: clrDir.rva) {
            info.isDotNet = true
            if let metaRVA = reader.u32(clrOffset + 8), let metaOffset = offset(rva: Int(metaRVA)),
               reader.u32(metaOffset) == 0x424A_5342, // "BSJB"
               let length = reader.u32(metaOffset + 12) {
                info.clrVersion = reader.cString(metaOffset + 16, max: Int(min(length, 64)))
            }
            info.referencesXNA = data.range(of: Data("Microsoft.Xna.Framework".utf8)) != nil
        }
        return info
    }
}

/// Bounds-checked little-endian reads from `Data`.
private struct ByteReader {
    let data: Data

    private func bytes(_ offset: Int, _ count: Int) -> Data.SubSequence? {
        guard offset >= 0, count >= 0, offset + count <= data.count else { return nil }
        let start = data.startIndex + offset
        return data[start..<start + count]
    }

    func u16(_ offset: Int) -> UInt16? {
        bytes(offset, 2).map { $0.reversed().reduce(0) { $0 << 8 | UInt16($1) } }
    }

    func u32(_ offset: Int) -> UInt32? {
        bytes(offset, 4).map { $0.reversed().reduce(0) { $0 << 8 | UInt32($1) } }
    }

    func u64(_ offset: Int) -> UInt64? {
        bytes(offset, 8).map { $0.reversed().reduce(0) { $0 << 8 | UInt64($1) } }
    }

    func cString(_ offset: Int, max: Int = 256) -> String? {
        guard offset >= 0, offset < data.count else { return nil }
        let start = data.startIndex + offset
        let end = min(data.endIndex, start + max)
        let slice = data[start..<end]
        let terminator = slice.firstIndex(of: 0) ?? end
        return String(data: data[start..<terminator], encoding: .ascii)
    }
}
