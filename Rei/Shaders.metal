#include <metal_stdlib>
using namespace metal;

struct SVONode {
    uint children[8];
    uint value;
};

struct CameraUniforms {
    float4x4 viewMatrix;
    float4x4 projectionMatrix;
    float4x4 inverseViewMatrix;
    float4x4 inverseProjectionMatrix;
    float3 position;
    float nearPlane;
    float farPlane;
    float fov;
};

struct SVOData {
    uint rootIndex;
    uint gridSize;
    float voxelSize;
    float3 gridOrigin;
};

bool isLeaf(uint value) {
    return value != UINT_MAX;
}

float traverseSVO(device const uint* flatSVO, constant SVOData& svoData, int3 pos, thread float& surfaceValue, thread int& nodeSize) {
    int x = pos.x, y = pos.y, z = pos.z;
    int size = int(svoData.gridSize);
    uint nodeIndex = svoData.rootIndex;
    float voxelValue = 0;
    bool found = false;
    
    int maxDepth = 0;
    int tempSize = size;
    while (tempSize > 1) {
        tempSize /= 2;
        maxDepth++;
    }
    maxDepth = min(maxDepth, 8);
    
    for (int depth = 0; depth < maxDepth; depth++) {
        if (nodeIndex >= 0xFFFFFFFF) break;
        
        uint nodeValue = flatSVO[nodeIndex + 8];
        
        if (nodeValue != UINT_MAX) {
            voxelValue = float(nodeValue);
            found = (nodeValue != 0);
            nodeSize = size;
            break;
        }
        
        if (size <= 1) break;
        
        int halfSize = size / 2;
        
        int childX = (x >= halfSize) ? 1 : 0;
        int childY = (y >= halfSize) ? 1 : 0;
        int childZ = (z >= halfSize) ? 1 : 0;
        int childIndex = (childZ * 4) + (childY * 2) + childX;
        
        uint childNodeIndex = flatSVO[nodeIndex + childIndex];
        
        if (childNodeIndex == 0) {
            found = false;
            break;
        }
        
        x = x % halfSize;
        y = y % halfSize;
        z = z % halfSize;
        
        nodeIndex = childNodeIndex;
        size = halfSize;
    }
    
    if (found && voxelValue != 0) {
        surfaceValue = voxelValue;
        return 1.0;
    }
    
    return 0.0;
}

float4 getVoxelColor(float value, float3 normal, float3 lightDir) {
    float diffuse = max(dot(normal, lightDir), 0.0);
    float ambient = 0.15;
    float lighting = ambient + diffuse * 0.85;
    
    float shadow = 0.5 + 0.5 * dot(normal, float3(0, 1, 0));
    
    int voxelValue = int(value);
    
    if (voxelValue == 1) { // stone
        return float4(0.5, 0.5, 0.5, 1.0) * lighting * shadow;
    } else if (voxelValue == 2) { // grass
        return float4(0.3, 0.6, 0.3, 1.0) * lighting * shadow;
    } else if (voxelValue == 3) { // bedrock
        return float4(0.2, 0.2, 0.2, 1.0) * lighting * shadow;
    } else if (voxelValue == 4) { // dirt
        return float4(0.4, 0.3, 0.2, 1.0) * lighting * shadow;
    } else if (voxelValue == 5) { // stone_deep
        return float4(0.3, 0.3, 0.4, 1.0) * lighting * shadow;
    } else {
        float br = float(voxelValue) / 255.0;
        return float4(br, br, br, 1.0) * lighting;
    }
}

