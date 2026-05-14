//
//  MetalRendererCore.swift
//  Rei
//
//  Core Metal rendering logic
//

import SwiftUI
import MetalKit
import simd

/// Camera uniforms matching the Metal shader
struct CameraUniforms {
    var viewMatrix: simd_float4x4
    var projectionMatrix: simd_float4x4
    var inverseViewMatrix: simd_float4x4
    var inverseProjectionMatrix: simd_float4x4
    var position: SIMD3<Float>
    var nearPlane: Float
    var farPlane: Float
    var fov: Float
    var padding: Float = 0
}

/// SVO data structure matching the Metal shader
struct SVOData {
    var rootIndex: UInt32
    var gridSize: UInt32
    var voxelSize: Float
    var gridOrigin: SIMD3<Float>
}


class MetalRendererCore: NSObject, MTKViewDelegate {
    // Dependencies
    let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private let sceneController: SceneController
    
    // Rendering
    private var computePipeline: MTLComputePipelineState?
    private var outputTexture: MTLTexture?
    private var svoBuffer: MTLBuffer?
    private var cameraBuffer: MTLBuffer?
    private var svoDataBuffer: MTLBuffer?
    private var samplerState: MTLSamplerState?
    private var renderPipelineState: MTLRenderPipelineState?
    private var interpolatedRenderPipelineState: MTLRenderPipelineState?
    private var previousTexture: MTLTexture?
    
    // Rendering parameters
    private var outputPixelFormat: MTLPixelFormat = .rgba16Float
    
    var renderWidth: Int = 512
    var renderHeight: Int = 512
    
    // Timing
    private var lastFrameTime: TimeInterval = 0
    private var firstFrame = true
    private var lastFrameTimestamp: TimeInterval = 0
    private var interpolationFactor: Float = 0
    private var hasPreviousFrame = false
    private let frameInterpolationEnabled = true
    
    init(sceneController: SceneController) {
        guard let device = MTLCreateSystemDefaultDevice() else {
            fatalError("Metal is not supported on this device")
        }
        
        self.device = device
        self.commandQueue = device.makeCommandQueue()!
        self.sceneController = sceneController
        
        super.init()
        setupPipelines()
        createTextures(pixelFormat: outputPixelFormat)
    }
    
    private func setupPipelines() {
        guard let library = device.makeDefaultLibrary() else {
            print("Failed to load Metal library")
            return
        }
        
        // FIXED: Use correct function name "renderScene" instead of "raycast_kernel"
        guard let computeFunction = library.makeFunction(name: "renderScene") else {
            print("Failed to load renderScene kernel")
            print("Available functions: \(library.functionNames)")
            return
        }
        
        do {
            computePipeline = try device.makeComputePipelineState(function: computeFunction)
            print("Compute pipeline created successfully")
        } catch {
            print("Failed to create compute pipeline: \(error)")
        }

        guard let vertexFunction = library.makeFunction(name: "scale_vertex"),
              let fragmentFunction = library.makeFunction(name: "scale_fragment"),
              let interpolatedFragmentFunction = library.makeFunction(name: "scale_fragment_interpolated") else {
            print("Failed to load scaling shaders")
            return
        }

        let renderPipelineDescriptor = MTLRenderPipelineDescriptor()
        renderPipelineDescriptor.vertexFunction = vertexFunction
        renderPipelineDescriptor.fragmentFunction = fragmentFunction
        renderPipelineDescriptor.colorAttachments[0].pixelFormat = outputPixelFormat
        renderPipelineDescriptor.depthAttachmentPixelFormat = .invalid
        renderPipelineDescriptor.stencilAttachmentPixelFormat = .invalid

        do {
            renderPipelineState = try device.makeRenderPipelineState(descriptor: renderPipelineDescriptor)
        } catch {
            print("Failed to create render pipeline: \(error)")
        }

        let interpolatedPipelineDescriptor = MTLRenderPipelineDescriptor()
        interpolatedPipelineDescriptor.vertexFunction = vertexFunction
        interpolatedPipelineDescriptor.fragmentFunction = interpolatedFragmentFunction
        interpolatedPipelineDescriptor.colorAttachments[0].pixelFormat = outputPixelFormat
        interpolatedPipelineDescriptor.depthAttachmentPixelFormat = .invalid
        interpolatedPipelineDescriptor.stencilAttachmentPixelFormat = .invalid

        do {
            interpolatedRenderPipelineState = try device.makeRenderPipelineState(descriptor: interpolatedPipelineDescriptor)
        } catch {
            print("Failed to create interpolated render pipeline: \(error)")
        }

        let samplerDescriptor = MTLSamplerDescriptor()
        samplerDescriptor.minFilter = .linear
        samplerDescriptor.magFilter = .linear
        samplerDescriptor.sAddressMode = .clampToEdge
        samplerDescriptor.tAddressMode = .clampToEdge
        samplerState = device.makeSamplerState(descriptor: samplerDescriptor)
    }
    
