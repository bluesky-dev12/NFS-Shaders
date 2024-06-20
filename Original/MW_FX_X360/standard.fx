//
// Standard Effect
//
#include "global.h"

float4x4 WorldView				: WORLDVIEW;
float4x4 World					: WORLDMAT;
shared float4 TextureOffset		: TEXTUREANIMOFFSET;
shared float4x4 TextureOffsetMatrix : TEXTUREOFFSETMATRIX;
float4 DiffuseColour				: DIFFUSECOLOUR;

float Brightness				: STANDARD_BRIGHTNESS;

sampler DIFFUSEMAP_SAMPLER = sampler_state
{
	AddressU = WRAP;
	AddressV = WRAP;
	MIPFILTER = LINEAR;
	MINFILTER = LINEAR;
	MAGFILTER = LINEAR;
};

sampler OPACITYMAP_SAMPLER = sampler_state
{
	AddressU = CLAMP;
	AddressV = CLAMP;
	MIPFILTER = LINEAR;
	MINFILTER = LINEAR;
	MAGFILTER = LINEAR;
};

struct VS_INPUT
{
	float4 position : POSITION;
	float4 color    : COLOR;
	float4 tex		: TEXCOORD;
	float4 tex1		: TEXCOORD1;
	float3 normal	: NORMAL;
};

struct VtoP
{
	float4 position : POSITION;
	float4 color    : COLOR0;
	float4 tex      : TEXCOORD0;
	float4 tex1     : TEXCOORD1;
};

struct PS_OUTPUT
{
	float4 color : COLOR0;
};

struct VtoP_Depth
{
	float4 position : POSITION;
	float dist		: COLOR0;
};

//-----------------------------------------------------------------------------
// STANDARD
//
VtoP vertex_shader(const VS_INPUT IN)
{
	VtoP OUT;
	OUT.position = world_position(IN.position);
	OUT.tex = IN.tex + TextureOffset;
	OUT.tex1 = IN.tex1;
	OUT.color = IN.color * DiffuseColour;

	return OUT;
}

PS_OUTPUT pixel_shader(const VtoP IN)
{
	PS_OUTPUT OUT;

	float4 diffuse = tex2D(DIFFUSEMAP_SAMPLER, IN.tex);
	float4 mask	   = tex2D(OPACITYMAP_SAMPLER, IN.tex1);
	
	OUT.color.xyz = diffuse * IN.color * Brightness;
	OUT.color.w   = diffuse.w * mask.w * DiffuseColour.w * IN.color.w;
	
	return OUT;
}

technique standard <int shader = 1;>
{
    pass p0
    {
        VertexShader = compile vs_1_1 vertex_shader();
        PixelShader  = compile ps_2_0 pixel_shader();
    }
}

#include "ZPrePass_fx.h"
