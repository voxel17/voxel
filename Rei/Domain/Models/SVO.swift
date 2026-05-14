//
//  SVO.swift
//  Rei
//
//  Restructured SVO implementation
//

import Foundation

/// Sparse Voxel Octree node structure
struct SVONode {
    var children: [SVONode]
    var value: UInt8?  // nil = mixed node, otherwise material value
    
    init(children: [SVONode] = [], value: UInt8? = nil) {
        self.children = children
        self.value = value
    }
    
    var isLeaf: Bool {
        return value != nil
    }
}

/// SVO Node structure (for reference, though we use flattened array in shader)
struct SVONodeMetal {
    var children: (UInt32, UInt32, UInt32, UInt32, UInt32, UInt32, UInt32, UInt32)
    var value: UInt32
}

// MARK: - SVO Operations

/// Flattens SVO tree for GPU rendering
func flattenSVO(root: SVONode) -> [UInt32] {
    var output = [UInt32]()
    _ = pack(node: root, output: &output)
    return output
}

private func pack(node: SVONode, output: inout [UInt32]) -> Int {
    let nodeStart = output.count
    output.append(contentsOf: [UInt32](repeating: 0, count: 9))
    
    if let value = node.value {
        output[nodeStart + 8] = UInt32(value)
        return nodeStart
    }
    
    for i in 0..<node.children.count {
        if i < node.children.count {
            let childIndex = pack(node: node.children[i], output: &output)
            output[nodeStart + i] = UInt32(childIndex)
        }
    }
    output[nodeStart + 8] = UInt32.max
    return nodeStart
}

/// Builds SVO from voxel positions
func buildSVOFromVoxels(_ voxels: [(position: Vector3Int, value: UInt8)], gridSize: Int) -> SVONode {
    let sortedVoxels = voxels.sorted { a, b in
        if a.position.z != b.position.z { return a.position.z < b.position.z }
        if a.position.y != b.position.y { return a.position.y < b.position.y }
        return a.position.x < b.position.x
    }
    
    return buildNodeFromVoxels(sortedVoxels, x: 0, y: 0, z: 0, size: gridSize)
}

private func buildNodeFromVoxels(_ voxels: [(position: Vector3Int, value: UInt8)], 
                                 x: Int, y: Int, z: Int, size: Int) -> SVONode {
    let regionVoxels = voxels.filter { voxel in
        voxel.position.x >= x && voxel.position.x < x + size &&
        voxel.position.y >= y && voxel.position.y < y + size &&
        voxel.position.z >= z && voxel.position.z < z + size
    }
    
    if regionVoxels.isEmpty {
        return SVONode(children: [], value: 0)
    }
    
    if size == 1 {
        return SVONode(children: [], value: regionVoxels[0].value)
    }
    
    let firstValue = regionVoxels[0].value
    let allSame = regionVoxels.allSatisfy { $0.value == firstValue }
    if allSame && regionVoxels.count == size * size * size {
        return SVONode(children: [], value: firstValue)
    }
    
    let half = size / 2
    var children: [SVONode] = []
    
    for dz in 0..<2 {
        for dy in 0..<2 {
            for dx in 0..<2 {
                let childX = x + dx * half
                let childY = y + dy * half
                let childZ = z + dz * half
                children.append(buildNodeFromVoxels(regionVoxels, 
                                                   x: childX, y: childY, z: childZ, 
                                                   size: half))
            }
        }
    }
    
    return SVONode(children: children, value: nil)
}

/// Thread-safe SVO modifier
class SVOModifier {
    private let queue = DispatchQueue(label: "com.rei.svoModifier", 
                                     qos: .userInitiated, 
                                     attributes: .concurrent)
    
    func modifyNode(_ node: SVONode, at path: [Int], 
                   with value: UInt8, gridSize: Int) -> SVONode {
        guard !path.isEmpty, path.allSatisfy({ $0 >= 0 && $0 < 8 }) else {
            return node
        }
        
        return modifyNodeRecursive(node: node, path: path, depth: 0, 
                                  value: value, size: gridSize)
    }
    
    private func modifyNodeRecursive(node: SVONode, path: [Int], depth: Int, 
                                    value: UInt8, size: Int) -> SVONode {
        guard depth < path.count else {
            return SVONode(children: [], value: value)
        }
        
        let childIndex = path[depth]
        var children = node.children
        
        if let leafValue = node.value {
            children = (0..<8).map { _ in SVONode(children: [], value: leafValue) }
        }
        
        while children.count < 8 {
            children.append(SVONode(children: [], value: 0))
        }
        
        let newSize = size / 2
        children[childIndex] = modifyNodeRecursive(
            node: children[childIndex],
            path: path,
            depth: depth + 1,
            value: value,
            size: newSize
        )
        
        if let firstValue = children[0].value {
            let allSame = children.allSatisfy { $0.value == firstValue }
            if allSame {
                return SVONode(children: [], value: firstValue)
            }
        }
        
        return SVONode(children: children, value: nil)
    }
}