    private func updateBuffers() {
        guard let flattenedSVO = sceneController.scene.flattenedSVOSnapshot() else {
            print("No flattened SVO available")
            return
        }
        
        // Update SVO buffer
        let svoSize = flattenedSVO.count * MemoryLayout<UInt32>.size
        if svoBuffer == nil || svoBuffer?.length != svoSize {
            svoBuffer = device.makeBuffer(bytes: flattenedSVO, length: svoSize, options: .storageModeShared)
        } else {
            svoBuffer?.contents().copyMemory(from: flattenedSVO, byteCount: svoSize)
        }
        
        // Update SVO data
        var svoData = SVOData(
            rootIndex: 0,
            gridSize: UInt32(sceneController.getGridSize()),
            voxelSize: 1.0,
            gridOrigin: SIMD3<Float>(0, 0, 0)
        )
        
        let svoDataLength = MemoryLayout<SVOData>.stride
        if svoDataBuffer == nil || svoDataBuffer?.length != svoDataLength {
            svoDataBuffer = device.makeBuffer(bytes: &svoData, length: svoDataLength, options: .storageModeShared)
        } else {
            svoDataBuffer?.contents().copyMemory(from: &svoData, byteCount: svoDataLength)
        }
        
        // Update camera uniforms
        let cameraState = sceneController.cameraController.state
        
        // Create view and projection matrices
        let viewMatrix = createViewMatrix(eye: cameraState.position, center: cameraState.position + cameraState.direction, up: cameraState.up)
        let aspect = Float(renderWidth) / Float(renderHeight)
        let projectionMatrix = createPerspectiveMatrix(fov: cameraState.fov, aspect: aspect, near: cameraState.nearPlane, far: cameraState.farPlane)
        
        var uniforms = CameraUniforms(
            viewMatrix: viewMatrix,
            projectionMatrix: projectionMatrix,
            inverseViewMatrix: viewMatrix.inverse,
            inverseProjectionMatrix: projectionMatrix.inverse,
            position: cameraState.position,
            nearPlane: cameraState.nearPlane,
            farPlane: cameraState.farPlane,
            fov: cameraState.fov
        )
        
        let uniformLength = MemoryLayout<CameraUniforms>.stride
        if cameraBuffer == nil || cameraBuffer?.length != uniformLength {
            cameraBuffer = device.makeBuffer(bytes: &uniforms, length: uniformLength, options: .storageModeShared)
        } else {
            cameraBuffer?.contents().copyMemory(from: &uniforms, byteCount: uniformLength)
        }
    }
    
    private func createViewMatrix(eye: SIMD3<Float>, center: SIMD3<Float>, up: SIMD3<Float>) -> simd_float4x4 {
        let f = normalize(center - eye)
        let s = normalize(cross(f, up))
        let u = cross(s, f)
        
        return simd_float4x4(
            SIMD4<Float>(s.x, u.x, -f.x, 0),
            SIMD4<Float>(s.y, u.y, -f.y, 0),
            SIMD4<Float>(s.z, u.z, -f.z, 0),
            SIMD4<Float>(-dot(s, eye), -dot(u, eye), dot(f, eye), 1)
        )
    }
    
