//
//  TerrainGenerator.swift
//  Rei
//
//  Platform-agnostic terrain generation
//

import Foundation
import simd

typealias Vector3Int = SIMD3<Int>

class TerrainGenerator {
    private let perlinNoiseGenerator: PerlinNoise
    
    init(seed: Int = 12345) {
        self.perlinNoiseGenerator = PerlinNoise(seed: seed)
    }
    
    func generateTerrain(
        gridSize: Int,
        seaLevel: Int = 28,
        maxHeight: Int = 48,
        octaves: Int = 4,
        persistence: Float = 0.5,
        noiseScale: Float = 0.02
    ) -> [VoxelOperation] {
        
        let noiseMountain = PerlinNoise(seed: 54321)
        let noiseCave = PerlinNoise(seed: 99999)
        
        var operations: [VoxelOperation] = []
        operations.reserveCapacity(gridSize * gridSize * (maxHeight / 2))
        
        let bedrockLevel = 4
        
        for x in 0..<gridSize {
            let nx = Float(x) * noiseScale
            
            for z in 0..<gridSize {
                let nz = Float(z) * noiseScale
                
                // Calculate base terrain height
                var baseHeight: Float = perlinNoiseGenerator.noise(nx * 0.03, 0, nz * 0.03) * 1.5
                var maxValue: Float = 1.5
                
                var amplitude: Float = 1.0
                var frequency: Float = 1.0
                
                // Mountains
                for _ in 0..<Swift.min(octaves, 4) {
                    let mountainNoise = noiseMountain.noise(nx * frequency, 0, nz * frequency)
                    baseHeight += mountainNoise * amplitude * 1.2
                    maxValue += amplitude * 1.2
                    amplitude *= persistence
                    frequency *= 2
                }
                
                baseHeight /= maxValue
                
                var terrainHeight = Int((baseHeight + 1.0) / 2.0 * Float(maxHeight - seaLevel)) + seaLevel
                
                // Add variation
                let variation = Int(perlinNoiseGenerator.noise(
                    Float(x) * 0.1, 0, Float(z) * 0.1
                ) * 3)
                terrainHeight = Swift.max(bedrockLevel + 1, 
                                         Swift.min(gridSize - 20, terrainHeight + variation))
                
                // Generate voxels for this column
                for y in 0..<terrainHeight {
                    // Cave generation
                    let caveNoise = noiseCave.octaveNoise(
                        Float(x) * 0.08, Float(y) * 0.08, Float(z) * 0.08, 
                        octaves: 2, persistence: 0.5
                    )
                    
                    let isCave = y > bedrockLevel && y < terrainHeight - 5 && caveNoise > 0.7
                    if isCave { continue }
                    
                    let material = determineMaterial(y: y, 
                                                    terrainHeight: terrainHeight, 
                                                    bedrockLevel: bedrockLevel,
                                                    perlinNoise: perlinNoiseGenerator,
                                                    x: x, z: z)
                    
                    operations.append(VoxelOperation(
                        position: Vector3Int(x, y, z),
                        material: material,
                        type: .add
                    ))
                }
            }
        }
        
        return operations
    }
    
    private func determineMaterial(y: Int, terrainHeight: Int, bedrockLevel: Int,
                                   perlinNoise: PerlinNoise, x: Int, z: Int) -> VoxelMaterial {
        let distanceFromTop = terrainHeight - y - 1
        
        if y < bedrockLevel {
            return .bedrock
        } else if distanceFromTop <= 1 {
            return .grass
        } else if distanceFromTop <= 3 {
            return .dirt
        } else if distanceFromTop <= 6 {
            let stoneNoise = perlinNoise.noise(Float(x) * 0.15, Float(y) * 0.15, Float(z) * 0.15)
            return stoneNoise > 0.3 ? .dirt : .stone
        } else if y - bedrockLevel <= 8 {
            return .stone
        } else {
            return .stone_deep
        }
    }
}
