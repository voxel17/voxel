//
//  RenderProtocols.swift
//  Rei
//
//  Platform-agnostic rendering abstractions
//

import Foundation
import simd

/// Result of processing a frame
struct FrameData {
    let svoBuffer: Data
    let cameraPosition: Vector3Float
    let cameraDirection: Vector3Float
    let cameraUp: Vector3Float
    let fov: Float
}



/// Abstract renderer protocol
protocol Renderer {
    func preload() throws
    func render(frameData: FrameData) throws
    func resize(width: Int, height: Int)
    func update(deltaTime: Float)
}

/// Frame update delegate
protocol FrameUpdateDelegate: AnyObject {
    func onFrameUpdate(deltaTime: Float)
    func getFrameData() -> FrameData
}
