//
//  MatrixHelper.swift
//  Rei
//
//  Created by Разуваев Лев on 03.05.2026.
//

import simd

extension simd_float4x4 {
    static func lookAt(eye: simd_float3, center: simd_float3, up: simd_float3) -> simd_float4x4 {
        let f = normalize(center - eye)
        let s = normalize(cross(f, up))
        let u = cross(s, f)
        
        return simd_float4x4(
            simd_float4(s.x, u.x, -f.x, 0),
            simd_float4(s.y, u.y, -f.y, 0),
            simd_float4(s.z, u.z, -f.z, 0),
            simd_float4(-dot(s, eye), -dot(u, eye), dot(f, eye), 1)
        )
    }
    
    static func perspective(fovy: Float, aspect: Float, nearZ: Float, farZ: Float) -> simd_float4x4 {
        let ys = 1 / tan(fovy * 0.5)
        let xs = ys / aspect
        let zs = farZ / (nearZ - farZ)
        
        return simd_float4x4(
            simd_float4(xs, 0, 0, 0),
            simd_float4(0, ys, 0, 0),
            simd_float4(0, 0, zs, -1),
            simd_float4(0, 0, nearZ * zs, 0)
        )
    }
}
