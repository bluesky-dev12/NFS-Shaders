//
// Standard Effect
//
#include "global.h"

float4x4 WorldView				: WORLDVIEW;
float4x4 World					: WORLDMAT;
float4x4 Proj                   : PROJMAT;
shared float4 TextureOffset		: TEXTUREOFFSET;
shared float4x4 TextureOffsetMatrix : TEXTUREOFFSETMATRIX;

float Brightness			: STANDARD_BRIGHTNESS;
float FocalRange			: FOCALRANGE;
float4 LocalCenter			: LOCALCENTER;
float4 BaseAlphaRef			: BASEALPHAREF;

float MaxParticleSize = .65;

sampler DIFFUSEMAP_SAMPLER = sampler_state
{
	AddressU = WRAP;
	AddressV = WRAP;
	MIPFILTER = LINEAR;
	MINFILTER = LINEAR;
	MAGFILTER = LINEAR;
};

sampler MISCMAP1_SAMPLER = sampler_state	// backbuffer for screen distortion
{
	AddressU = CLAMP;
	AddressV = CLAMP;
	MIPFILTER = LINEAR;
	MINFILTER = LINEAR;
	MAGFILTER = LINEAR;
};

sampler OPACITYMAP_SAMPLER = sampler_state	// rain alpha texture
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
	float4 position  : POSITION;
	float4 color     : COLOR0;
	float4 tex       : TEXCOORD0;
	float4 tex1      : TEXCOORD1;
	float4 shadowTex : TEXCOORD2;
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

#include "shadowmap_fx_def.h"

//-----------------------------------------------------------------------------
// PARTICLES
//

float3x3 BuildRotate(float angle, float3 rotAxis)
{
	float3x3 m;
    // float fSin = sin(angle);
    // float fCos = cos(angle);
    float2 sc;
    sincos(angle,sc.x,sc.y);
	float3 axis = normalize(rotAxis);

    float3 cosAxis = (1.0f - sc.y) * axis;
    float3 sinAxis = sc.x * axis;
    m[0] = cosAxis.x * axis; 
    m[1] = cosAxis.y * axis; 
    m[2] = cosAxis.z * axis; 
    m[0][0] += sc.y;
    m[0][1] += sinAxis.z;
    m[0][2] -= sinAxis.y;
    m[1][0] -= sinAxis.z;
    m[1][1] += sc.y;
    m[1][2] += sinAxis.x;
    m[2][0] += sinAxis.y;
    m[2][1] -= sinAxis.x;
    m[2][2] += sc.y;
    
    return m;
}

VtoP vertex_shader_particles(const VS_INPUT IN)
{
	VtoP OUT;
	// Offset the vertex by the particle size		
	float3 right	= WorldView._m00_m10_m20;
	float3 up		= WorldView._m01_m11_m21;
	float3 facing	= WorldView._m02_m12_m22;

	// Rotate the up and right around the facing
	float angle = IN.tex1.z;
	if( angle > 0 )
	{
		float3x3 rotation = BuildRotate(angle, facing);
		right = mul(right, rotation);
		up	  = mul(up, rotation);
	}

	// Cap the screen size of any particle
	float4 pv = IN.position;
	pv.xyz = pv.xyz + right * IN.tex1.x;
	pv.xyz = pv.xyz + up    * IN.tex1.y;

	OUT.shadowTex = vertex_shadow_tex(pv);
	pv = world_position(pv);
	float3 pvn = pv.xyz/pv.w;
	float4 pc = world_position(IN.position);
	float3 pcn = pc.xyz/pc.w;
	float size = distance(pvn.xy,pcn.xy);
	float new_size = min(size, MaxParticleSize);
	float scale = new_size/size;
	pv = lerp(pc,pv,scale);
	
	OUT.position = pv;

	OUT.tex = IN.tex + TextureOffset;
	OUT.tex1 = IN.tex1;
	OUT.color = IN.color;
	
	//pos.w = 1;

	return OUT;
}

PS_OUTPUT pixel_shader_particles(const VtoP IN)
{
	PS_OUTPUT OUT;

	float  shadow = DoShadow( IN.shadowTex, 1 ) * 0.5 + 0.5;
	
	float4 diffuse = tex2D(DIFFUSEMAP_SAMPLER, IN.tex) * Brightness * IN.color;
	//float4 mask	   = tex2D(samp1, IN.tex1);
	
	OUT.color.xyz = diffuse * shadow;
	//OUT.color.xyz = float3(1,1,1);
	OUT.color.w   = diffuse.w * shadow;
	//OUT.color.w *= 2;
	
	//OUT.color.xyzw = shadow;
	//OUT.color.xyz = IN.radius;
	//OUT.color.w   = 1;

	return OUT;
}

technique particles <int shader = 1;>
{
    pass p0
    {
        VertexShader = compile vs_1_1 vertex_shader_particles();
        PixelShader  = compile ps_2_0 pixel_shader_particles();
    }
}

//
//
//
PS_OUTPUT pixel_shader_particles_noshadow(const VtoP IN)
{
	PS_OUTPUT OUT;

	float4 diffuse = tex2D(DIFFUSEMAP_SAMPLER, IN.tex);
	
	OUT.color = diffuse;
	OUT.color *= IN.color;
	OUT.color *= Brightness;
	
	return OUT;
}

technique noshadow <int shader = 1;>
{
    pass p0
    {
        VertexShader = compile vs_1_1 vertex_shader_particles();
        PixelShader  = compile ps_2_0 pixel_shader_particles_noshadow();
    }
}


//
// Onscreen rain particle effect
//
VtoP vertex_shader_passthru(const VS_INPUT IN)
{
	VtoP OUT;
	OUT.position = screen_position(IN.position);
	OUT.position.w = 1.0f;
	OUT.tex = IN.tex;
	OUT.shadowTex = IN.tex1;
	OUT.color = IN.color;

	float4 p = IN.position;	
	p.y=-p.y;
	p.xy += p.w; // add "one" - texture bias
	p.xy *= 0.5;
	OUT.tex1 = p;

	return OUT;
}

float4 pixel_shader_onscreen_distort(const VtoP IN) : COLOR0
{
	float4 distortion = tex2D(DIFFUSEMAP_SAMPLER, IN.tex);
	float2 offset = distortion.gb * LocalCenter.ba + LocalCenter.rg;
	float4 background = tex2D(MISCMAP1_SAMPLER, offset);
	
	// The opacity map has four different raindrop texture tiled horizontally.  The
	// offset into this texure is stored in BaseAlphaRef.y
	//
	offset = IN.tex;
	offset.x = BaseAlphaRef.y + IN.tex.x*0.25;
	float4 opacity = tex2D(OPACITYMAP_SAMPLER, offset);
	
	float4 result;
	result = background * opacity.y;
	result.w = opacity.r * BaseAlphaRef.x;

	//result = opacity;
	
	return result;
}

technique onscreen_distort <int shader = 1;>
{
    pass p0
    {
        VertexShader = compile vs_1_1 vertex_shader_passthru();
        PixelShader  = compile ps_2_0 pixel_shader_onscreen_distort();
    }
}

#include "ZPrePass_fx.h"