kernel void renderScene(
    texture2d<float, access::write> output [[texture(0)]],
    device const uint* flatSVO [[buffer(0)]],
    constant SVOData& svoData [[buffer(1)]],
    constant CameraUniforms& camera [[buffer(2)]],
    uint2 gid [[thread_position_in_grid]],
    uint2 threadCount [[threads_per_grid]])
{
    uint widthPixels = output.get_width();
    uint heightPixels = output.get_height();

    if (gid.x >= widthPixels || gid.y >= heightPixels) {
        return;
    }

    float width = float(widthPixels);
    float height = float(heightPixels);
    
    float2 uv = float2(
        (float(gid.x) + 0.5f) / width,
        1.0f - ((float(gid.y) + 0.5f) / height)
    );
    
    float2 ndc = uv * 2.0f - 1.0f;
    
    float4 rayClip = float4(ndc.x, ndc.y, -1.0f, 1.0f);
    float4 rayEye = camera.inverseProjectionMatrix * rayClip;
    rayEye = float4(rayEye.xy, -1.0f, 0.0f);
    float4 rayWorld = camera.inverseViewMatrix * rayEye;
    
    float3 rayOrigin = camera.position;
    float3 rayDir = normalize(rayWorld.xyz);
    
    // Convert ray origin to grid space
    float3 gridOrigin = svoData.gridOrigin;
    float voxelSize = svoData.voxelSize;
    int gridSize = int(svoData.gridSize);
    
    // Transform ray origin to grid-local coordinates (0 to gridSize)
    float3 localOrigin = (rayOrigin - gridOrigin) / voxelSize;
    
    // DDA setup in grid space
    int3 mapPos = int3(floor(localOrigin));
    
    // Clamp to grid bounds
    mapPos = clamp(mapPos, int3(0), int3(gridSize - 1));
    
    float3 deltaDist = abs(1.0f / (rayDir + 0.0001f));
    
    int3 step;
    float3 sideDist;
    
    // Calculate step direction and initial side distances
    if (rayDir.x < 0) {
        step.x = -1;
        sideDist.x = (localOrigin.x - float(mapPos.x)) * deltaDist.x;
    } else {
        step.x = 1;
        sideDist.x = (float(mapPos.x + 1) - localOrigin.x) * deltaDist.x;
    }
    
    if (rayDir.y < 0) {
        step.y = -1;
        sideDist.y = (localOrigin.y - float(mapPos.y)) * deltaDist.y;
    } else {
        step.y = 1;
        sideDist.y = (float(mapPos.y + 1) - localOrigin.y) * deltaDist.y;
    }
    
    if (rayDir.z < 0) {
        step.z = -1;
        sideDist.z = (localOrigin.z - float(mapPos.z)) * deltaDist.z;
    } else {
        step.z = 1;
        sideDist.z = (float(mapPos.z + 1) - localOrigin.z) * deltaDist.z;
    }
    
    int side = 0;
    float distance = 0.0;
    const float maxDistance = 500.0;
    const int maxSteps = 1024;
    
    // Ray marching loop
    for (int i = 0; i < maxSteps; i++) {
        // Calculate actual world distance traveled
        distance = (sideDist.x < sideDist.y) ?
                   ((sideDist.x < sideDist.z) ? sideDist.x : sideDist.z) :
                   ((sideDist.y < sideDist.z) ? sideDist.y : sideDist.z);
        
        if (distance > maxDistance) {
            break;
        }
        
        // Bounds check in grid space
        if (mapPos.x < 0 || mapPos.x >= gridSize ||
            mapPos.y < 0 || mapPos.y >= gridSize ||
            mapPos.z < 0 || mapPos.z >= gridSize) {
            break;
        }
        
        // Query SVO at current grid position
        float voxelValue = 0;
        int nodeSize = 1;
        float hit = traverseSVO(flatSVO, svoData, mapPos, voxelValue, nodeSize);
        
        if (hit > 0.5 && voxelValue != 0) {
            // Determine hit normal based on which side we entered from
            float3 hitNormal;
            if (side == 0) hitNormal = float3(-float(step.x), 0, 0);
            else if (side == 1) hitNormal = float3(0, -float(step.y), 0);
            else hitNormal = float3(0, 0, -float(step.z));
            
            // Calculate lighting
            float3 lightDir = normalize(float3(0.5, 1.0, 0.3));
            
            // Add distance-based ambient occlusion
            float ao = 1.0 - min(1.0, distance / 200.0) * 0.3;
            
            // Get color
            float4 color = getVoxelColor(voxelValue, hitNormal, lightDir);
            color *= ao;
            
            // LOD visualization
            if (nodeSize > 1) {
                float lodFactor = float(nodeSize) / float(gridSize);
                float3 gray = float3(dot(color.rgb, float3(0.299, 0.587, 0.114)));
                color.rgb = mix(color.rgb, gray, lodFactor * 0.2);
            }
            
            // Add fog effect
            float fogFactor = exp(-distance * 0.002);
            fogFactor = clamp(fogFactor, 0.3, 1.0);
            float4 fogColor = float4(0.2, 0.3, 0.5, 1.0);
            color = mix(fogColor, color, fogFactor);
            
            output.write(color, gid);
            return;
        }
        
        // DDA step - move to next voxel boundary
        if (sideDist.x <= sideDist.y && sideDist.x <= sideDist.z) {
            sideDist.x += deltaDist.x;
            mapPos.x += step.x;
            side = 0;
        } else if (sideDist.y <= sideDist.z) {
            sideDist.y += deltaDist.y;
            mapPos.y += step.y;
            side = 1;
        } else {
            sideDist.z += deltaDist.z;
            mapPos.z += step.z;
            side = 2;
        }
    }
    
    // Sky gradient
    float skyBlend = max(0.0, rayDir.y * 0.5 + 0.5);
    float4 skyBottom = float4(0.2, 0.3, 0.5, 1.0);
    float4 skyTop = float4(0.05, 0.05, 0.15, 1.0);
    
    float3 sunDir = normalize(float3(0.5, 0.8, 0.2));
    float sunFactor = pow(max(0.0, dot(rayDir, sunDir)), 50.0);
    float4 sunColor = float4(1.0, 0.8, 0.5, 1.0);
    
    float4 finalSky = mix(skyBottom, skyTop, skyBlend);
    finalSky = mix(finalSky, sunColor, sunFactor);
    
    output.write(finalSky, gid);
}

