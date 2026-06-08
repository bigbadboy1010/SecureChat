// SecureChat/BIT/Crypto/MemoryHardKDF.swift
//
// Memory-hard KDF used for password channels.
// This is NOT Argon2id, but a deterministic memory-mixing KDF to raise GPU/ASIC cost
// without external dependencies (CryptoKit only).
//
// Output: 32 bytes (SymmetricKey)
//
// Parameters chosen to be safe on iPhone simulators; tune memoryKiB/rounds as needed.

import Foundation
import CryptoKit

enum MemoryHardKDFError: Error {
    case invalidParams
}

struct MemoryHardKDF {
    static func deriveKey(password: String, salt: Data, memoryKiB: Int = 4096, rounds: Int = 3) throws -> SymmetricKey {
        guard memoryKiB >= 512, rounds >= 1 else { throw MemoryHardKDFError.invalidParams }

        let pw = password.data(using: .utf8) ?? Data()
        // Initial seed
        var state = SHA256.hash(data: pw + salt)
        let blocks = memoryKiB * 1024 / 32
        var mem = [UInt8](repeating: 0, count: blocks * 32)

        func writeBlock(_ i: Int, _ digest: SHA256.Digest) {
            let base = i * 32
            for (j,b) in digest.enumerated() {
                mem[base + j] = b
            }
        }

        // Fill memory
        for i in 0..<blocks {
            let d = SHA256.hash(data: Data(state) + withU32be(UInt32(i)))
            writeBlock(i, d)
            state = d
        }

        // Mix rounds
        for r in 0..<rounds {
            for i in 0..<blocks {
                let idxA = indexFrom(state: state, modulo: blocks)
                let idxB = (idxA + i + r) % blocks
                let a = Data(mem[idxA*32..<(idxA+1)*32])
                let b = Data(mem[idxB*32..<(idxB+1)*32])
                let d = SHA256.hash(data: a + b + withU32be(UInt32(i)) + withU32be(UInt32(r)))
                writeBlock(idxB, d)
                state = d
            }
        }

        // Finalize: fold memory
        var acc = Data(state)
        for i in stride(from: 0, to: blocks, by: max(1, blocks/64)) {
            acc = Data(SHA256.hash(data: acc + Data(mem[i*32..<(i+1)*32])))
        }

        let final = SHA256.hash(data: acc + salt)
        return SymmetricKey(data: Data(final))
    }

    private static func indexFrom(state: SHA256.Digest, modulo: Int) -> Int {
        // Use first 4 bytes
        let bytes = Array(state.prefix(4))
        var v: UInt32 = 0
        for b in bytes { v = (v << 8) | UInt32(b) }
        return Int(v % UInt32(modulo))
    }

    private static func withU32be(_ v: UInt32) -> Data {
        var x = v.bigEndian
        return Data(bytes: &x, count: 4)
    }
}

private extension Data {
    static func +(lhs: Data, rhs: Data) -> Data {
        var d = lhs
        d.append(rhs)
        return d
    }
}

private extension SHA256.Digest {
    init(_ digest: SHA256.Digest) {
        self = digest
    }
}
