//
// WorldNormalmap Effects
//

#include "global.h"
#include "lightscattering.h"

float4x4	WorldView			: WORLDVIEW;
float4x4	WorldMat			: WORLDMAT;
float4		LocalLightVec			: LOCALLIGHTDIRVECTOR;
float4		DiffuseColour		: DIFFUSECOLOUR;
float4		SpecularColour		: SPECULARCOLOUR;
float		SpecularPower		: SPECULARPOWER;
float4		LocalEyePos			: LOCALEYEPOS;
float		SurfaceSmoothness	: SURFACESMOOTHNESS;
float		MipMapBias			: MIPMAPBIAS;
float		OffsetBias			: OFFSET_BIAS;
float		Brightness			: STANDARD_BRIGHTNESS;

int			IsParallexMapped	: IS_PARALLEX_MAPPED;

const float3 kLuminanceVector  =	float3(0.2125f,	0.7154f, 0.0721f);

sampler DIFFUSEMAP_SAMPLER = sampler_state
{
	MIPFILTER	= LINEAR;
	MINFILTER	= LINEAR;
	MAGFILTER	= LINEAR;
};

sampler NORMALMAP_SAMPLER = sampler_state
{
	MIPFILTER	= LINEAR;
	MINFILTER	= LINEAR;
	MAGFILTER	= LINEAR;
};

sampler SPECULARMAP_SAMPLER = sampler_state
{
	MIPFILTER	= LINEAR;
	MINFILTER	= LINEAR;
	MAGFILTER	= LINEAR;
};

struct VS_INPUT
{
	float4 position		: POSITION;
	float4 normal		: NORMAL;
	float4 color		: COLOR;
	float2 tex			: TEXCOORD0;
	float2 texn			: TEXCOORD1;
	float4 tangent		: TANGENT;
};

struct VtoP
{
	float4 position		: POSITION;

	float4 radiosity	: COLOR0;
	float3 FogMod		: COLOR1;
	float3 FogAdd		: TEXCOORD0;
	float4 tex			: TEXCOORD1;
	float4 texn			: TEXCOORD2;
	float3 Light		: TEXCOORD3;
	float3 View			: TEXCOORD4;
	float3 Normal		: TEXCOORD5;
	float4 shadowTex    : TEXCOORD6;
};

struct PS_OUTPUT
{
	float4 color : COLOR0;
};

#include "shadowmap_fx_def.h"
#include "auxiliarylighting_normalmap.h"


VtoP vertex_shader(const VS_INPUT IN)
{
	VtoP OUT;

	OUT.position	= world_position(IN.position);
	OUT.radiosity.xyz = IN.color.xyz * AmbientColour.xyz * AmbientColour.w;
	OUT.radiosity.w   = IN.color.w;
	OUT.tex.xy		= IN.tex;
	OUT.texn.xy		= IN.tex;
	OUT.tex.z		= 1.0;
	OUT.texn.z		= 1.0;
	OUT.tex.w		= MipMapBias;
	OUT.texn.w		= MipMapBias;
	
	// compute transform matrix to transform from
	// world to tangent space
	float3x3 mToTangent;
	mToTangent[0]	= IN.tangent;
	mToTangent[2]	= IN.normal;
	mToTangent[1]	= cross( mToTangent[2], mToTangent[0] ) * IN.tangent.w;

	OUT.Light.xyz	= mul( mToTangent, LocalLightVec );

	//Compute the reflection vector
	float3 Viewer	= normalize(LocalEyePos - IN.position);
	OUT.View		= mul( mToTangent, Viewer );

	OUT.Normal = IN.normal;

	OUT.shadowTex = vertex_shadow_tex( IN.position );

	float dist = mul(IN.position, WorldView).z;
	float cos_theta = dot(normalize(LocalLightVec), Viewer);
	CalcFog(dist, cos_theta, OUT.FogAdd.xyz, OUT.FogMod.xyz);
	
	return OUT;
}

float4 ParallexMapped(float3 ray, const VtoP IN)
{
	const float heightDepth = 0.075f;
	float height = tex2D(NORMALMAP_SAMPLER, IN.tex.xy).w*2;
	//float height = tex2Dbias(NORMALMAP_SAMPLER, IN.tex).w*2;
    float heightScaled = height * heightDepth - heightDepth * 0.5;
	float4 offsetTex = IN.tex;
	offsetTex.xy += ray.xy * heightScaled;  
	return offsetTex;
}

