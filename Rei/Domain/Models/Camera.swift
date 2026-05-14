//
//  Camera.swift
//  Rei
//
//  Domain model for camera
//

import simd

typealias Vector3Float = SIMD3<Float>

struct CameraState {
    // Position and orientation
    var position: Vector3Float
    var direction: Vector3Float  // Must be normalized
    var up: Vector3Float         // Must be normalized
    
    var right: Vector3Float {
        return normalize(cross(direction, SIMD3<Float>(0, 1, 0)))
    }
    
    // Camera parameters
    var fov: Float = 90.0        // Degrees
    var nearPlane: Float = 0.1
    var farPlane: Float = 1000.0
    
    // Angles
    var yaw: Float = Float.pi / 2
    var pitch: Float = 0
    
    // Movement settings
    var mouseSensitivity: Float = 0.002
    var movementSpeed: Float = 5.0
    
    mutating func updateDirectionFromAngles() {
        direction = normalize(SIMD3<Float>(
            cos(pitch) * cos(yaw),
            sin(pitch),
            cos(pitch) * sin(yaw)
        ))
        updateUpVector()
    }

    mutating func updateUpVector() {
        up = normalize(cross(right, direction))
    }
    
    mutating func handleMouseMovement(deltaX: Float, deltaY: Float) {
        let yawAngle = -deltaX * mouseSensitivity
        let yawRotation = simd_float4x4(rotationAbout: SIMD3<Float>(0, 1, 0), by: yawAngle)
        let rotatedForward = yawRotation * SIMD4<Float>(direction, 0)
        direction = normalize(SIMD3<Float>(rotatedForward.x, rotatedForward.y, rotatedForward.z))

        let pitchAngle = -deltaY * mouseSensitivity
        let currentPitch = asin(direction.y)
        let maxPitchAngle = Float.pi / 2 - 0.01
        let newPitch = currentPitch + pitchAngle

        if abs(newPitch) < maxPitchAngle {
            let pitchRotation = simd_float4x4(rotationAbout: right, by: pitchAngle)
            let pitchedForward = pitchRotation * SIMD4<Float>(direction, 0)
            direction = normalize(SIMD3<Float>(pitchedForward.x, pitchedForward.y, pitchedForward.z))
        }
        
        updateUpVector()
    }
    
    func getViewMatrix() -> simd_float4x4 {
        let target = position + direction
        let upVector = up
        return simd_float4x4.lookAt(eye: position, center: target, up: upVector)
    }

    func getProjectionMatrix(width: Float, height: Float) -> simd_float4x4 {
        let aspect = width / height
        let fovRadians = fov * Float.pi / 180
        return simd_float4x4.perspective(fovy: fovRadians, aspect: aspect, nearZ: nearPlane, farZ: farPlane)
    }
    
    mutating func moveForward(deltaTime: Float) {
        position += direction * movementSpeed * deltaTime
    }
    
    mutating func moveBackward(deltaTime: Float) {
        position -= direction * movementSpeed * deltaTime
    }
    
    mutating func moveLeft(deltaTime: Float) {
        position -= right * movementSpeed * deltaTime
    }
    
    mutating func moveRight(deltaTime: Float) {
        position += right * movementSpeed * deltaTime
    }

    mutating func moveUp(deltaTime: Float) {
        position.y += movementSpeed * deltaTime
    }

    mutating func moveDown(deltaTime: Float) {
        position.y -= movementSpeed * deltaTime
    }
}

private func cross(_ a: Vector3Float, _ b: Vector3Float) -> Vector3Float {
    return SIMD3<Float>(
        a.y * b.z - a.z * b.y,
        a.z * b.x - a.x * b.z,
        a.x * b.y - a.y * b.x
    )
}

private func normalize(_ v: Vector3Float) -> Vector3Float {
    let len = sqrt(v.x * v.x + v.y * v.y + v.z * v.z)
    if len == 0 { return v }
    return v / len
}

private extension simd_float4x4 {
    init(rotationAbout axis: SIMD3<Float>, by angle: Float) {
        let normalizedAxis = normalize(axis)
        let c = cos(angle)
        let s = sin(angle)
        let t = 1 - c

        let x = normalizedAxis.x
        let y = normalizedAxis.y
        let z = normalizedAxis.z

        self = simd_float4x4(columns: (
            SIMD4<Float>(t * x * x + c, t * x * y + s * z, t * x * z - s * y, 0),
            SIMD4<Float>(t * x * y - s * z, t * y * y + c, t * y * z + s * x, 0),
            SIMD4<Float>(t * x * z + s * y, t * y * z - s * x, t * z * z + c, 0),
            SIMD4<Float>(0, 0, 0, 1)
        ))
    }
}
