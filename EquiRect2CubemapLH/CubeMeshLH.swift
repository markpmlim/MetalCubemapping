//
//  CubeMesh.swift
//  MetalCubemapping
//
//  Created by Mark Lim Pak Mun on 12/04/2022.
//  Copyright © 2022 Mark Lim Pak Mun. All rights reserved.
//

import Foundation
import Metal
import MetalKit
import SceneKit.ModelIO

// Shows how to build a mesh from scratch.
// Instantiate a 2x2x2 units cube.
class CubeMesh: Mesh {
    
    // size=24 bytes; alignment=16 bytes; stride=32 bytes
    struct CubeVertex {
        let position: float4    // 16 bytes
        let uv: float2          //  8 bytes
    }
    
    init?(device: MTLDevice) {
        
        super.init()
        let cubeVertexDescriptor = MTLVertexDescriptor()
        // Positions.
        cubeVertexDescriptor.attributes[0].format = .float4
        cubeVertexDescriptor.attributes[0].offset = 0
        cubeVertexDescriptor.attributes[0].bufferIndex = 0
        
        // Texture coordinates.
        cubeVertexDescriptor.attributes[1].format = .float2
        cubeVertexDescriptor.attributes[1].offset = MemoryLayout<float4>.stride
        cubeVertexDescriptor.attributes[1].bufferIndex = 0
        
        // Generic Attribute Buffer Layout
        cubeVertexDescriptor.layouts[0].stride = MemoryLayout<CubeVertex>.stride
        cubeVertexDescriptor.layouts[0].stepRate = 1
        cubeVertexDescriptor.layouts[0].stepFunction = .perVertex
        
        vertexDescriptor = cubeVertexDescriptor
        // vertices of cube
        var cubeVertices = [CubeVertex](repeating: CubeVertex(position: float4(0,0,0,0),
                                                              uv: float2(0,0)),
                                        count: 24)
        
        // Normals and texture coordinates are not needed since only the vertices
        // are required when converting the equirectangular map to a cubemap.
        // left face - ccw when viewed from right
        cubeVertices[ 0] = CubeVertex(position: float4(-1.0,  1.0, -1.0, 1.0), uv: float2(0.0, 0.0))
        cubeVertices[ 1] = CubeVertex(position: float4(-1.0,  1.0,  1.0, 1.0), uv: float2(1.0, 0.0))
        cubeVertices[ 2] = CubeVertex(position: float4(-1.0, -1.0, -1.0, 1.0), uv: float2(0.0, 1.0))
        cubeVertices[ 3] = CubeVertex(position: float4(-1.0, -1.0,  1.0, 1.0), uv: float2(1.0, 1.0))
        
        // right face - cw when viewed from right
        cubeVertices[ 4] = CubeVertex(position: float4(1.0,  1.0,  1.0, 1.0), uv: float2(0.0, 0.0))
        cubeVertices[ 5] = CubeVertex(position: float4(1.0,  1.0, -1.0, 1.0), uv: float2(1.0, 0.0))
        cubeVertices[ 6] = CubeVertex(position: float4(1.0, -1.0,  1.0, 1.0), uv: float2(0.0, 1.0))
        cubeVertices[ 7] = CubeVertex(position: float4(1.0, -1.0, -1.0, 1.0), uv: float2(1.0, 1.0))
        
        // bottom face - ccw when viewed from top
        cubeVertices[ 8] = CubeVertex(position: float4(-1.0, -1.0,  1.0, 1.0), uv: float2(0.0, 0.0))
        cubeVertices[ 9] = CubeVertex(position: float4( 1.0, -1.0,  1.0, 1.0), uv: float2(1.0, 0.0))
        cubeVertices[10] = CubeVertex(position: float4(-1.0, -1.0, -1.0, 1.0), uv: float2(0.0, 1.0))
        cubeVertices[11] = CubeVertex(position: float4( 1.0, -1.0, -1.0, 1.0), uv: float2(1.0, 1.0))
        
        // top face - cw when viewed from top
        cubeVertices[12] = CubeVertex(position: float4(-1.0, 1.0, -1.0, 1.0), uv: float2(0.0, 0.0))
        cubeVertices[13] = CubeVertex(position: float4( 1.0, 1.0, -1.0, 1.0), uv: float2(1.0, 0.0))
        cubeVertices[14] = CubeVertex(position: float4(-1.0, 1.0,  1.0, 1.0), uv: float2(0.0, 1.0))
        cubeVertices[15] = CubeVertex(position: float4( 1.0, 1.0,  1.0, 1.0), uv: float2(1.0, 1.0))
        
        // back face - ccw when viewed from front
        cubeVertices[16] = CubeVertex(position: float4( 1.0,  1.0, -1.0, 1.0), uv: float2(0.0, 0.0))
        cubeVertices[17] = CubeVertex(position: float4(-1.0,  1.0, -1.0, 1.0), uv: float2(1.0, 0.0))
        cubeVertices[18] = CubeVertex(position: float4( 1.0, -1.0, -1.0, 1.0), uv: float2(0.0, 1.0))
        cubeVertices[19] = CubeVertex(position: float4(-1.0, -1.0, -1.0, 1.0), uv: float2(1.0, 1.0))
        
        // front face - cw when viewed from front
        cubeVertices[20] = CubeVertex(position: float4(-1.0,  1.0, 1.0, 1.0), uv: float2(0.0, 0.0))
        cubeVertices[21] = CubeVertex(position: float4( 1.0,  1.0, 1.0, 1.0), uv: float2(1.0, 0.0))
        cubeVertices[22] = CubeVertex(position: float4(-1.0, -1.0, 1.0, 1.0), uv: float2(0.0, 1.0))
        cubeVertices[23] = CubeVertex(position: float4( 1.0, -1.0, 1.0, 1.0), uv: float2(1.0, 1.0))

        vertexBuffer = device.makeBuffer(bytes: cubeVertices,
                                         length: MemoryLayout<CubeVertex>.stride * cubeVertices.count,
                                         options: [])
        vertexBuffer.label = "Cube Mesh Vertices"
        vertexBufferOffset = 0
        primitiveType = .triangle

        // each quad is a triangle fan.
        let cubeIndices: [UInt16] = [
            0, 1, 3,     0, 3, 2,   // left
            4, 5, 7,     4, 7, 6,   // right
            8, 9,11,     8,11,10,   // bottom
            12,13,15,   12,15,14,   // top
            16,17,19,   16,19,18,   // back
            20,21,23,   20,23,22,   // front
        ]
        
        indexBuffer = device.makeBuffer(bytes: cubeIndices,
                                        length: MemoryLayout<UInt16>.stride * cubeIndices.count,
                                        options: [])
        indexBuffer.label = "Cube Indices"
        indexCount = cubeIndices.count
        indexType = .uint16
        indexBufferOffset = 0
    }
}
