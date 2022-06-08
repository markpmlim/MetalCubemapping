//
//  Shaders.metal
//  EquiRect2CubemapLH
//
//  Created by Mark Lim Pak Mun on 07/06/2022.
//  Copyright © 2022 Mark Lim Pak Mun. All rights reserved.
//

#include <metal_stdlib>
using namespace metal;

// The model has all 3 vertex attributes viz. position, normal & texture coordinates.
struct VertexIn {
    float3 position  [[attribute(0)]];
    float3 normal    [[attribute(1)]];
    float2 texCoords [[attribute(2)]];  // unused
};

struct VertexOut {
    float4 position [[position]];   // clip space
    float4 texCoords;               // float4 instead of float3
};

struct Uniforms {
    float4x4 projectionMatrix;
    float4x4 viewMatrix;
    float4x4 modelMatrix;
    float4x4 normalMatrix;
    float4 worldCameraPosition;
};

struct CubeVertex {
    float4 position  [[attribute(0)]];
    float2 texCoords [[attribute(1)]];  // unused
};

struct MappingVertex {
    float4 position [[position]];       // clip space
    float4 worldPosition;
    uint whichLayer [[render_target_array_index]];
};

// size=16 bytes
typedef struct
{
    float4x4 viewProjectionMatrix;
} InstanceParams;

#define SRGB_ALPHA 0.055

float linear_from_srgb(float x)
{
    if (x <= 0.04045)
        return x / 12.92;
    else
        return powr((x + SRGB_ALPHA) / (1.0 + SRGB_ALPHA), 2.4);
}

float3 linear_from_srgb(float3 rgb)
{
    return float3(linear_from_srgb(rgb.r),
                  linear_from_srgb(rgb.g),
                  linear_from_srgb(rgb.b));
}

vertex MappingVertex
cubeMapVertexShader(CubeVertex              vertexIn        [[stage_in]],
                    unsigned int            instanceId      [[instance_id]],
                    constant Uniforms       &uniforms       [[buffer(1)]],
                    device InstanceParams *instanceParms    [[buffer(2)]])
{
    float4 position = vertexIn.position;

    MappingVertex outVert;
    outVert.whichLayer = instanceId;
    // Transform vertex's position into clip space.
    //outVert.position = uniforms.projectionMatrix * uniforms.viewMatrix * position;
    outVert.position = instanceParms[instanceId].viewProjectionMatrix * position;
    // Its position (in object/model space) will be used to access the equiRectangular map texture.
    // Since there is no model matrix, its vertex position is deemed to be in world space.
    // Another way of looking at things is we may consider that the model matrix is the identity matrix.
    outVert.worldPosition = position;
    return outVert;
}


// Left-hand - this function is based on a DirectX Pixel Shader.
// Helper function
constant float2 invAtan = float2(1/(2*M_PI_F), 1/M_PI_F);   // float2(1/2π, 1/π);

// Working as expected. faceIndex no longer required.
float2 sampleSphericalMap_LH(float3 direction, uint faceIndex)
{
    // Original code:
    //      tan(θ) = dir.z/dir.x and sin(φ) = dir.y/1.0
    float2 uv = float2(atan2(direction.x, direction.z),
                       asin(-direction.y));

    // The range of u: [ -π,   π ] --> [-0.5, 0.5]
    // The range of v: [-π/2, π/2] --> [-0.5, 0.5]
    uv *= invAtan;
    uv += 0.5;          // [0, 1] for both u & v

    return uv;
}


// Render to an offscreen texture object in this case a 2D texture.
fragment half4
outputCubeMapTexture(MappingVertex      mappingVertex   [[stage_in]],
                     texture2d<half> equirectangularMap [[texture(0)]])
{
    constexpr sampler mapSampler(s_address::clamp_to_edge,  // default
                                 t_address::clamp_to_edge,
                                 mip_filter::linear,
                                 mag_filter::linear,
                                 min_filter::linear);

    // Magnitude of direction is 1.0 upon normalization.
    float3 direction = normalize(mappingVertex.worldPosition.xyz);
    uint faceIndex = mappingVertex.whichLayer;
    // The paramter faceIndex is not used.
    float2 uv = sampleSphericalMap_LH(direction, faceIndex);
    half4 color = equirectangularMap.sample(mapSampler, uv);

    return color;
}

///////

// Draw the skybox
vertex VertexOut
SkyboxVertexShader(VertexIn vertexIn             [[stage_in]],
                   constant Uniforms &uniforms   [[buffer(1)]])
{
    float4 position = float4(vertexIn.position, 1.0);
    
    VertexOut outVert;
    // Transform vertex's position into clip space.
    outVert.position = uniforms.projectionMatrix * uniforms.viewMatrix * uniforms.modelMatrix * position;
    // Its position (in object/model space) will be used to access the cube map texture.
    outVert.texCoords = position;
    return outVert;
}

// The Uniforms are not used but to be declared.
fragment float4
CubeLookupShader(VertexOut fragmentIn               [[stage_in]],
                 texturecube<float> cubemapTexture  [[texture(0)]],
                 constant Uniforms & uniforms       [[buffer(1)]])
{
    constexpr sampler cubeSampler(mip_filter::linear,
                                  mag_filter::linear,
                                  min_filter::linear);
    // Don't have to flip horizontally anymore.
    float3 texCoords = float3(fragmentIn.texCoords.x, fragmentIn.texCoords.y, fragmentIn.texCoords.z);
    return cubemapTexture.sample(cubeSampler, texCoords);
}

vertex VertexOut
ReflectionVertexShader(VertexIn vertexIn            [[stage_in]],
                       constant Uniforms &uniforms  [[buffer(1)]])
{
    // The position and normal of the incoming vertex in Object Space.
    // The w-component of position vectors should be set to 1.0
    float4 positionMC = float4(vertexIn.position, 1.0);
    // Normal is a vector; its w-component should be set 0.0
    float4 normalMC = float4(vertexIn.normal, 0.0);

    // We assume the camera's position is already expressed in world coordinates.
    float4 cameraPositionWC = uniforms.worldCameraPosition;
    // Transform vertex's position from model coordinates to world coordinates.
    float4 positionWC = uniforms.modelMatrix * positionMC;
    // Compute the direction of the incident ray which is from
    // the camera to the vertex in world space.
    float4 viewDirectionWC = normalize(positionWC - cameraPositionWC);

    VertexOut vertexOut;
    // Transform the normal from model space to world space.
    float4 normalWC = normalize(uniforms.normalMatrix * normalMC);
    // Compute the reflected ray; the direction of this ray will be used
    // to access the cubemap texture. No need to normalize since both
    // vectors are already normalized.
    vertexOut.texCoords = reflect(viewDirectionWC, normalWC);
    // Transform incoming vertex's position into clip space
    vertexOut.position = uniforms.projectionMatrix * uniforms.viewMatrix * positionWC;
    return vertexOut;
}
