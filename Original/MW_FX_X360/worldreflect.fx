//
// World Effects
//

#include "global.h"
#include "lightscattering.h"

float4x4 WorldView		: WORLDVIEW;
texture  ReflectedTex   : REFLECTEDTEX;
float4x4 ReflectedProj  : REFLECTEDPROJ;
float	Brightness		: STANDARD_BRIGHTNESS;
float   SurfaceReflection : SURFACE_REFLECTION;
float   RainIntensity	  : RAIN_INTENSITY;

float4		LocalLightVec		: LOCALLIGHTDIRVECTOR;
float4		DiffuseColour		: DIFFUSECOLOUR;
float4		SpecularColour		: SPECULARCOLOUR;
float		SpecularPower		: SPECULARPOWER;
float4		LocalEyePos			: LOCALEYEPOS;
float		SurfaceSmoothness	: SURFACESMOOTHNESS;
float		MipMapBias			: MIPMAPBIAS;

sampler DIFFUSEMAP_SAMPLER = sampler_state
{
	MIPFILTER = LINEAR;
	MINFILTER = LINEAR;
	MAGFILTER = LINEAR;
};

sampler NORMALMAP_SAMPLER = sampler_state
{
	MIPFILTER = LINEAR;
	MINFILTER = LINEAR;
	MAGFILTER = LINEAR;
};

sampler SPECULARMAP_SAMPLER = sampler_state
{
	MIPFILTER = LINEAR;
	MINFILTER = LINEAR;
	MAGFILTER = LINEAR;
};

sampler MISCMAP1_SAMPLER = sampler_state	// reflect texture sampler
{
	AddressU = CLAMP;
	AddressV = CLAMP;
	MIPFILTER = LINEAR;
	MINFILTER = LINEAR;
	MAGFILTER = LINEAR;
};

//sampler MISCMAP2_SAMPLER;

sampler MISCMAP2_SAMPLER = sampler_state	// rain splash
{
	AddressU = WRAP;
	AddressV = WRAP;
	MIPFILTER = LINEAR;
	MINFILTER = LINEAR;
	MAGFILTER = LINEAR;
};

//
// 
//
//
struct VS_INPUT
{
	float4 position		: POSITION;
	float4 normal		: NORMAL;
	float4 colour		: COLOR;
	float2 tex			: TEXCOORD0;
	float4 tangent		: TANGENT;
};

struct VtoP
{
	float4 position		: POSITION;
	float4 radiosity	: COLOR0;
	float4 FogMod		: COLOR1;
	float4 t0			: TEXCOORD0_centroid;
	float4 t1			: TEXCOORD1_centroid;
	float3 Light		: TEXCOORD3_centroid;
	float3 View			: TEXCOORD4_centroid;
	float3 Normal		: TEXCOORD5_centroid;
	float4 shadowTex	: TEXCOORD6_centroid;
	float3 FogAdd		: TEXCOORD7_centroid;
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
	float4 p = world_position(IN.position);
	OUT.position	= p;
	OUT.t0.xy		= IN.tex;
	OUT.radiosity	= IN.colour * float4(AmbientColour.xyz * AmbientColour.w, IN.colour.w);

	// Use t0.zw for the world space UV's to index into the rain sampler
	OUT.t0.zw		= IN.position.xy;
	const float kRainSplashWorldScale = 0.2;
	OUT.t0.zw	*= kRainSplashWorldScale;
	
	p.y=-p.y;
	p.xy += p.w; // add "one" - texture bias
	p.xy *= 0.5;
	OUT.t1 = p;

	// compute transform matrix to transform from
	// world to tangent space
	float3x3 mToTangent;
	mToTangent[0]	= IN.tangent;
	mToTangent[2]	= IN.normal;
	mToTangent[1]	= cross( mToTangent[2], mToTangent[0] ) * IN.tangent.w;

	//rotate light into tangent space
	OUT.Light.xyz	= mul( mToTangent, LocalLightVec );

	//Compute the reflection vector
	float3 Viewer		= normalize(LocalEyePos - IN.position);
	OUT.View			= mul( mToTangent, Viewer );

	OUT.Normal = IN.normal;

	OUT.shadowTex = vertex_shadow_tex( IN.position );
//	OUT.vPosView  = vertex_shadow_pos_view( IN.position );

	// fog
	float dist = mul(IN.position, WorldView).z;
	float cos_theta = dot(normalize(LocalLightVec), Viewer);
	CalcFog(dist, cos_theta, OUT.FogAdd.xyz, OUT.FogMod.xyz);
	// shadowmap depth
	OUT.FogMod.w = OUT.position.z;
	
	return OUT;
}

