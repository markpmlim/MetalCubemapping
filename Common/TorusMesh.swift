//
//  TorusMesh.swift
//  MetalCubemapping
//
//  Created by Mark Lim Pak Mun on 09/09/2020.
//  Copyright © 2020 Mark Lim Pak Mun. All rights reserved.
//

import Foundation
import Metal
import MetalKit
import SceneKit.ModelIO

class TorusMesh: Mesh {

    init?(ringRadius: Float, pipeRadius: Float,
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

        // A partially converted ModelIO vertex descriptor.
        let mdlVertexDesc = MTKModelIOVertexDescriptorFromMetal(vertexDescriptor)
        (mdlVertexDesc.attributes[0] as! MDLVertexAttribute).name = MDLVertexAttributePosition
        (mdlVertexDesc.attributes[1] as! MDLVertexAttribute).name = MDLVertexAttributeNormal
        (mdlVertexDesc.attributes[2] as! MDLVertexAttribute).name = MDLVertexAttributeTextureCoordinate

        // Use the built-in primitive
        let torus = SCNTorus(ringRadius: CGFloat(ringRadius),
                             pipeRadius: CGFloat(pipeRadius))
        torus.ringSegmentCount = 96
        torus.pipeSegmentCount = 48
        // To ensure the ring and pipe radii has immediate effect, do a SCNTransaction flush
        SCNTransaction.flush()
        let metalAllocator = MTKMeshBufferAllocator(device: device)
        let torusMesh = MDLMesh(scnGeometry: torus,
                                bufferAllocator: metalAllocator)
        torusMesh.vertexDescriptor = mdlVertexDesc
        do {
            let mtkMesh = try MTKMesh(mesh: torusMesh,
                                      device: device)
            // The MTKMesh object encapsulate 1 vertex buffer and one submesh
            let mtkVertexBuffer = mtkMesh.vertexBuffers[0]  // an instance of MTKMeshBuffer
            
            vertexBuffer = mtkVertexBuffer.buffer           // an instance of MTLBuffer
            vertexBufferOffset = mtkVertexBuffer.offset
            vertexBuffer.label = "Mesh Vertices"
            
            let submesh = mtkMesh.submeshes[0]              // an instance of MTKSubmesh
            let mtkIndexBuffer = submesh.indexBuffer        // an instance of MTKMeshBuffer
            primitiveType = submesh.primitiveType
            indexBuffer = mtkIndexBuffer.buffer             // an instance of MTLBuffer
            indexBufferOffset = mtkIndexBuffer.offset
            indexBuffer.label = "Mesh Indices"
            
            indexCount = submesh.indexCount
            indexType = submesh.indexType
        }
        catch {
            fatalError("Could not extract meshes from Model I/O asset")
        }
    }
}
