//
// Shadow Volume Effect
//
#include "global.h"

shared float	ShadowVolumeOffset	: SHADOWVOLUMEOFFSET;
shared float4	LocalLightPos		: LOCALLIGHTPOS;
float4			DiffuseColour		: DIFFUSECOLOUR;

struct VS_INPUT
{
	float4 position : POSITION;
	float4 color    : COLOR;
	float4 texcoord : TEXCOORD;
};

struct VtoP
{
	float4 position : POSITION;
	float4 color    : COLOR0;
	float4 tex      : TEXCOORD0;
};

struct PS_OUTPUT
{
	float4 color : COLOR0;
};

VtoP solid_vertex_shader(const VS_INPUT IN)
{
	VtoP OUT;
	float4 p = mul(IN.position, WorldViewProj);
	OUT.position = p;
	OUT.tex = IN.texcoord;
    float4 diffuse = { 0.0f, 0.0f, 0.2f, 1.0f };    // soft blue
	OUT.color = diffuse;

	return OUT;
}

/////////////////////////////////////////////////////////////////////////////
//                                                                         //
//	debugRenderStencilBuffer								               //
//                                                                         //
/////////////////////////////////////////////////////////////////////////////

PS_OUTPUT flatshaded_pixelShader(VtoP IN)
{
	PS_OUTPUT OUT;
	OUT.color = IN.color;
	return OUT;
}


struct VS_INPUT2
{
	float4 position : POSITION;
};

VtoP volume_vertex_shader(const VS_INPUT2 IN)
{
	VtoP OUT;
    float4 diffuse = { 0.0f, 0.0f, 0.2f, 1.0f };    // soft blue
	OUT.color = diffuse;
	OUT.tex = float4(0.0f, 0.0f, 0.0f, 0.0f);

	//
	// Implement the shadow vertex calculations
	//
	
	// If LocalLightPos.w is zero then this is a directional light otherwise it is a position light

	// Offset vertex along light direction.
	float3 vLightDir = normalize( IN.position * LocalLightPos.w - LocalLightPos.xyz ); // V * Lw - L
	float3 vExtrudedPos = vLightDir * ( IN.position[3] * ShadowVolumeOffset ) + IN.position; // Add offset to pos

	// Transform (extruded) position
	float4 p = float4(vExtrudedPos,1.0f); 
    OUT.position = world_position(p);
    OUT.position.z += 0.001f;	//Tiny bias to improve self shadowing. Gets rid of precision artifacts
	return OUT;
}

PS_OUTPUT volume_pixel_shader(VtoP IN)
{
	PS_OUTPUT OUT;
	OUT.color = IN.color;
	return OUT;
}

technique debugShadowVolume
{
    pass p0
    {
        VertexShader = compile vs_1_1 volume_vertex_shader();
        PixelShader  = compile ps_1_1 flatshaded_pixelShader();
    }
}

VtoP flatshaded_vertexShader(const VS_INPUT IN)
{
	VtoP OUT;
	OUT.position = IN.position;
	OUT.tex = IN.texcoord;
	OUT.color = float4(1.0f, 1.0f, 0.0f, 0.35f);//(FlatShadedColour);
	return OUT;
}

technique debugRenderStencilBuffer
{
    pass p0
    {
        VertexShader = compile vs_1_1 flatshaded_vertexShader();
        PixelShader  = compile ps_1_1 flatshaded_pixelShader();
    }
}

technique StencilShadowVolumeMultiPass
{
    pass p0
    {
        VertexShader = compile vs_1_1 volume_vertex_shader();
        PixelShader  = NULL;
    }
    pass p1
    {
        VertexShader = compile vs_1_1 volume_vertex_shader();
        PixelShader  = NULL;
    }
}

technique StencilShadowVolume2Sided
{
    pass p0
    {
        VertexShader = compile vs_1_1 volume_vertex_shader();
        PixelShader  = NULL;//compile ps_1_1 volume_pixel_shader();
    }
}

/////////////////////////////////////////////////////////////////////////////
//                                                                         //
//	ShadowMap Mesh Techniques  											   //
//                                                                         //
/////////////////////////////////////////////////////////////////////////////

struct VtoP2
{
	float4 position : POSITION;
};

float4 shadowmapmesh_vertex_shader(const VS_INPUT2 IN) : POSITION
{
	float4 pos = world_position(IN.position);
	pos.z -= 0.001f;
	return pos;
}

float4 shadowmapmesh_pixelShader(VtoP2 IN) : COLOR0
{
	return DiffuseColour;
}

technique debugShadowMapMesh
{
    pass p0
    {
        VertexShader = compile vs_1_1 shadowmapmesh_vertex_shader();
        PixelShader  = compile ps_1_1 shadowmapmesh_pixelShader();
    }
}

technique shadowMapMesh
{
    pass p0
    {
        VertexShader = compile vs_1_1 shadowmapmesh_vertex_shader();
        //PixelShader  = compile ps_1_1 shadowmapmesh_pixelShader();
        PixelShader  = NULL;
    }
}
