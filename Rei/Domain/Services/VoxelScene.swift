//
//  VoxelScene.swift
//  Rei
//
//  Core scene management with voxel operations
//  Platform-agnostic scene logic
//

import Foundation

class VoxelScene {
    private var gridSize: Int
    private var pendingOperations: [VoxelOperation] = []
    private var rebuildQueue = DispatchQueue(
        label: "com.rei.svoRebuild",
        qos: .userInitiated,
        attributes: .concurrent
    )
    private var isRebuilding = false
    private let rebuildLock = NSLock()
    private let queryCacheLock = NSLock()
    
    private var queryCache: [Int: UInt8] = [:]
    private let maxCacheSize = 10000
    
    var svoRoot: SVONode?
    var flattenedSVO: [UInt32]?
    var svoNeedsUpdate = false
    
    let terrainGenerator: TerrainGenerator
    
    init(gridSize: Int = 128) {
        self.gridSize = gridSize
        self.terrainGenerator = TerrainGenerator()
        self.svoRoot = SVONode(children: [], value: 0)
        
        createInitialScene()
        buildSVO()
    }
    
    func getGridSize() -> Int{
        return gridSize
    }
    
    // MARK: - Voxel Operations
    
    func addVoxel(at position: Vector3Int, material: VoxelMaterial) {
        rebuildLock.lock()
        pendingOperations.append(VoxelOperation(position: position, material: material, type: .add))
        rebuildLock.unlock()
        scheduleRebuild()
    }
    
    func removeVoxel(at position: Vector3Int) {
        rebuildLock.lock()
        pendingOperations.append(VoxelOperation(position: position, material: .air, type: .remove))
        rebuildLock.unlock()
        scheduleRebuild()
    }
    
    func addSphere(center: Vector3Int, radius: Int, material: VoxelMaterial) {
        rebuildLock.lock()
        for x in Swift.max(0, center.x - radius)...Swift.min(gridSize - 1, center.x + radius) {
            for y in Swift.max(0, center.y - radius)...Swift.min(gridSize - 1, center.y + radius) {
                for z in Swift.max(0, center.z - radius)...Swift.min(gridSize - 1, center.z + radius) {
                    let dx = x - center.x
                    let dy = y - center.y
                    let dz = z - center.z
                    let distanceSquared = dx * dx + dy * dy + dz * dz
                    
                    if distanceSquared <= radius * radius {
                        pendingOperations.append(VoxelOperation(
                            position: Vector3Int(x, y, z),
                            material: material,
                            type: .add
                        ))
                    }
                }
            }
        }
        rebuildLock.unlock()
        scheduleRebuild()
    }
    
    func addCube(min: Vector3Int, max: Vector3Int, material: VoxelMaterial) {
        rebuildLock.lock()
        
        let startX = Swift.max(0, min.x)
        let endX = Swift.min(gridSize - 1, max.x)
        let startY = Swift.max(0, min.y)
        let endY = Swift.min(gridSize - 1, max.y)
        let startZ = Swift.max(0, min.z)
        let endZ = Swift.min(gridSize - 1, max.z)
        
        for x in startX...endX {
            for y in startY...endY {
                for z in startZ...endZ {
                    pendingOperations.append(VoxelOperation(
                        position: Vector3Int(x, y, z),
                        material: material,
                        type: .add
                    ))
                }
            }
        }
        rebuildLock.unlock()
        scheduleRebuild()
    }
    
    func generateTerrain(scale: Float = 0.02, height: Int = 48) {
        print("Generating terrain...")
        rebuildLock.lock()
        pendingOperations.removeAll()
        rebuildLock.unlock()
        
        let operations = terrainGenerator.generateTerrain(
            gridSize: gridSize,
            maxHeight: height,
            noiseScale: scale
        )
        
        rebuildLock.lock()
        pendingOperations = operations
        rebuildLock.unlock()
        
        scheduleRebuild()
    }
    
    func clearAll() {
        rebuildLock.lock()
        pendingOperations.removeAll()
        rebuildLock.unlock()
        
        rebuildQueue.async { [weak self] in
            guard let self = self else { return }
            self.rebuildLock.lock()
            self.isRebuilding = true
            self.rebuildLock.unlock()
            
            let emptyRoot = SVONode(children: [], value: 0)
            
            self.rebuildLock.lock()
            self.svoRoot = emptyRoot
            self.flattenedSVO = flattenSVO(root: emptyRoot)
            self.svoNeedsUpdate = true
            self.isRebuilding = false
            self.rebuildLock.unlock()
        }
    }

    func consumeSVOUpdateFlag() -> Bool {
        rebuildLock.lock()
        let needsUpdate = svoNeedsUpdate
        svoNeedsUpdate = false
        rebuildLock.unlock()
        return needsUpdate
    }

