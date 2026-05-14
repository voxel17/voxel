//
//  CameraController.swift
//  Rei
//
//  Manages camera state and input handling
//

import Foundation
import simd


class CameraController {
    var state: CameraState
    
    private var movementState: Set<String> = []
    private let movementSpeed: Float = 25.0
    private var smoothMouseDelta = SIMD2<Float>(0, 0)
    private let mouseSmoothingFactor: Float = 0.3
    
    init(initialPosition: Vector3Float = Vector3Float(100, 130, 50),
         fov: Float = 90.0) {
        let initialDirection = normalize(Vector3Float(0, -0.3, 1))
        self.state = CameraState(
            position: initialPosition,
            direction: initialDirection,
            up: Vector3Float(0, 1, 0),
            fov: fov,
            nearPlane: 0.1,
            farPlane: 1000.0,
            yaw: atan2(initialDirection.z, initialDirection.x),
            pitch: asin(initialDirection.y),
            mouseSensitivity: 0.002,
            movementSpeed: movementSpeed
        )
        state.updateUpVector()
    }
    
    func reset() {
        let initialDirection = normalize(Vector3Float(0, -0.3, 1))
        state = CameraState(
            position: Vector3Float(100, 130, 50),
            direction: initialDirection,
            up: Vector3Float(0, 1, 0),
            fov: 90.0,
            nearPlane: 0.1,
            farPlane: 1000.0,
            yaw: atan2(initialDirection.z, initialDirection.x),
            pitch: asin(initialDirection.y),
            mouseSensitivity: 0.002,
            movementSpeed: movementSpeed
        )
        smoothMouseDelta = .zero
        state.updateUpVector()
    }
    
    func handleMouseDelta(x: Float, y: Float) {
        let scaledDelta = SIMD2<Float>(
            x * state.mouseSensitivity,
            y * state.mouseSensitivity
        )
        smoothMouseDelta = SIMD2<Float>(
            smoothMouseDelta.x * (1 - mouseSmoothingFactor) + scaledDelta.x * mouseSmoothingFactor,
            smoothMouseDelta.y * (1 - mouseSmoothingFactor) + scaledDelta.y * mouseSmoothingFactor
        )
        state.handleMouseMovement(deltaX: smoothMouseDelta.x / state.mouseSensitivity,
                                  deltaY: smoothMouseDelta.y / state.mouseSensitivity)
    }

    func resetMouseSmoothing() {
        smoothMouseDelta = .zero
    }
    
    func setMovementInput(_ keys: Set<String>) {
        self.movementState = keys
    }
    
    func update(deltaTime: Float) {
        guard deltaTime > 0 else { return }

        var movement = Vector3Float(0, 0, 0)

        if movementState.contains("w") {
            movement += state.direction
        }
        if movementState.contains("s") {
            movement -= state.direction
        }
        if movementState.contains("a") {
            movement -= state.right
        }
        if movementState.contains("d") {
            movement += state.right
        }
        if movementState.contains(" ") || movementState.contains("space") {
            movement.y += 1
        }
        if movementState.contains("c") {
            movement.y -= 1
        }

        guard length(movement) > 0 else { return }

        let horizontalMovement = Vector3Float(movement.x, 0, movement.z)
        let horizontalLength = length(horizontalMovement)

        if horizontalLength > 0 {
            let normalizedHorizontal = horizontalMovement / horizontalLength
            movement = Vector3Float(
                normalizedHorizontal.x,
                movement.y != 0 ? (movement.y > 0 ? 1 : -1) : 0,
                normalizedHorizontal.z
            )
        }

        state.position += movement * movementSpeed * deltaTime
    }
}
