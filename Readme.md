This project consists of 3 Demos involving the setting up of a cubic environment map.


**Demo 1: Cubemapping.** 

It applies the concept of layer rendering in Metal to create a cube texture which will be displayed as a background environment map.

Metal applications have 2 other ways of creating a cube map texture. One method is to instantiate six instances of 2D MTLTexture from 6 graphic images. The MTLTextureDescriptor class function is then called

```swift
        textureCubeDescriptor(pixelFormat:, size:, mipmapped:)
```
to create a 3D cube MTLTexture. The pixels of the six 2D MTLTextures are copied to 6 slices of the 3D cube MTLTexture.


Another method is to call the MTLTextureLoader function:

```swift
	newTexture(name:, scaleFactor:, bundle:, options:)
```

to load the 6 images to instantiate the cubemap texture. These 6 images are placed in a cubetexture set within the application's Assets.xcassets folder.

(See Apple's "LODwithFunctionSpecialization" or "Deferred Lighting" demo.)

Once the cubemap texture is created, it can be applied to a skybox or used to texture the 6 faces of a box.

This demo will also perform a simulation of a reflection of the environment. 


Details on creating a cube map using layer rendering in Metal
The cubemap texture is created using the following procedure:

a) Six square graphic images are loaded and instantiated as NSImage objects. An array of 6 CGImages are created from these NSImage instances.

b) They are converted into instances of MTLTextures (type2D) using the MTKTextureLoader function

```swift
	newTexture(cgImage:, options:)
```

c) The MTLRenderPassDescriptor and MTLRenderPipelineDescriptor objects of an offscreen renderer are setup. To apply the idea of layer rendering in Metal, the renderTargetArrayLength property of the MTLRenderPassDescriptor object is set to 6. Any value more than 0 will enable layer rendering. The inputPrimitiveTopology property of the MTLRenderPipelineDescriptor object must be set to "MTLPrimitiveTopologyClass.triangle" since layered rendering is enabled.

d) The 6 slices of the cube map are then rendered during a render pass using a MTLRenderCommandEncoder object. Refer to the function "createCubemapTexture".


For best performance during rendering to screen, the cubemap texture should be created before entering the main display loop.


Once the cubemap texture is created, a second MTLRenderCommandEncoder object uses it to draw a skybox.

A third MTLRenderCommandEncoder object uses the cubemap texture to simulate a reflection of the environment as displayed by the skybox.

Both the second and third render passes are executed within the main display loop.




**Demo 2: Convert six 2D Cubic environment maps to an EquiRectangular map.**

This demo loads and instantiates a MTLTexture of type MTLTextureTypeCube from 6 .HDR files located in the "Images" folder of this project. Two sets of .HDR files are provided; the sets have been converted from the files equirectImage.hdr and newport_loft.hdr.

An offscreen renderer is called to convert the six 2D Cubic environment maps to a 1:1 EquiRectangular projection (aka Spherical Projection) map.

Finally, within the main rendering loop, the generated EquiRectangular map is displayed as 2:1 rectangular image. We have to scale the geometry (a 4:2 quad) to fit Metal's [2,2,1] NDC (normalised device coordinates) box.


The texture output by the fragment function "outputEquiRectangularTexture" can be saved to disk by pressing an "s"/"S" key. To output the 1:1 EquiRectangular map as a 2:1 graphic, an Affine transformation is performed on the generated 1:1 graphic.

Note: the previous iteration of this demo uses a special function to load hdr. The EquiRectangular map was saved in HEIC format. Currently, the demo using 2 C functions viz. stbi_loadf() and stbi_write_hdr from the stb_image library to load and save the hdr images.



**Demo 3: Convert an EquiRectangular image to six 2D images.**

This demo converts an EquiRectangular image (2:1) to six 2D images by rendering to an off-screen cube texture (MTLTextureTypeCube)

Once the view is displayed, the user may save the six 2D images generated by this Metal application to disk by pressing "s" or "S". He/she can visually compare the six 2D images (.hdr) with those within the "Images" folder of this project. The images within this folder were obtained by running the WebGL program at the link:

 https://matheowis.github.io/HDRI-to-CubeMap/


Due the differences between coordinate systems between Metal and OpenGL, some minor modifications to the original fragment shader code is necessary. For instance, the 2D texture coordinate system in Metal is as follows:

- origin: top left hand corner of the 2x2 quad with
-   the s-axis: horizontally from left to right, and,
-   the t-axis: vertically from top to bottom.


In OpenGL, the texture coordinate system is:

- origin: lower left hand corner of the 2x2 quad with
-   the s-axis: horizontally from left to right, and,
-   the t-axis: vertically from bottom to top.

A previous iteration of this demo did not generate the six 2D textures in the correct order. If the following OpenGL fragment shader is run,

```glsl
#version 330 core

out vec4 FragColor;

in vec3 WorldPos;

uniform sampler2D equirectangularMap;

const vec2 invAtan = vec2(0.1591, 0.3183);

vec2 SampleSphericalMap(vec3 v)
{
    vec2 uv = vec2(atan(v.z, v.x),
                   asin(v.y));
    uv *= invAtan;
    uv += 0.5;
    return uv;
}

void main()
{
    vec2 uv = SampleSphericalMap(normalize(WorldPos));
    vec3 color = texture(equirectangularMap, uv).rgb;

    FragColor = vec4(color, 1.0);
}

the order of output files is unexpected.
```

|Expected order|	Generated order |
| :---: | :---: |
|	+X |                     +Z|
|	-X |                     -Z|
|	+Y |                     +Y|	                rotated 90 deg anti-clockwise (orientation)
|	-Y |                     -Y|	                rotated 90 deg clockwise (orientation)
|	+Z |                     -X|
|	-Z |                     +X|

As can be observed from the table above, 4 of the faces are not in the correct order.
Also, the orientation of the top and bottom faces are wrong.

If the line

```glsl
    vec2 uv = vec2(atan(v.z, v.x),
                   asin(v.y));

is changed to

    vec2 uv = vec2(atan(v.x, v.z),
                   asin(v.y));
```

the six faces are generated in the correct order and orientation. This discrepancy could be due to the implementation in OpenGL drivers in macOS. 


The Metal fragment shader function of this demo is a port of the above OpenGL fragment shader program with some modifications. Because the coordinate systems in Metal and OpenGL are different, the line of code listed above have to be written as:

```cpp
    float2 uv;
    if (faceIndex == 2 || faceIndex == 3)
    {   // top, bottom
        uv = float2(atan2(direction.x, -direction.z),
                    -asin(direction.y));
    }
    else
    {
        // left, right, front, back.
        uv = float2(atan2(direction.x, direction.z),
                    asin(direction.y));

    }
```


**Requirements:** XCode 9.x, Swift 4.x and macOS 10.13.4 or later.

**References:**

https://learnopengl.com/PBR/IBL/Diffuse-irradiance

http://paulbourke.net/panorama/cubemaps/index.html

https://metalbyexample.com

