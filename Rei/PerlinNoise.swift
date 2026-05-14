// File: PerlinNoise.swift
// Rei
//
// Created by Разуваев Лев on 30.04.2026
//

import Foundation
import simd

class PerlinNoise {
    private var permutation: [Int]
    
    init(seed: Int = 42) {
        var p = Array(0..<256)
        var rng = SeedableRNG(seed: seed)
        
        // Fisher-Yates shuffle with safe integer conversion
        for i in (0..<256).reversed() {
            let randomValue = rng.next()
            // Use modulo on the UInt64 directly, then convert to Int
            let j = Int(randomValue % UInt64(i + 1))
            p.swapAt(i, j)
        }
        
        // Double the permutation array for wrap-around
        permutation = p + p
    }
    
    private func fade(_ t: Float) -> Float {
        return t * t * t * (t * (t * 6.0 - 15.0) + 10.0)
    }
    
    private func lerp(_ a: Float, _ b: Float, _ t: Float) -> Float {
        return a + t * (b - a)
    }
    
    private func grad(_ hash: Int, _ x: Float, _ y: Float, _ z: Float) -> Float {
        let h = hash & 15
        let u = h < 8 ? x : y
        let v = h < 4 ? y : (h == 12 || h == 14 ? x : z)
        return ((h & 1) == 0 ? u : -u) + ((h & 2) == 0 ? v : -v)
    }
    
    func noise(_ x: Float, _ y: Float, _ z: Float) -> Float {
        let X = Int(floor(x)) & 255
        let Y = Int(floor(y)) & 255
        let Z = Int(floor(z)) & 255
        
        let xf = x - floor(x)
        let yf = y - floor(y)
        let zf = z - floor(z)
        
        let u = fade(xf)
        let v = fade(yf)
        let w = fade(zf)
        
        let A = permutation[X] + Y
        let AA = permutation[A] + Z
        let AB = permutation[A + 1] + Z
        let B = permutation[X + 1] + Y
        let BA = permutation[B] + Z
        let BB = permutation[B + 1] + Z
        
        return lerp(
            lerp(
                lerp(grad(permutation[AA], xf, yf, zf),
                     grad(permutation[BA], xf - 1, yf, zf), u),
                lerp(grad(permutation[AB], xf, yf - 1, zf),
                     grad(permutation[BB], xf - 1, yf - 1, zf), u), v),
            lerp(
                lerp(grad(permutation[AA + 1], xf, yf, zf - 1),
                     grad(permutation[BA + 1], xf - 1, yf, zf - 1), u),
                lerp(grad(permutation[AB + 1], xf, yf - 1, zf - 1),
                     grad(permutation[BB + 1], xf - 1, yf - 1, zf - 1), u), v), w)
    }
    
    func octaveNoise(_ x: Float, _ y: Float, _ z: Float, octaves: Int = 4, persistence: Float = 0.5) -> Float {
        var total: Float = 0
        var frequency: Float = 1
        var amplitude: Float = 1
        var maxValue: Float = 0
        
        for _ in 0..<octaves {
            total += noise(x * frequency, y * frequency, z * frequency) * amplitude
            maxValue += amplitude
            amplitude *= persistence
            frequency *= 2
        }
        
        return total / maxValue
    }
}

// Simple seedable random number generator
struct SeedableRNG {
    private var state: UInt64
    
    init(seed: Int) {
        self.state = UInt64(bitPattern: Int64(seed))
    }
    
    mutating func next() -> UInt64 {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return state
    }
}