    func flattenedSVOSnapshot() -> [UInt32]? {
        rebuildLock.lock()
        let snapshot = flattenedSVO
        rebuildLock.unlock()
        return snapshot
    }
    
    // MARK: - Raycast Query
    
    func raycast(from origin: Vector3Float, direction: Vector3Float, 
                 maxDistance: Float = 100.0) -> RaycastHit? {
        if direction.x == 0 && direction.y == 0 && direction.z == 0 {
            return nil
        }
        
        let start = origin
        let dir = normalize(direction)
        
        var currentX = Int(floor(start.x))
        var currentY = Int(floor(start.y))
        var currentZ = Int(floor(start.z))
        
        let stepX = dir.x > 0 ? 1 : (dir.x < 0 ? -1 : 0)
        let stepY = dir.y > 0 ? 1 : (dir.y < 0 ? -1 : 0)
        let stepZ = dir.z > 0 ? 1 : (dir.z < 0 ? -1 : 0)
        
        let tDeltaX = abs(1.0 / dir.x)
        let tDeltaY = abs(1.0 / dir.y)
        let tDeltaZ = abs(1.0 / dir.z)
        
        var tMaxX: Float
        var tMaxY: Float
        var tMaxZ: Float
        
        if stepX > 0 {
            tMaxX = (Float(currentX + 1) - start.x) / dir.x
        } else if stepX < 0 {
            tMaxX = (start.x - Float(currentX)) / -dir.x
        } else {
            tMaxX = Float.infinity
        }
        
        if stepY > 0 {
            tMaxY = (Float(currentY + 1) - start.y) / dir.y
        } else if stepY < 0 {
            tMaxY = (start.y - Float(currentY)) / -dir.y
        } else {
            tMaxY = Float.infinity
        }
        
        if stepZ > 0 {
            tMaxZ = (Float(currentZ + 1) - start.z) / dir.z
        } else if stepZ < 0 {
            tMaxZ = (start.z - Float(currentZ)) / -dir.z
        } else {
            tMaxZ = Float.infinity
        }
        
        var distance: Float = 0
        
        while distance < maxDistance {
            if let voxelValue = getVoxel(at: Vector3Int(currentX, currentY, currentZ)),
               voxelValue != 0 {
                return RaycastHit(
                    position: Vector3Int(currentX, currentY, currentZ),
                    material: VoxelMaterial(rawValue: voxelValue) ?? .air,
                    distance: distance
                )
            }
            
            if tMaxX < tMaxY {
                if tMaxX < tMaxZ {
                    currentX += stepX
                    distance = tMaxX
                    tMaxX += tDeltaX
                } else {
                    currentZ += stepZ
                    distance = tMaxZ
                    tMaxZ += tDeltaZ
                }
            } else {
                if tMaxY < tMaxZ {
                    currentY += stepY
                    distance = tMaxY
                    tMaxY += tDeltaY
                } else {
                    currentZ += stepZ
                    distance = tMaxZ
                    tMaxZ += tDeltaZ
                }
            }
        }
        
        return nil
    }
    
    private func getVoxel(at position: Vector3Int) -> UInt8? {
        // Check bounds
        if position.x < 0 || position.x >= gridSize ||
           position.y < 0 || position.y >= gridSize ||
           position.z < 0 || position.z >= gridSize {
            return nil
        }
        
        queryCacheLock.lock()
        let hashKey = position.x ^ (position.y << 10) ^ (position.z << 20)
        if let cached = queryCache[hashKey] {
            queryCacheLock.unlock()
            return cached
        }
        queryCacheLock.unlock()
        
        // Query from SVO
        if let result = querySVO(position: position) {
            queryCacheLock.lock()
            if queryCache.count >= maxCacheSize {
                queryCache.removeAll()
            }
            queryCache[hashKey] = result
            queryCacheLock.unlock()
            return result
        }
        
        return nil
    }
    
    private func querySVO(position: Vector3Int) -> UInt8? {
        guard let root = svoRoot else { return nil }
        return querySVONode(root, position: position, size: gridSize)
    }
    
    private func querySVONode(_ node: SVONode, position: Vector3Int, size: Int) -> UInt8? {
        if let value = node.value {
            return value
        }
        
        if node.children.isEmpty || size <= 1 {
            return nil
        }
        
        let half = size / 2
        let childX = position.x >= half ? 1 : 0
        let childY = position.y >= half ? 1 : 0
        let childZ = position.z >= half ? 1 : 0
        let childIndex = childZ * 4 + childY * 2 + childX
        
        guard childIndex < node.children.count else { return nil }
        
        let newPos = Vector3Int(
            position.x % half,
            position.y % half,
            position.z % half
        )
        
        return querySVONode(node.children[childIndex], position: newPos, size: half)
    }
    
    // MARK: - Private Methods
    
