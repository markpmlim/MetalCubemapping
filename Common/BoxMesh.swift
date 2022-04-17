//
//  BoxMesh.swift
//  MetalCubemapping
//
//  Created by Mark Lim Pak Mun on 09/09/2020.
//  Copyright © 2020 Mark Lim Pak Mun. All rights reserved.
//

import Foundation
import Metal
import MetalKit
import SceneKit.ModelIO

class BoxMesh: Mesh {

    init?(withSize size: Float,
          device: MTLDevice) {
 
        super.init()
        vertexDescriptor = MTLVertexDescriptor()
        vertexDescriptor.attributes[0].format = MTLVertexFormat.float3
        vertexDescriptor.attributes[0].offset = 0
        vertexDescriptor.attributes[0].bufferIndex = 0
        vertexDescriptor.attributes[1].format = MTLVertexFormat.float3
        vertexDescriptor.attributes[1].offset = 3 * MemoryLayout<Float>.stride
        vertexDescriptor.attributes[1].bufferIndex = 0
        vertexDescriptor.attributes[2].format = MTLVertexFormat.float2
        vertexDescriptor.attributes[2].offset = 6 * MemoryLayout<Float>.stride
        vertexDescriptor.attributes[2].bufferIndex = 0
        vertexDescriptor.layouts[0].stride = 8 * MemoryLayout<Float>.stride
        vertexDescriptor.layouts[0].stepRate = 1
        vertexDescriptor.layouts[0].stepFunction = .perVertex

        // Indicate how each Metal vertex descriptor attribute maps to each Model I/O  attribute
        let boxMDLVertexDescriptor = MTKModelIOVertexDescriptorFromMetal(vertexDescriptor)
        (boxMDLVertexDescriptor.attributes[0] as! MDLVertexAttribute).name = MDLVertexAttributePosition
        (boxMDLVertexDescriptor.attributes[1] as! MDLVertexAttribute).name = MDLVertexAttributeNormal
        (boxMDLVertexDescriptor.attributes[2] as! MDLVertexAttribute).name = MDLVertexAttributeTextureCoordinate

        let allocator = MTKMeshBufferAllocator(device: device)

        let boxMDLMesh = MDLMesh.newBox(withDimensions: [size,size,size],
                                        segments: [1,1,1],
                                        geometryType: .triangles,
                                        inwardNormals: true,
                                        allocator: allocator)

        // Apply the Model I/O vertex descriptor we created to match the Metal vertex descriptor.
        // Set our vertex descriptor to re-layout the vertex data
        boxMDLMesh.vertexDescriptor = boxMDLVertexDescriptor

        do {
            let mtkMesh = try MTKMesh(mesh: boxMDLMesh,
                                     device: device)

            let mtkVertexBuffer = mtkMesh.vertexBuffers[0]  // an instance of MTKMeshBuffer
            let submesh = mtkMesh.submeshes[0]              // an instance of MTKSubmesh
            let mtkIndexBuffer = submesh.indexBuffer        // an instance of MTKMeshBuffer

            vertexBuffer = mtkVertexBuffer.buffer           // an instance of MTLBuffer
            vertexBufferOffset = mtkVertexBuffer.offset     // added
            vertexBuffer.label = "Box Mesh Vertices"

            primitiveType = submesh.primitiveType
            indexBuffer = mtkIndexBuffer.buffer             // an instance of MTLBuffer
            indexBufferOffset = mtkIndexBuffer.offset       // added
            indexBuffer.label = "Box Indices"

            indexCount = submesh.indexCount
            indexType = submesh.indexType
        }
        catch _ {
           // Unable to create MTK mesh from MDL mesh
           print("Can't create Box mesh")
           return nil
        }
    }
}