PS_OUTPUT pixel_shader(const VtoP IN)
{
	PS_OUTPUT OUT;

    float3 viewDir	= normalize(IN.View);	// V
	
	// Offset parallex mapping
	float4 tex = IN.tex;
	if( IsParallexMapped )	
	{
		tex = ParallexMapped(viewDir, IN);
	}
	//tex = EnhancedParallexMapping(viewDir, IN);
	
	float4 base		= tex2Dbias(DIFFUSEMAP_SAMPLER, tex); //diffuse map
	float4 norm		= tex2Dbias(NORMALMAP_SAMPLER, tex); // normal map
	float3 specMap	= tex2Dbias(SPECULARMAP_SAMPLER, tex); // normal map


	//convert between unsigned and signed normal map data
	norm = (norm - 0.5)*2;
	

	norm = normalize(norm);
	//norm = float4(0, 0, 1, 1);	// emulates standard diffuse lighting

	float3 lightDir	= normalize(IN.Light);	// L

    float ndotL = dot(norm, lightDir);	
	float diff	= saturate(ndotL);
	
	float3 reflection = 2*ndotL*norm - lightDir;
	
	float specular = saturate(dot(reflection, viewDir)); //specular comp.
	specular = pow(specular, SpecularPower);

	float shadow = DoShadow( IN.shadowTex, 1 );
//	float shadow = DoShadow( IN.shadowTex, ndotL );

	float shadowMult	= saturate(4 * dot(IN.Normal, LocalLightVec));				// compute self-shadowing term 

	float4 radiosity = IN.radiosity;
	
	OUT.color.xyz  = base * diff * DiffuseColour;			// diffuse
	//OUT.color.xyz += specular * SpecularColour * specMap;	// specular
	OUT.color.xyz += specular * SpecularColour * specMap;	// specular
	OUT.color.xyz *= shadowMult * shadow.r;					// shadow knocks out diffuse and spec
	OUT.color.xyz += base * radiosity;						// ambient
	OUT.color.xyz *= Brightness;							// Brightness factor: normaly is 2
	OUT.color.xyz *= IN.FogMod.xyz;							// fog
	OUT.color.xyz += IN.FogAdd.xyz;
  	OUT.color.w    = base.w;
  	
	//OUT.color.xyz = tex2D(NORMALMAP_SAMPLER, IN.tex.xy).w;
	//OUT.color.xyz = 1;
	
	return OUT;
}

technique worldnormalmap <int shader = 1;>
{
    pass p0
    {
        VertexShader		= compile vs_1_1 vertex_shader();
        PixelShader			= compile ps_3_0 pixel_shader();
    }
    pass auxiliary_lighting
    {
        VertexShader		= compile vs_1_1 vertex_shader_normalmap_auxiliary_lighting();
        PixelShader			= compile ps_3_0 pixel_shader_normalmap_auxiliary_lighting();
    }
}

///////////////////////////////////////////////////////////////////////////////
//
// LOW LOD SHADER
//
//
#define DRAW_LOWLOD_SHADOWS  0

struct VS_INPUT_LOWLOD
{
	float4 position : POSITION;
	float4 normal	: NORMAL;
	float4 color    : COLOR;
	float2 tex		: TEXCOORD0;
};

struct VtoP_LOWLOD
{
	float4 position   : POSITION;
	float4 color      : COLOR;
	float4 t0         : TEXCOORD0;
	float3 diffuse    : TEXCOORD1;
#if DRAW_LOWLOD_SHADOWS
	float4 shadowTex  : TEXCOORD2;
#endif
};

VtoP_LOWLOD vertex_shader_lowlod(const VS_INPUT_LOWLOD IN)
{
	VtoP_LOWLOD OUT;
	OUT.position = world_position(IN.position);
	OUT.t0.xy = IN.tex;
	OUT.t0.z  = 1.0;
	OUT.t0.w  = MipMapBias;
	OUT.color = IN.color;

	// Diffuse
	float3 lightDir	= normalize(LocalLightVec);
    float ndotL		= dot(IN.normal, lightDir);
	OUT.diffuse		= saturate(ndotL) * DiffuseColour;

	// Specular
	float3 viewDir   = normalize(LocalEyePos - IN.position);

#if DRAW_LOWLOD_SHADOWS
	OUT.shadowTex = vertex_shadow_tex( IN.position );
#endif

	return OUT;
}

float4 pixel_shader_lowlod(const VtoP_LOWLOD IN) : COLOR0
{
	float4 base		= tex2Dbias(DIFFUSEMAP_SAMPLER, IN.t0) ;

	float4 result;
	result.xyz  =  IN.diffuse * base;
#if DRAW_LOWLOD_SHADOWS
	float shadow = DoShadowMapLowLOD( IN.shadowTex );
	result.xyz	*= shadow.r;
#endif
	result.xyz	+= base * AmbientColour;	// ambient
	result.xyz	*= Brightness;
	
    result.w = base.w;

	return result;
}

technique lowlod
{
    pass p0
    {
        VertexShader = compile vs_1_1 vertex_shader_lowlod();
        PixelShader  = compile ps_2_0 pixel_shader_lowlod();
    }
}


#include "ZPrePass_fx.h"

#include "shadowmap_fx.h"
