//
//  ShimDLL.swift
//  Miro
//
//  Builds tiny "forwarder" DLLs for Windows API-set DLLs that Wine 7.7 doesn't ship.
//  Example: newer Unity IL2CPP games import RoGetBufferMarshaler from
//  api-ms-win-core-winrt-robuffer-l1-1-0.dll ("Failed to load il2cpp"). Wine already implements the
//  function in wintypes.dll, so the shim only contains an export table that forwards there —
//  no machine code at all.
//

import Foundation

struct ShimExport: Hashable, Sendable {
    /// Exported name, e.g. `RoGetBufferMarshaler`
    let name: String
    /// Forward target, e.g. `wintypes.RoGetBufferMarshaler`
    let target: String
}

enum ShimDLL {
    /// A valid PE32 / PE32+ DLL whose only content is an export directory of forwarders.
    static func forwarder(dllName: String, exports: [ShimExport], is64Bit: Bool) -> Data {
        let sectionRVA: UInt32 = 0x1000
        let fileAlignment: UInt32 = 0x200
        let sorted = exports.sorted { $0.name.utf8.lexicographicallyPrecedes($1.name.utf8) }
        let count = UInt32(sorted.count)

        // ---- Export data (lives at RVA 0x1000) ----
        var strings = Data()
        func addString(_ text: String) -> UInt32 {
            let offset = UInt32(strings.count)
            strings.append(contentsOf: Array(text.utf8) + [0])
            return offset
        }
        let directorySize: UInt32 = 40
        let functionsOffset = directorySize
        let namesOffset = functionsOffset + 4 * count
        let ordinalsOffset = namesOffset + 4 * count
        let stringsOffset = ordinalsOffset + 2 * count

        let dllNameRVA = sectionRVA + stringsOffset + addString(dllName)
        var nameRVAs: [UInt32] = []
        var forwarderRVAs: [UInt32] = []
        for export in sorted {
            nameRVAs.append(sectionRVA + stringsOffset + addString(export.name))
            forwarderRVAs.append(sectionRVA + stringsOffset + addString(export.target))
        }

        var exportData = Data()
        exportData.le32(0)                               // Characteristics
        exportData.le32(0)                               // TimeDateStamp
        exportData.le16(0); exportData.le16(0)           // Major/Minor version
        exportData.le32(dllNameRVA)                      // Name
        exportData.le32(1)                               // Base (first ordinal)
        exportData.le32(count)                           // NumberOfFunctions
        exportData.le32(count)                           // NumberOfNames
        exportData.le32(sectionRVA + functionsOffset)    // AddressOfFunctions
        exportData.le32(sectionRVA + namesOffset)        // AddressOfNames
        exportData.le32(sectionRVA + ordinalsOffset)     // AddressOfNameOrdinals
        forwarderRVAs.forEach { exportData.le32($0) }    // forwarders point inside the export directory
        nameRVAs.forEach { exportData.le32($0) }
        for index in 0..<sorted.count { exportData.le16(UInt16(index)) }
        exportData.append(strings)

        let exportSize = UInt32(exportData.count)
        let rawSize = (exportSize + fileAlignment - 1) / fileAlignment * fileAlignment
        let imageSize = sectionRVA + (exportSize + 0xFFF) / 0x1000 * 0x1000

        // ---- Headers ----
        var pe = Data(count: 0x40)
        pe[0] = 0x4D; pe[1] = 0x5A                       // "MZ"
        pe.replaceSubrange(0x3C..<0x40, with: le32Bytes(0x40)) // e_lfanew

        pe.append(contentsOf: [0x50, 0x45, 0, 0])        // "PE\0\0"
        pe.le16(is64Bit ? 0x8664 : 0x014C)               // Machine
        pe.le16(1)                                       // NumberOfSections
        pe.le32(0); pe.le32(0); pe.le32(0)               // TimeDateStamp, symbols
        pe.le16(is64Bit ? 0xF0 : 0xE0)                   // SizeOfOptionalHeader
        pe.le16(is64Bit ? 0x2022 : 0x2102)               // EXECUTABLE | (LARGE_ADDRESS_AWARE|32BIT) | DLL

        pe.le16(is64Bit ? 0x20B : 0x10B)                 // Magic
        pe.append(contentsOf: [14, 0])                   // Linker version
        pe.le32(0)                                       // SizeOfCode
        pe.le32(rawSize)                                 // SizeOfInitializedData
        pe.le32(0)                                       // SizeOfUninitializedData
        pe.le32(0)                                       // AddressOfEntryPoint (none)
        pe.le32(sectionRVA)                              // BaseOfCode
        if is64Bit {
            pe.le64(0x1_8000_0000)                       // ImageBase
        } else {
            pe.le32(sectionRVA)                          // BaseOfData
            pe.le32(0x1000_0000)                         // ImageBase
        }
        pe.le32(0x1000)                                  // SectionAlignment
        pe.le32(fileAlignment)                           // FileAlignment
        pe.le16(6); pe.le16(0)                           // OS version
        pe.le16(0); pe.le16(0)                           // Image version
        pe.le16(6); pe.le16(0)                           // Subsystem version
        pe.le32(0)                                       // Win32VersionValue
        pe.le32(imageSize)                               // SizeOfImage
        pe.le32(0x200)                                   // SizeOfHeaders
        pe.le32(0)                                       // CheckSum
        pe.le16(3)                                       // Subsystem: console (irrelevant for DLLs)
        pe.le16(is64Bit ? 0x0160 : 0x0140)               // DYNAMIC_BASE | NX_COMPAT (| HIGH_ENTROPY_VA)
        if is64Bit {
            pe.le64(0x10_0000); pe.le64(0x1000); pe.le64(0x10_0000); pe.le64(0x1000)
        } else {
            pe.le32(0x10_0000); pe.le32(0x1000); pe.le32(0x10_0000); pe.le32(0x1000)
        }
        pe.le32(0)                                       // LoaderFlags
        pe.le32(16)                                      // NumberOfRvaAndSizes
        pe.le32(sectionRVA); pe.le32(exportSize)         // [0] Export directory
        for _ in 1..<16 { pe.le32(0); pe.le32(0) }

        // Section header
        pe.append(contentsOf: Array(".rdata".utf8) + [0, 0])
        pe.le32(exportSize)                              // VirtualSize
        pe.le32(sectionRVA)                              // VirtualAddress
        pe.le32(rawSize)                                 // SizeOfRawData
        pe.le32(0x200)                                   // PointerToRawData
        pe.le32(0); pe.le32(0); pe.le16(0); pe.le16(0)   // relocations / line numbers
        pe.le32(0x4000_0040)                             // INITIALIZED_DATA | MEM_READ

        pe.append(Data(count: 0x200 - pe.count))         // pad headers to 0x200
        pe.append(exportData)
        pe.append(Data(count: Int(rawSize - exportSize)))
        return pe
    }

    private static func le32Bytes(_ value: UInt32) -> Data {
        var data = Data()
        data.le32(value)
        return data
    }
}

private extension Data {
    mutating func le16(_ value: UInt16) { append(contentsOf: [UInt8(value & 0xFF), UInt8(value >> 8)]) }
    mutating func le32(_ value: UInt32) { (0..<4).forEach { append(UInt8((value >> ($0 * 8)) & 0xFF)) } }
    mutating func le64(_ value: UInt64) { (0..<8).forEach { append(UInt8((value >> UInt64($0 * 8)) & 0xFF)) } }
}
