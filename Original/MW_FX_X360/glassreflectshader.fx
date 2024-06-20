//
// Glass reflection effects
//
#include "global.h"
#include "lightscattering.h"

float4x4	WorldView			: WORLDVIEW;
float4x4	WorldMat			: WORLDMAT;
float4		DiffuseColour		: DIFFUSECOLOUR;
float4		LocalEyePos			: LOCALEYEPOS;
float		MipMapBias			: MIPMAPBIAS;
float4		LightDirVec			: LOCALLIGHTDIRVECTOR;
float4		SpecularColour		: SPECULARCOLOUR;
float		SpecularPower		: SPECULARPOWER;
float		Brightness			: STANDARD_BRIGHTNESS;

sampler DIFFUSEMAP_SAMPLER = sampler_state
{
	AddressU	= WRAP;
	AddressV	= WRAP;
	MIPFILTER	= LINEAR;
	MINFILTER	= LINEAR;
	MAGFILTER	= LINEAR;
};

sampler	MISCMAP1_SAMPLER = sampler_state
{
	AddressU = WRAP;
	AddressV = WRAP;
	MIPFILTER =	LINEAR;
	MINFILTER =	LINEAR;
	MAGFILTER =	LINEAR;
};

struct PS_OUTPUT
{
	float4 color : COLOR0;
};

struct VS_INPUT
{
	float4 position : POSITION;
	float4 normal	: NORMAL;
	float4 color    : COLOR;
	float2 tex		: TEXCOORD0;
	float2 tex1		: TEXCOORD1;
};

struct VtoP
{
	float4 position		: POSITION;
	float4 radiosity	: COLOR0;
	float3 FogAdd		: COLOR1;
	float3 FogMod		: COLOR2;
	float4 tex			: TEXCOORD0;
	float3 normal		: TEXCOORD1;
	float3 view			: TEXCOORD2;
	float2 frenel_NdotL	: TEXCOORD3;
	float3 diffuse		: TEXCOORD4;
	float  specular		: TEXCOORD5;
	float4 shadowTex	: TEXCOORD6;
};

#include "shadowmap_fx_def.h"

VtoP vertex_shader(const VS_INPUT IN)
{
	VtoP OUT;

	OUT.position = world_position(IN.position);

	// calculations performed in local coords
	// (LocalEyePos is viewpoint mapped to local frame)
	OUT.view   = normalize(LocalEyePos - IN.position);
	OUT.normal = IN.normal;
	OUT.radiosity = IN.color * float4(AmbientColour.xyz * AmbientColour.w, 1);

	// Calculate the frenel terms
	half vdotn = dot( OUT.view, IN.normal );
	// frenel in frenel_NdotL.x
	OUT.frenel_NdotL.x = saturate(0.2 + (1.0-vdotn) * 0.4);
	
	float3	lightDir = normalize(LightDirVec);
	float	NdotL = dot(IN.normal, lightDir);

	// NdotL in frenel_NdotL.y
	OUT.frenel_NdotL.y = NdotL;

	OUT.diffuse = saturate(NdotL) * DiffuseColour;

	float3 reflection = 2*NdotL*IN.normal - lightDir;
	OUT.specular = saturate(dot(reflection, OUT.view)); //specular comp
	OUT.specular = pow(OUT.specular, 100);				// spec power to mimic sun hot spot
	
	OUT.tex = float4(IN.tex, IN.tex1);

	OUT.shadowTex = vertex_shadow_tex( IN.position );

	float dist = mul(IN.position, WorldView).z;
	float cos_theta = dot(lightDir, OUT.view);
	CalcFog(dist, cos_theta, OUT.FogAdd.xyz, OUT.FogMod.xyz);
	
	return OUT;
}

float4 pixel_shader(const VtoP IN) : COLOR
{
	float4	base = tex2D(DIFFUSEMAP_SAMPLER, IN.tex.xy);

	float3  viewDir = normalize(IN.view);
	float3	vR = reflect(viewDir, IN.normal);

	// spheremapping
//	float2	vSphereMap;
//	float	fZ = vR.z+1.0f,
//			fM = 2.0f * sqrt( (vR.x*vR.x) + (vR.y*vR.y) + (fZ*fZ) );
//	vSphereMap.x = (vR.x/fM) + 0.5f;
//	vSphereMap.y = (vR.y/fM) + 0.5f;
//	float4	reflection	= tex2D(MISCMAP1_SAMPLER, vSphereMap );

	// cylinder mapping
	float2	vCylinderMap;
	vCylinderMap.x = atan2( vR.y, vR.x );
	// IN.tex.zw contains reflection map xy
	vCylinderMap.y = IN.tex.w;
	float4	reflection	= tex2D(MISCMAP1_SAMPLER, vCylinderMap );

	float shadow = DoShadow( IN.shadowTex, IN.frenel_NdotL.y );

	float4 result;
	result.xyz = IN.radiosity;	// ambient
	result.xyz += shadow * IN.diffuse;	// diffuse lighting
	result.xyz *= base;			// base texture
	result.xyz += IN.specular * base.w * shadow * 2; // specular lighting
	result.xyz += (reflection * base.w) * IN.frenel_NdotL.x; 
	result.xyz *= Brightness;
	result.xyz *= IN.FogMod;
	result.xyz += IN.FogAdd;

	// Write the specular gloss intensity into the alpha channel for
	// the HDR tagging to bloom 
	result.w = 1 - (IN.specular*base.w);

	return result;
}

technique glassreflect <int shader = 1;>
{
    pass p0
    {
        VertexShader		= compile vs_1_1 vertex_shader();
        PixelShader			= compile ps_2_0 pixel_shader();
    }
}

#include "ZPrePass_fx.h"

#include "shadowmap_fx.h"
