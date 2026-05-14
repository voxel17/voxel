//
//  SceneController.swift
//  Rei
//
//  High-level scene controller coordinating all systems
//

import Foundation
import SwiftUI

enum RenderQuality: String, CaseIterable, Identifiable {
    case performance = "Performance"
    case balanced = "Balanced"
    case quality = "Quality"

    var id: String { rawValue }

    var renderScale: Float {
        switch self {
        case .performance: return 0.5
        case .balanced: return 0.75
        case .quality: return 1.0
        }
    }

    var minDimension: Int {
        switch self {
        case .performance: return 256
        case .balanced: return 512
        case .quality: return 768
        }
    }

    var maxDimension: Int {
        switch self {
        case .performance: return 512
        case .balanced: return 768
        case .quality: return 1280
        }
    }
}

class SceneController: ObservableObject, InputSceneDelegate, FrameUpdateDelegate {
    // Core systems
    let cameraController: CameraController
    let scene: VoxelScene
    let inputHandler: DefaultInputHandler
    
    // Raycast
    private var lastRaycastHit: RaycastHit?
    private let maxRaycastDistance: Float = 30.0
    
    // World
    private let gridSize: Int

    @Published var renderQuality: RenderQuality = .balanced
    @Published var deletionProgress: Float = 0
    
    init() {
        self.cameraController = CameraController()
        self.scene = VoxelScene()
        self.gridSize = scene.getGridSize()
        self.inputHandler = DefaultInputHandler()
        self.inputHandler.sceneDelegate = self
    }
    
    func update(deltaTime: Float) {
        // Update input
        cameraController.setMovementInput(inputHandler.getActiveKeys())
        cameraController.update(deltaTime: deltaTime)
    }
    
    // MARK: - Input Handling
    
    func onMouseMove(deltaX: Float, deltaY: Float) {
        cameraController.handleMouseDelta(x: deltaX, y: deltaY)
    }
    
    func onMouseClick(at point: CGPoint) {
        deleteTargetVoxel()
    }

    func deleteTargetVoxel() {
        let rayDirection = cameraController.state.direction
        let rayOrigin = cameraController.state.position
        
        if let hit = scene.raycast(from: rayOrigin, direction: rayDirection, 
                                   maxDistance: maxRaycastDistance) {
            print("Hit voxel: \(hit.material) at \(hit.position)")
            scene.removeVoxel(at: hit.position)
            lastRaycastHit = hit
        }
    }

    func setDeletionProgress(_ progress: Float) {
        deletionProgress = min(max(progress, 0), 1)
    }
    
    // MARK: - Scene Editing
    
    func addSphere(center: Vector3Int, radius: Int, material: VoxelMaterial = .stone) {
        scene.addSphere(center: center, radius: radius, material: material)
    }
    
    func addCube(min: Vector3Int, max: Vector3Int, material: VoxelMaterial = .stone) {
        scene.addCube(min: min, max: max, material: material)
    }
    
    func generateTerrain(scale: Float = 0.02, height: Int = 70) {
        scene.generateTerrain(scale: scale, height: height)
    }
    
    func clearAll() {
        scene.clearAll()
    }
    
    func resetCamera() {
        cameraController.reset()
    }
    
    func getGridSize() -> Int{
        return gridSize
    }
    
    // MARK: - FrameUpdateDelegate
    
    func onFrameUpdate(deltaTime: Float) {
        update(deltaTime: deltaTime)
    }
    
    func getFrameData() -> FrameData {
        let svoData = scene.flattenedSVO ?? []
        return FrameData(
            svoBuffer: Data(bytes: svoData, count: svoData.count * MemoryLayout<UInt32>.size),
            cameraPosition: cameraController.state.position,
            cameraDirection: cameraController.state.direction,
            cameraUp: cameraController.state.up,
            fov: cameraController.state.fov
        )
    }
}