float4 get_road_colour(const VtoP IN, float4 reflectionSample) : COLOR0
{
	float4 tex = float4(IN.t0.xy, 0, MipMapBias);
	float4 base = tex2Dbias(DIFFUSEMAP_SAMPLER, tex);
	float3 norm		= tex2Dbias(NORMALMAP_SAMPLER, tex); // normal map
	float3 specMap	= tex2Dbias(SPECULARMAP_SAMPLER, tex); // specular map
	float3 viewDir	= normalize(IN.View);	// V
   
	//convert between unsigned and signed normal map data
	norm = (norm - 0.5)*2;
	
	norm = normalize(norm);

    float3 lightDir	= normalize(IN.Light);	// L

    float ndotL = dot(norm, lightDir);
	float3 diffuse	= saturate(ndotL) * DiffuseColour;

	float3 reflection = 2*ndotL*norm - lightDir;

	float specularCoeff = saturate(dot(reflection, viewDir)); //specular comp.
	float3 specular = pow(specularCoeff, SpecularPower) * SpecularColour;
	
	float shadow = DoShadow( IN.shadowTex, -ndotL );

	float4 radiosity = IN.radiosity;
	
	float4 result;
	result.xyz   = diffuse  * base;								// diffuse
	result.xyz  += specular * specMap;							// specular
	result.xyz	*= shadow;										// shadow knocks out diffuse and spec
	result.xyz	+= base * radiosity;							// ambient 
	result.xyz  += reflectionSample * specMap.x;				// The reflection is broken up by the intensity of the spec map
	result.xyz  *= Brightness;
	result.xyz  *= IN.FogMod;									// fog
	result.xyz  += IN.FogAdd;

	// No alpha because the base alpha was used to modulate the reflection
    result.w = 1;	
    
	return result;
}

float4 pixel_shader_dryroad(const VtoP IN) : COLOR0
{
	return get_road_colour(IN, 0);
}

float4 pixel_shader_wetroad(VtoP IN) : COLOR0
{
	// Index in the rain splash texture at different scales to simulate
	// more variety across the reflective surface
	float4 rainSplash1 = tex2D(MISCMAP2_SAMPLER, IN.t0.zw);
	float4 rainSplash2 = tex2D(MISCMAP2_SAMPLER, IN.t0.zw * 1.5);
	float4 rainSplash = (rainSplash1 + rainSplash2) * 0.5;
	
	// Perturbe the reflection uv based on the rainSplash value - this is just
	// a form of parallex mapping.  Height stored in x channel
	rainSplash.x *= RainIntensity;
	
 	const float heightDepth = 1.0f;
    float heightScaled = rainSplash.x * heightDepth;
	float4 offsetTex = IN.t1 + heightScaled;
	
	// Index reflection sample with the offset
	float4 reflectionSample = tex2Dproj(MISCMAP1_SAMPLER, offsetTex);
	
	// Add a bright ripple rim from the y channel
	reflectionSample += 5 * rainSplash.y * RainIntensity;
	reflectionSample -= 5 * rainSplash.z * RainIntensity;
	// Darken the reflection when it's raining to simulate less light from sky
	reflectionSample *= (1-RainIntensity*0.6);
	// Modulate with how much the road is reflecting (RoadDampness) and the road vertex alpha
	reflectionSample *= SurfaceReflection * IN.radiosity.w;
	
	return get_road_colour(IN, reflectionSample);
}

technique dryroad
{
    pass p0
    {
        VertexShader		= compile vs_1_1 vertex_shader();
        PixelShader			= compile ps_3_0 pixel_shader_dryroad();
    }
    pass auxiliary_lighting
    {
        VertexShader		= compile vs_1_1 vertex_shader_normalmap_auxiliary_lighting();
        PixelShader			= compile ps_3_0 pixel_shader_normalmap_auxiliary_lighting();
    }
}

technique wetroad
{
    pass p0
    {
        VertexShader		= compile vs_1_1 vertex_shader();
        PixelShader			= compile ps_2_0 pixel_shader_wetroad();
    }
    pass p1
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
#define DRAW_LOWLOD_SHADOWS 0

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
	float3 specular   : TEXCOORD2;
#if DRAW_LOWLOD_SHADOWS
	float4 shadowTex  : TEXCOORD3;
#endif
};

VtoP_LOWLOD vertex_shader_lowlod(const VS_INPUT_LOWLOD IN)
{
	VtoP_LOWLOD OUT;
	OUT.position	= world_position(IN.position);
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
	float3 reflection = 2*ndotL*IN.normal - lightDir;
	float specular = saturate(dot(reflection, viewDir)); //specular comp.
	OUT.specular = pow(specular, SpecularPower) * SpecularColour;

#if DRAW_LOWLOD_SHADOWS
	OUT.shadowTex = vertex_shadow_tex( IN.position );
#endif

	return OUT;
}

float4 pixel_shader_lowlod(const VtoP_LOWLOD IN) : COLOR0
{
	float4 base		= tex2Dbias(DIFFUSEMAP_SAMPLER, IN.t0) ;
	float3 specMap	= tex2Dbias(SPECULARMAP_SAMPLER, IN.t0);

	float4 result;
	result.xyz  =  IN.diffuse * base;
	result.xyz  += IN.specular * specMap;
#if DRAW_LOWLOD_SHADOWS
	float4 shadow = DoShadowMapLowLOD( IN.shadowTex );
	result.xyz	*= shadow.r;
#else
	result.xyz	*= IN.color.w;
#endif
	result.xyz	+= base * AmbientColour;	// ambient
	result.xyz	*= Brightness;

	result.w = 1;

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