    private func createInitialScene() {
        let groundLevel = 5
        
        for x in 0..<gridSize {
            for z in 0..<gridSize {
                for y in 0..<groundLevel {
                    let material: VoxelMaterial
                    if y < 3 {
                        material = .bedrock
                    } else if y == groundLevel - 1 {
                        material = .grass
                    } else {
                        material = .stone
                    }
                    
                    pendingOperations.append(VoxelOperation(
                        position: Vector3Int(x, y, z),
                        material: material,
                        type: .add
                    ))
                }
            }
        }
    }
    
    private func scheduleRebuild() {
        rebuildQueue.async { [weak self] in
            guard let self = self else { return }
            
            self.rebuildLock.lock()
            guard !self.isRebuilding else {
                self.rebuildLock.unlock()
                return
            }
            self.isRebuilding = true
            self.rebuildLock.unlock()
            
            self.rebuildLock.lock()
            let operations = self.pendingOperations
            self.pendingOperations.removeAll()
            self.rebuildLock.unlock()
            
            let updatedRoot = self.applyOperations(
                operations,
                to: self.svoRoot ?? SVONode(children: [], value: 0)
            )
            let flattened = flattenSVO(root: updatedRoot)
            
            self.rebuildLock.lock()
            self.svoRoot = updatedRoot
            self.flattenedSVO = flattened
            self.svoNeedsUpdate = true
            self.isRebuilding = false
            self.rebuildLock.unlock()
            
            self.clearQueryCache()
        }
    }
    
    private func buildSVO() {
        rebuildLock.lock()
        let operations = pendingOperations
        pendingOperations.removeAll()
        rebuildLock.unlock()
        
        let root = buildSVOFromOperations(operations)
        rebuildLock.lock()
        svoRoot = root
        flattenedSVO = flattenSVO(root: root)
        rebuildLock.unlock()
    }
    
    private func buildSVOFromOperations(_ operations: [VoxelOperation]) -> SVONode {
        let voxels = operations.map { ($0.position, $0.material.rawValue) }
        return buildSVOFromVoxels(voxels, gridSize: gridSize)
    }

    private func applyOperations(_ operations: [VoxelOperation], to root: SVONode) -> SVONode {
        var modifiedRoot = root

        for operation in operations {
            modifiedRoot = applyOperation(operation, to: modifiedRoot, size: gridSize)
        }

        return modifiedRoot
    }

    private func applyOperation(_ operation: VoxelOperation,
                                to node: SVONode,
                                size: Int,
                                position: Vector3Int = Vector3Int(0, 0, 0)) -> SVONode {
        guard operation.position.x >= position.x,
              operation.position.x < position.x + size,
              operation.position.y >= position.y,
              operation.position.y < position.y + size,
              operation.position.z >= position.z,
              operation.position.z < position.z + size else {
            return node
        }

        if size == 1 {
            let value: UInt8 = operation.type == .remove ? 0 : operation.material.rawValue
            return SVONode(children: [], value: value)
        }

        let halfSize = size / 2
        let targetX = operation.position.x - position.x
        let targetY = operation.position.y - position.y
        let targetZ = operation.position.z - position.z

        let childIndex = ((targetZ >= halfSize ? 1 : 0) * 4) +
                         ((targetY >= halfSize ? 1 : 0) * 2) +
                         (targetX >= halfSize ? 1 : 0)

        var currentNode = node
        if let leafValue = currentNode.value {
            if operation.type == .add && leafValue == operation.material.rawValue {
                return currentNode
            }
            if operation.type == .remove && leafValue == 0 {
                return currentNode
            }

            currentNode = SVONode(
                children: (0..<8).map { _ in SVONode(children: [], value: leafValue) },
                value: nil
            )
        }

        var children = currentNode.children
        if children.isEmpty {
            children = (0..<8).map { _ in SVONode(children: [], value: 0) }
        }

        let childPosition = Vector3Int(
            position.x + ((childIndex & 1) != 0 ? halfSize : 0),
            position.y + ((childIndex & 2) != 0 ? halfSize : 0),
            position.z + ((childIndex & 4) != 0 ? halfSize : 0)
        )

        children[childIndex] = applyOperation(
            operation,
            to: children[childIndex],
            size: halfSize,
            position: childPosition
        )

        let firstValue = children[0].value
        let allSame = firstValue != nil && children.dropFirst().allSatisfy { $0.value == firstValue }

        if allSame, let value = firstValue {
            return SVONode(children: [], value: value)
        }

        return SVONode(children: children, value: nil)
    }
    
    private func clearQueryCache() {
        queryCacheLock.lock()
        queryCache.removeAll()
        queryCacheLock.unlock()
    }
}

// Helper functions
private func normalize(_ v: Vector3Float) -> Vector3Float {
    let len = sqrt(v.x * v.x + v.y * v.y + v.z * v.z)
    if len == 0 { return v }
    return v / len
}
