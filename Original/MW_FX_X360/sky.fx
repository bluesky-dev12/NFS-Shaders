//
// World Effects
//

#include "global.h"
#include "lightscattering.h"

float4x4 WorldView : WORLDVIEW;
float4x4 World : WORLDMAT;

float		Brightness			: STANDARD_BRIGHTNESS;
float3		LightDirVec			: LOCALLIGHTDIRVECTOR;
float4		DiffuseColour		: DIFFUSECOLOUR;
float4		CloudIntensity		: SKY_DIFFUSESCALE;
float		SkyFogScale			: SKY_FOGSCALE;
float3		LocalEyePos			: LOCALEYEPOS;
float		TimeTicker			: TIME_TICKER;
float		MipMapBias			: MIPMAPBIAS;
float		SkyAlphaTag			: BASEALPHAREF;

sampler DIFFUSEMAP_SAMPLER = sampler_state
{
	AddressU = WRAP;
	AddressV = WRAP;
	MIPFILTER = LINEAR;
	MINFILTER = LINEAR;
	MAGFILTER = LINEAR;
};

sampler MISCMAP1_SAMPLER = sampler_state
{
	AddressU = WRAP;
	AddressV = WRAP;
	MIPFILTER = LINEAR;
	MINFILTER = LINEAR;
	MAGFILTER = LINEAR;
};

sampler MISCMAP2_SAMPLER = sampler_state
{
	AddressU = WRAP;
	AddressV = WRAP;
	MIPFILTER = LINEAR;
	MINFILTER = LINEAR;
	MAGFILTER = LINEAR;
};

sampler MISCMAP3_SAMPLER = sampler_state
{
	AddressU = WRAP;
	AddressV = WRAP;
	MIPFILTER = LINEAR;
	MINFILTER = LINEAR;
	MAGFILTER = LINEAR;
};

struct VS_INPUT
{
	float4 position : POSITION;
	float4 color    : COLOR;
	float4 tex0		: TEXCOORD0;
	float4 tex1		: TEXCOORD1;
	float3 normal	: NORMAL;
};

//-----------------------------------------------------------------------------
// SKY RENDERING
//
struct VtoP
{
	float4 position		: POSITION;
	float4 vertexColour	: COLOR0;
	float4 diffuse		: COLOR1;
	float4 tex0			: TEXCOORD0;
	float4 tex1			: TEXCOORD1;
	float4 tex2			: TEXCOORD2;
	float4 tex3			: TEXCOORD3;
	float3 FogAdd		: TEXCOORD4;
	float3 FogMod		: TEXCOORD5;
};

VtoP vertex_shader(const VS_INPUT IN)
{
	VtoP OUT;
	float4 p = world_position(IN.position);
	OUT.position = p;
	OUT.tex0 = IN.tex0;
	OUT.tex0.w = MipMapBias;
	OUT.tex1 = IN.tex1;
	OUT.tex1.w = MipMapBias;
	OUT.tex2 = IN.tex0;
	OUT.tex2.w = MipMapBias;
	OUT.tex3 = IN.tex0;
	OUT.tex3.w = MipMapBias;
	
	OUT.tex2.x -= TimeTicker;
	OUT.tex0.x -= TimeTicker*0.4;
	OUT.tex3.x -= TimeTicker*0.2+0.3;
	OUT.tex3.y -= 0.05;
	
	OUT.vertexColour = IN.color;// * float4(AmbientColour.xyz * AmbientColour.w, 1);
	
	float3 lightDir = normalize(LightDirVec);

	float3 Viewer = LocalEyePos.xyz - IN.position.xyz;
	Viewer = normalize(Viewer);
	OUT.diffuse = DiffuseColour;

	// Light Scattering	
	//

	// Fake the distance extrapolating further to the horizon.  This results in the
	// light scatters colour becoming lighter closer to the horizon
	const float kSkyDistance = 10000.0f;
	float dist = kSkyDistance + kSkyDistance*(1-IN.position.z/3300);
	
	float cos_theta = dot(lightDir, Viewer);
	CalcFogNoDistScale(dist, cos_theta, OUT.FogAdd.xyz, OUT.FogMod.xyz);
	
	return OUT;
}

float4 pixel_shader(const VtoP IN) : COLOR0
{
	float4 cloudA	  = tex2Dbias(DIFFUSEMAP_SAMPLER, IN.tex0);
	float4 cloudAShift= tex2Dbias(DIFFUSEMAP_SAMPLER, IN.tex3);
	float4 cloudACap  = tex2Dbias(MISCMAP1_SAMPLER,   IN.tex1);
	float4 cloudB     = tex2Dbias(MISCMAP2_SAMPLER,   IN.tex2);
	float4 cloudBCap  = tex2Dbias(MISCMAP3_SAMPLER,   IN.tex1);
	
	float4 result;
	result.xyz = IN.FogAdd.xyz;					// base texture

	// Render the whispy clouds
	cloudA.w *= cloudAShift.w * 2;
	result.xyz = lerp(result.xyz, cloudA.xyz,	cloudA.w*CloudIntensity[0]); 
	result.xyz = lerp(result.xyz, cloudACap.xyz, cloudACap.w*CloudIntensity[0]); 

	// Render the overcast clouds
	result.xyz = lerp(result.xyz, cloudB.xyz,	cloudB.w*CloudIntensity[1]); 
	result.xyz = lerp(result.xyz, cloudBCap.xyz,cloudBCap.w*CloudIntensity[2]); 
	
	// The vertex colour contains white for the sky area and black for the floor
	// of the skydome - this effectively clears the screen.
	result.xyz *= Brightness* 0.5 * IN.vertexColour;
	result.w    = SkyAlphaTag;

	return result;
}

technique sky <int shader = 1;>
{
    pass p0
    {
        VertexShader = compile vs_1_1 vertex_shader();
        PixelShader  = compile ps_2_0 pixel_shader();
    }
}

//-----------------------------------------------------------------------------
// SKY HDR TAG
//
struct VtoP_HDR
{
	float4 position		: POSITION;
};

VtoP vertex_shader_tag_hdr(const VS_INPUT IN)
{
	VtoP_HDR OUT;
	OUT.position = world_position(IN.position);
}
	
float4 pixel_shader_tag_hdr(const VtoP IN) : COLOR0
{
	// Write into the alpha HDR tag channel
	return Brightness;
}

technique tag_hdr
{
    pass p0
    {
        VertexShader = compile vs_1_1 vertex_shader();
        PixelShader  = compile ps_2_0 pixel_shader_tag_hdr();
    }
}


#include "ZPrePass_fx.h"
