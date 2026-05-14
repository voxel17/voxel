//
//  Voxel.swift
//  Rei
//
//  Domain model for voxel data
//

import Foundation
import simd


/// Represents a voxel material type
enum VoxelMaterial: UInt8, CaseIterable {
    case air = 0
    case stone = 1
    case grass = 2
    case bedrock = 3
    case dirt = 4
    case stone_deep = 5
    
    var isOpaque: Bool {
        return self != .air
    }
}

/// Represents a voxel operation (add/remove)
struct VoxelOperation: Hashable {
    enum OperationType {
        case add
        case remove
    }
    
    let position: Vector3Int
    let material: VoxelMaterial
    let type: OperationType
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(position.x)
        hasher.combine(position.y)
        hasher.combine(position.z)
        hasher.combine(material.rawValue)
        hasher.combine(type)
    }
    
    static func == (lhs: VoxelOperation, rhs: VoxelOperation) -> Bool {
        return lhs.position == rhs.position &&
               lhs.material == rhs.material &&
               lhs.type == rhs.type
    }
}

/// Result of a raycast query
struct RaycastHit {
    let position: Vector3Int
    let material: VoxelMaterial
    let distance: Float
}