    private func createPerspectiveMatrix(fov: Float, aspect: Float, near: Float, far: Float) -> simd_float4x4 {
        let fovRad = fov * Float.pi / 180
        let yScale = 1 / tan(fovRad * 0.5)
        let xScale = yScale / aspect
        let zScale = far / (near - far)
        
        return simd_float4x4(
            SIMD4<Float>(xScale, 0, 0, 0),
            SIMD4<Float>(0, yScale, 0, 0),
            SIMD4<Float>(0, 0, zScale, -1),
            SIMD4<Float>(0, 0, near * zScale, 0)
        )
    }
    
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        updateRenderSize(drawableWidth: Int(size.width), drawableHeight: Int(size.height))
    }
    
    func draw(in view: MTKView) {
        let now = CACurrentMediaTime()
        let deltaTime = firstFrame ? 0.016 : Float(now - lastFrameTime)
        lastFrameTime = now
        firstFrame = false
        
        // Update scene
        sceneController.update(deltaTime: deltaTime)
        
        // Check if SVO needs update
        if sceneController.scene.consumeSVOUpdateFlag() {
            invalidateInterpolationHistory()
        }
        
        guard let commandBuffer = commandQueue.makeCommandBuffer(),
              let drawable = view.currentDrawable,
              let computePipeline = computePipeline else {
            return
        }

        updateRenderSize(drawableWidth: drawable.texture.width, drawableHeight: drawable.texture.height)
        
        // Update buffers with latest data
        updateBuffers()
        
        guard let outputTexture = outputTexture,
              let svoBuffer = svoBuffer,
              let cameraBuffer = cameraBuffer,
              let svoDataBuffer = svoDataBuffer else {
            // Draw fallback color if buffers aren't ready
            if let renderPassDescriptor = view.currentRenderPassDescriptor {
                let renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor)
                renderEncoder?.endEncoding()
                commandBuffer.present(drawable)
                commandBuffer.commit()
            }
            return
        }
        
        // Dispatch compute shader
        guard let computeEncoder = commandBuffer.makeComputeCommandEncoder() else { return }
        
        computeEncoder.setComputePipelineState(computePipeline)
        computeEncoder.setTexture(outputTexture, index: 0)
        computeEncoder.setBuffer(svoBuffer, offset: 0, index: 0)
        computeEncoder.setBuffer(svoDataBuffer, offset: 0, index: 1)
        computeEncoder.setBuffer(cameraBuffer, offset: 0, index: 2)
        
        let threadGroupSize = MTLSize(width: 8, height: 8, depth: 1)
        let threadGroups = MTLSize(
            width: (renderWidth + threadGroupSize.width - 1) / threadGroupSize.width,
            height: (renderHeight + threadGroupSize.height - 1) / threadGroupSize.height,
            depth: 1
        )
        
        computeEncoder.dispatchThreadgroups(threadGroups, threadsPerThreadgroup: threadGroupSize)
        computeEncoder.endEncoding()

        let interpFactor = calculateInterpolationFactor()
        let shouldInterpolate = frameInterpolationEnabled &&
                                hasPreviousFrame &&
                                previousTexture != nil &&
                                interpolatedRenderPipelineState != nil &&
                                interpFactor > 0.01
        
        if let renderPassDescriptor = view.currentRenderPassDescriptor,
           let samplerState = samplerState,
           let renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor) {
            var canDraw = true
            if shouldInterpolate,
               let interpolatedRenderPipelineState = interpolatedRenderPipelineState,
               let previousTexture = previousTexture {
                renderEncoder.setRenderPipelineState(interpolatedRenderPipelineState)
                renderEncoder.setFragmentTexture(outputTexture, index: 0)
                renderEncoder.setFragmentTexture(previousTexture, index: 1)
                var interpFactorValue = interpFactor
                var scaleFactorValue: Float = 1.0
                renderEncoder.setFragmentBytes(&interpFactorValue, length: MemoryLayout<Float>.stride, index: 0)
                renderEncoder.setFragmentBytes(&scaleFactorValue, length: MemoryLayout<Float>.stride, index: 1)
            } else if let renderPipelineState = renderPipelineState {
                renderEncoder.setRenderPipelineState(renderPipelineState)
                renderEncoder.setFragmentTexture(outputTexture, index: 0)
            } else {
                canDraw = false
            }
            if canDraw {
                renderEncoder.setFragmentSamplerState(samplerState, index: 0)
                renderEncoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
            }
            renderEncoder.endEncoding()
        }

        if let previousTexture = previousTexture,
           let blitEncoder = commandBuffer.makeBlitCommandEncoder() {
            blitEncoder.copy(from: outputTexture, to: previousTexture)
            blitEncoder.endEncoding()
            hasPreviousFrame = true
        }
        
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }

    private func calculateInterpolationFactor() -> Float {
        let currentTime = CACurrentMediaTime()
        let deltaTime = currentTime - lastFrameTimestamp
        let targetFrameTime: TimeInterval = 1.0 / 60.0

        if lastFrameTimestamp == 0 {
            interpolationFactor = 0
        } else if deltaTime > targetFrameTime * 1.25 {
            interpolationFactor = min(interpolationFactor * 0.95, 0.3)
        } else {
            interpolationFactor = min(interpolationFactor + 0.02, 0.5)
        }

        lastFrameTimestamp = currentTime
        return interpolationFactor
    }

    private func invalidateInterpolationHistory() {
        interpolationFactor = 0
        lastFrameTimestamp = 0
        hasPreviousFrame = false
    }
    
    private func updateRenderSize(drawableWidth: Int, drawableHeight: Int) {
        guard drawableWidth > 0, drawableHeight > 0 else { return }

        let quality = sceneController.renderQuality
        let scale = quality.renderScale

        var newWidth = Int(Float(drawableWidth) * scale)
        var newHeight = Int(Float(drawableHeight) * scale)

        let longestSide = Swift.max(newWidth, newHeight)
        if longestSide > quality.maxDimension {
            let maxScale = Float(quality.maxDimension) / Float(longestSide)
            newWidth = Int(Float(newWidth) * maxScale)
            newHeight = Int(Float(newHeight) * maxScale)
        }

        let shortestSide = Swift.min(newWidth, newHeight)
        if shortestSide < quality.minDimension {
            let minScale = Float(quality.minDimension) / Float(Swift.max(shortestSide, 1))
            newWidth = Int(Float(newWidth) * minScale)
            newHeight = Int(Float(newHeight) * minScale)
        }

        newWidth = Swift.max(1, newWidth)
        newHeight = Swift.max(1, newHeight)

        if renderWidth != newWidth || renderHeight != newHeight || outputTexture == nil {
            renderWidth = newWidth
            renderHeight = newHeight
            createTextures(pixelFormat: outputPixelFormat)
            invalidateInterpolationHistory()
        }
    }

    private func createTextures(pixelFormat: MTLPixelFormat) {
        let textureDescriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: pixelFormat,
            width: renderWidth,
            height: renderHeight,
            mipmapped: false
        )
        textureDescriptor.usage = [.shaderRead, .shaderWrite]
        
        outputTexture = device.makeTexture(descriptor: textureDescriptor)

        let previousTextureDescriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: pixelFormat,
            width: renderWidth,
            height: renderHeight,
            mipmapped: false
        )
        previousTextureDescriptor.usage = [.shaderRead]
        previousTexture = device.makeTexture(descriptor: previousTextureDescriptor)
        hasPreviousFrame = false
        print("Created output texture: \(renderWidth)x\(renderHeight)")
    }
}