struct ScaleVertexOut {
    float4 position [[position]];
    float2 texcoord;
};

vertex ScaleVertexOut scale_vertex(uint vertexID [[vertex_id]]) {
    ScaleVertexOut out;
    float2 positions[4] = {
        float2(-1.0, -1.0),
        float2( 1.0, -1.0),
        float2(-1.0,  1.0),
        float2( 1.0,  1.0)
    };
    float2 texcoords[4] = {
        float2(0.0, 1.0),
        float2(1.0, 1.0),
        float2(0.0, 0.0),
        float2(1.0, 0.0)
    };
    out.position = float4(positions[vertexID], 0.0, 1.0);
    out.texcoord = texcoords[vertexID];
    return out;
}

fragment float4 scale_fragment(ScaleVertexOut in [[stage_in]],
                               texture2d<float> tex [[texture(0)]],
                               sampler smp [[sampler(0)]]) {
    return tex.sample(smp, in.texcoord);
}

fragment float4 scale_fragment_interpolated(ScaleVertexOut in [[stage_in]],
                                            texture2d<float> currentTex [[texture(0)]],
                                            texture2d<float> previousTex [[texture(1)]],
                                            constant float& interpolationFactor [[buffer(0)]],
                                            constant float& scaleFactor [[buffer(1)]],
                                            sampler smp [[sampler(0)]]) {
    float2 scaledUV = in.texcoord;
    
    if (scaleFactor < 0.99) {
        float2 scale = float2(scaleFactor, scaleFactor);
        float2 offset = (1.0 - scale) * 0.5;
        scaledUV = in.texcoord * scale + offset;
        scaledUV = clamp(scaledUV, 0.001, 0.999);
    }
    
    float4 currentColor = currentTex.sample(smp, scaledUV);
    float4 previousColor = previousTex.sample(smp, scaledUV);
    
    float4 finalColor = mix(previousColor, currentColor, interpolationFactor);
    
    if (scaleFactor < 0.8) {
        float2 texelSize = 1.0 / float2(currentTex.get_width(), currentTex.get_height());
        float4 sharpened = currentColor * 1.2;
        
        for (int x = -1; x <= 1; x++) {
            for (int y = -1; y <= 1; y++) {
                if (x == 0 && y == 0) continue;
                float2 offset = float2(x, y) * texelSize;
                sharpened -= currentTex.sample(smp, scaledUV + offset) * 0.025;
            }
        }
        
        finalColor = mix(finalColor, sharpened, 0.3);
    }
    
    return finalColor;
}
