//
// World Effects
//

#include "global.h"
#include "auxiliarylighting.h"
#include "lightscattering.h"

float4x4 WorldView : WORLDVIEW;
float4x4 World : WORLDMAT;

float4 TextureOffset   : TEXTUREANIMOFFSET;
float4x4 TextureOffsetMatrix : TEXTUREOFFSETMATRIX;

float		Brightness			: STANDARD_BRIGHTNESS;
float3		LightDirVec			: LOCALLIGHTDIRVECTOR;
float4		DiffuseColour		: DIFFUSECOLOUR;
float4		SkyDiffuseScale		: SKY_DIFFUSESCALE;
float3		LocalEyePos			: LOCALEYEPOS;

float		MipMapBias			: MIPMAPBIAS;

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

struct VS_INPUT
{
	float4 position		: POSITION;
	float4 color		: COLOR;
	float4 tex			: TEXCOORD;
	float3 normal		: NORMAL;
};

struct VtoP
{
	float4 position		: POSITION;
	float4 radiosity	: COLOR0;
	float4 tex			: TEXCOORD0_centroid;
	float4 shadowTex	: TEXCOORD1_centroid;
	float4 diffuse		: TEXCOORD2_centroid;
	float3 FogAdd		: TEXCOORD3_centroid;
	float3 FogMod		: TEXCOORD4_centroid;
	float4 AuxLightDiff	: TEXCOORD5_centroid;
	float4 AuxLightSpec	: TEXCOORD6_centroid;
	float  NdotL		: TEXCOORD7_centroid;
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

VtoP vertex_shader(const VS_INPUT IN)
{
	VtoP OUT;
	OUT.position = world_position(IN.position);

	OUT.tex = IN.tex + TextureOffset;
	OUT.tex.w = MipMapBias;

	OUT.radiosity.xyz = IN.color.xyz * AmbientColour.xyz * AmbientColour.w;
	OUT.radiosity.w   = IN.color.w;

	float3 lightDir = normalize(LightDirVec);
	float3 viewDir = normalize(LocalEyePos.xyz - IN.position.xyz);
	float ndotL = saturate(dot(IN.normal, lightDir));

	OUT.NdotL = ndotL;

	OUT.diffuse = ndotL * DiffuseColour;

	OUT.shadowTex = vertex_shadow_tex( IN.position );

	float dist = mul(IN.position, WorldView).z;
	float cos_theta = dot(lightDir, viewDir);
	CalcFog(dist, cos_theta, OUT.FogAdd.xyz, OUT.FogMod.xyz);

	OUT.AuxLightDiff = 0;
	OUT.AuxLightSpec = 0;
	if( ActiveAuxiliaryLight0 )	AuxiliaryLight(0, normalize(Lights[0][0].xyz - IN.position.xyz), IN.position, IN.normal, viewDir, OUT.AuxLightDiff.xyz, OUT.AuxLightSpec.xyz);
	if( ActiveAuxiliaryLight1 )	AuxiliaryLight(1, normalize(Lights[1][0].xyz - IN.position.xyz), IN.position, IN.normal, viewDir, OUT.AuxLightDiff.xyz, OUT.AuxLightSpec.xyz);
	if( ActiveAuxiliaryLight2 )	AuxiliaryLight(2, normalize(Lights[2][0].xyz - IN.position.xyz), IN.position, IN.normal, viewDir, OUT.AuxLightDiff.xyz, OUT.AuxLightSpec.xyz);
	if( ActiveAuxiliaryLight3 )	AuxiliaryLight(3, normalize(Lights[3][0].xyz - IN.position.xyz), IN.position, IN.normal, viewDir, OUT.AuxLightDiff.xyz, OUT.AuxLightSpec.xyz);
	

	return OUT;
}

float4 pixel_shader(const VtoP IN) : COLOR0
{
	float4 base = tex2Dbias(DIFFUSEMAP_SAMPLER, IN.tex);
	float shadow = DoShadow( IN.shadowTex, IN.NdotL );

	float4 radiosity = IN.radiosity;

	float4 result;
	result.xyz = radiosity;				// ambient
	result.xyz += shadow * IN.diffuse;	// diffuse lighting
	result.xyz += IN.AuxLightDiff;
	result.xyz *= base;					// base texture
	//result.xyz += IN.AuxLightSpec * base;	// no spec map so use a power of the base
 	result.xyz *= Brightness;
	result.xyz *= IN.FogMod.xyz;
	result.xyz += IN.FogAdd.xyz;

	result.w = base.w * radiosity.w;
	//result.xyz = 1;
	
	return result;
}

technique world <int shader = 1;>
{
    pass p0
    {
        VertexShader = compile vs_1_1 vertex_shader();
        PixelShader  = compile ps_2_0 pixel_shader();
    }
}

#include "ZPrePass_fx.h"

#include "shadowmap_fx.h"
