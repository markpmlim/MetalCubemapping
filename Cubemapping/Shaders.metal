
#include <metal_stdlib>
using namespace metal;
typedef struct
{
    ushort layer;
} InstanceParams;

typedef struct
{
    float4 renderedCoordinate [[position]]; // clip space
    float2 textureCoordinate;
    uint layer[[render_target_array_index]];
} TextureMappingVertex;

// Projects provided vertices to corners of offscreen texture.
vertex TextureMappingVertex
projectTexture(unsigned int vertex_id  [[ vertex_id ]],
               unsigned int instanceId [[ instance_id ]])
{
    // Triangle strip in NDC (normalized device coords).
    // The vertices' coord system has (-1, -1) at the bottom left.
    float4x4 renderedCoordinates = float4x4(float4(-1.0, -1.0, 0.0, 1.0),
                                            float4( 1.0, -1.0, 0.0, 1.0),
                                            float4(-1.0,  1.0, 0.0, 1.0),
                                            float4( 1.0,  1.0, 0.0, 1.0));
    // The texture coord system has (0, 0) at the upper left
    // The s-axis is +ve right and the t-axis is +ve down
    float4x2 textureCoordinates = float4x2(float2(0.0, 1.0),
                                           float2(1.0, 1.0),
                                           float2(0.0, 0.0),
                                           float2(1.0, 0.0));
    TextureMappingVertex outVertex;
    outVertex.renderedCoordinate = renderedCoordinates[vertex_id];
    outVertex.textureCoordinate = textureCoordinates[vertex_id];
    outVertex.layer = instanceId;
    return outVertex;
}

constexpr sampler sampl(address::clamp_to_edge,
                        filter::linear,
                        coord::normalized);

fragment half4
outputCubeMapTexture(TextureMappingVertex                       mappingVertex   [[stage_in]],
                     array<texture2d<float, access::sample>, 6> colorTextures   [[texture(0)]])
{
    uint whichTexture = mappingVertex.layer;
    float4 colorFrag = colorTextures[whichTexture].sample(sampl,
                                                          mappingVertex.textureCoordinate);
    return half4(colorFrag);
}

///////////////////////////////////////////////////////////////////////////////
// The model has all 3 vertex attributes viz. position, normal & texture coordinates.
struct VertexIn {
    float3 position  [[attribute(0)]];
    float3 normal    [[attribute(1)]];
    float2 texCoords [[attribute(2)]];  // unused
};

struct VertexOut
{
    float4 position [[position]];   // clip space
    float4 texCoords;               // float4 instead of float3
};

struct Uniforms {
    float4x4 modelMatrix;
    float4x4 viewMatrix;
    float4x4 projectionMatrix;
    float4x4 normalMatrix;
    float4 worldCameraPosition;
};

// Credit: Warren Moore - Cubic Environment Mapping.
// David Wolff: OpenGL 4.0 Shading Language Cookbook
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
    // the view direction & normal vectors are already normalized.
    vertexOut.texCoords = reflect(viewDirectionWC, normalWC);
    // Transform incoming vertex's position into clip space
    vertexOut.position = uniforms.projectionMatrix * uniforms.viewMatrix * positionWC;
	return vertexOut;
}

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

// The uniforms parameter is declared but not used.
fragment float4
CubeLookupShader(VertexOut fragmentIn               [[stage_in]],
                 texturecube<float> cubemapTexture  [[texture(0)]],
                 constant Uniforms & uniforms       [[buffer(1)]])
{
    constexpr sampler cubeSampler(mip_filter::linear,
                                  mag_filter::linear,
                                  min_filter::linear);

    // The 3D coordinate system of the cube map is left-handed as viewed from the inside of the cube.
    // So we must add a '-' to z-coord if the skybox is projected with the right-hand rule.
    // We have set Front Facing to be anti-clockwise.
    float3 texCoords = float3(fragmentIn.texCoords.x, fragmentIn.texCoords.y, -fragmentIn.texCoords.z);
    return cubemapTexture.sample(cubeSampler, texCoords);
}
