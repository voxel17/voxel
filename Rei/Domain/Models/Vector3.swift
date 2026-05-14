//
//  Vector3.swift
//  Rei
//
//  Platform-agnostic vector utilities
//

import simd


extension Vector3Float {
    var magnitude: Float {
        return simd_length(self)
    }
    
    func normalized() -> Vector3Float {
        return simd_normalize(self)
    }
    
    func distance(to other: Vector3Float) -> Float {
        return simd_distance(self, other)
    }
    
    func dot(_ other: Vector3Float) -> Float {
        return simd_dot(self, other)
    }
    
    func cross(_ other: Vector3Float) -> Vector3Float {
        return simd_cross(self, other)
    }
}

extension Vector3Int {
    func clamp(min: Vector3Int, max: Vector3Int) -> Vector3Int {
        return Vector3Int(
            Swift.max(Swift.min(self.x, max.x), min.x),
            Swift.max(Swift.min(self.y, max.y), min.y),
            Swift.max(Swift.min(self.z, max.z), min.z)
        )
    }
}
