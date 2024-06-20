//
// Car Effects
//

#include "global.h"

float4x4 WorldView       : WORLDVIEW ;
float4x4 LocalDirectionMatrix	: LOCALDIRECTIONMATRIX;
float4x4 LocalColourMatrix		: LOCALCOLOURMATRIX;
float4	 DiffuseColour		: DIFFUSECOLOUR;

float4 LocalEyePos : LOCALEYEPOS;

float  MetallicScale	 : METALLICSCALE;
float  SpecularHotSpot	 : SPECULARHOTSPOT;

int	g_bDoCarShadowMap	 : SHADOWMAP_CAR_SHADOW_ENABLED;

float4 DiffuseMin		 : DIFFUSEMIN;
float4 DiffuseRange		 : DIFFUSERANGE;
float4 SpecularMin		 : SPECULARMIN;
float4 SpecularRange     : SPECULARRANGE;
float4 EnvmapMin		 : ENVMAPMIN;
float4 EnvmapRange       : ENVMAPANGE;
float  SpecularPower	 : SPECULARPOWER;
float  EnvmapPower		 : ENVMAPPOWER;

float4 ShadowColour		 : CARSHADOWCOLOUR;

float FocalRange			: FOCALRANGE;

const bool IS_NORMAL_MAPPED = 1;
const bool HAS_METALIC_FLAKE;

const float3	LUMINANCE_VECTOR  =	float3(0.2125f,	0.7154f, 0.0721f);

sampler DIFFUSEMAP_SAMPLER = sampler_state
{
	AddressU = WRAP;
	AddressV = WRAP;
	MIPFILTER = LINEAR;
	MINFILTER = LINEAR;
	MAGFILTER = LINEAR;
};

sampler NORMALMAP_SAMPLER = sampler_state
{
	AddressU	= WRAP;
	AddressV	= WRAP;
	MIPFILTER	= LINEAR;
	MINFILTER	= LINEAR;
	MAGFILTER	= LINEAR;
};

sampler3D VOLUMEMAP_SAMPLER = sampler_state
{
    AddressU  = WRAP;        
    AddressV  = WRAP;
    AddressW  = WRAP;
	MIPFILTER = POINT;
	MINFILTER = POINT;
	MAGFILTER = POINT;
};

samplerCUBE ENVIROMAP_SAMPLER = sampler_state
{
	AddressU = MIRROR;
	AddressV = MIRROR;
	MIPFILTER = LINEAR;
	MINFILTER = LINEAR;
	MAGFILTER = LINEAR;
};

struct VS_INPUT
{
	float4 position : POSITION;
	float4 normal   : NORMAL;
	float4 color    : COLOR;
	float4 tex		: TEXCOORD;
	float4 tangent	: TANGENT;
};

struct PS_OUTPUT
{
	float4 color : COLOR0;
};

#include "shadowmap_fx_def.h"

/////////////////////////////////////////////////////////////////////////////////////////
//
// Car Shader
//
//
struct VtoP
{
	float4 position       : POSITION;
	half4  diffuse		  : COLOR0;
	half4  specular		  : COLOR1;
	half4  t0             : TEXCOORD0;	// Environment Map
	half4  t1             : TEXCOORD1;	// Base Texture Map
	half4  t2             : TEXCOORD2;	// Shadow Map
	half4  view			  : TEXCOORD3;
	half4  normal		  : TEXCOORD4;
	half4  lights[2]	  : TEXCOORD5;
};

/////////////////////////////////////////////////////////////////////////////////////////
//
// Car Shader Normal Map Shaders
//
//

VtoP vertex_shader_normalmap(const VS_INPUT IN)
{
	VtoP OUT;
	OUT.position = world_position(IN.position);
	OUT.normal	= IN.normal;
	OUT.t1	= IN.tex;
	OUT.t2  = vertex_shadow_tex( IN.position );
	
	// Calculate parameters use for the grazingto facing colour shift
	// based on the viewing angle
	float3 ViewDir = LocalEyePos - IN.position;

	// Metallic paint distance falloff coeff
	OUT.view.w = saturate(length(ViewDir)*-0.25 + 1.2);	// line equation
	
	half3 view_vector = normalize(ViewDir); 
	half vdotn		= dot( view_vector, IN.normal );
		 vdotn		= max( 0.01f, vdotn );
	half specvdotn	= pow( vdotn, SpecularPower );
	half envvdotn	= pow( vdotn, EnvmapPower );
	OUT.diffuse  = DiffuseMin  + (vdotn	 * DiffuseRange);
	OUT.specular = SpecularMin + (specvdotn * SpecularRange);
	OUT.specular.w	= envvdotn;

	// Transform view and lights from local to tangent space
	half3x3 mToTangent;
	mToTangent[0]		= IN.tangent;
	mToTangent[2]		= IN.normal;
	mToTangent[1]		= cross( mToTangent[2], mToTangent[0] ) * IN.tangent.w;
	OUT.lights[0].xyz	= mul( mToTangent, LocalDirectionMatrix._m00_m10_m20);
	OUT.lights[1].xyz	= mul( mToTangent, LocalDirectionMatrix._m01_m11_m21);
	OUT.view.xyz		= mul( mToTangent, ViewDir );
	// If normal mapped then the reflection to view calculations are done in pixel space
	OUT.t0				= 0;
	
	// We have run out of textcord slots so move the world position into the w components
	// of the normal and light vectors
	OUT.normal.w = IN.position.x;
	OUT.lights[0].w = IN.position.y;
	OUT.lights[1].w = IN.position.z;

	//float4 shadowTex = vertex_shadow_tex( IN.position );
	//OUT.t1.z = shadowTex.x;
	//OUT.t1.w = shadowTex.y;
	
	OUT.t0.w = IN.color.x;

	return OUT; 
}

float4 pixel_shader_normalmap(const VtoP IN) : COLOR0
{
	//
	// Implement phong specular model with environmental mapping
	// 
	half4 diffuse_sample	= tex2D(DIFFUSEMAP_SAMPLER, IN.t1.xy);
    
    half3 viewDir			= normalize(IN.view.xyz);			// V

	float3 position			= float3(IN.normal.w, IN.lights[0].w, IN.lights[1].w);
	half4 noise_sample		= tex3Dbias(VOLUMEMAP_SAMPLER, float4(position*20, -3));
	half3 flakeNoise		= (noise_sample - 0.5) * 2;
	half	shadow = 1.0;
	if ( g_bDoCarShadowMap )
	{
		shadow = DoShadow( IN.t2, 1 );
	}
	//half shadow				= DoShadowMapAlpha( IN.t2 );
	
	// Extract the normal from the map
	half4 norm_sample	= tex2Dbias(NORMALMAP_SAMPLER, IN.t1); // normal map
	norm_sample = (norm_sample - 0.5)*2;		//convert between unsigned and signed normal map data
	half3 normal = normalize(norm_sample);			// N
	
	// Calculate the reflection componenet using the normal maps normal
	half vdotn     = dot( viewDir, normal );
	vdotn			= max( 0.01f, vdotn );
	half4 envmapTex = float4(2.0f*vdotn*normal - viewDir, 0.0f); // R = 2 * (N.V) * N - V
	
	half4 envmap_sample = texCUBE( ENVIROMAP_SAMPLER, envmapTex);
	half3 envmap_color		= envmap_sample * 2 * (EnvmapMin + IN.specular.w * EnvmapRange);
	
	// Accumulate the diffuse for both lights
	half  ndotL1 = dot(normal, IN.lights[0].xyz);				// N.L1
	half  ndotL2 = dot(normal, IN.lights[1].xyz);				// N.L2
	half3 diffuse = saturate(ndotL1+0.3) * LocalColourMatrix[0].xyz;
	diffuse		  += saturate(ndotL2+0.3) * LocalColourMatrix[1].xyz;
	
	// Apply a metallic flake to the specular
	half3 normalFlake = normalize(normal + flakeNoise*0.04*MetallicScale*IN.view.w);
	half  ndotL1Flake = dot(normalFlake, IN.lights[0].xyz);				// N.L1
	// Calculate the specular for just the first light (i.e. the sun)
	half3 reflection  = 2*normalFlake*ndotL1Flake - IN.lights[0].xyz;		// R = 2 * (N.L1) * N - L1

	// Base specular falloff	
	half3 reflectDotView = saturate(dot(reflection, viewDir));
	half3 specular = pow(reflectDotView, SpecularPower) * 0.7; // S = (R.V) ^ n
	// Hot spot specular - helps define the sun centre
	specular += pow(reflectDotView, SpecularPower*100) * shadow.r * SpecularHotSpot;			// S = (R.V) ^ n
	specular *= LocalColourMatrix[0].xyz;
	
	// Calculate the self shadow
	//float3 selfShadow = saturate(4 * ndotL1);	// self-shadowing term 
	
	half ambientOcclusion = IN.t0.w;
	
	half4 result;
	result.xyz = diffuse * IN.diffuse;// * ambientOcclusion;						// diffuse
	result.xyz *= diffuse_sample;
	result.xyz += IN.diffuse.w * specular * IN.specular * shadow.r * ambientOcclusion;			// specular
	result.xyz *= lerp(ShadowColour.xyz, 1, shadow.r);											// shadow;
	result.xyz += IN.diffuse.w * envmap_color * ambientOcclusion;							// environ gloss mapping (2x)
	result.w   = IN.diffuse.w * diffuse_sample.w;												// alpha
		
	return result;
}

/////////////////////////////////////////////////////////////////////////////////////////
//
// Low Lod Shader
//
//
VtoP vertex_shader_lowlod(const VS_INPUT IN)
{
	VtoP OUT;
	OUT.position = world_position(IN.position);
	OUT.normal	= IN.normal;
	OUT.t1	= IN.tex;
	OUT.t2  = vertex_shadow_tex( IN.position );
	
	// Calculate parameters use for the grazingto facing colour shift
	// based on the viewing angle

	half3 view_vector = normalize(LocalEyePos - IN.position); 
	half vdotn		= dot( view_vector, IN.normal );
		 vdotn		= max( 0.01f, vdotn );
	half specvdotn	= pow( vdotn, SpecularPower );
	half envvdotn	= pow( vdotn, EnvmapPower );
	OUT.diffuse		= DiffuseMin  + (vdotn	 * DiffuseRange);
	OUT.specular = SpecularMin + (specvdotn * SpecularRange);
	OUT.specular.w	= 2 * IN.color.x * (EnvmapMin.x + envvdotn * EnvmapRange.x);

	// Leave view and lights in local space
	OUT.view.xyz		= view_vector;
	OUT.view.w			= 1;
	OUT.lights[0].xyz	= LocalDirectionMatrix._m00_m10_m20;
	OUT.lights[1].xyz	= LocalDirectionMatrix._m01_m11_m21;
	// Environment mapping texture coords
	half4 reflection = half4(2.0f*vdotn*IN.normal - view_vector, 0.0f); // R = 2 * (N.V) * N - V
	OUT.t0 = half4(mul( reflection, WorldView ).xyz, 1.0f);
	
	// We have run out of textcord slots so move the world position into the w components
	// of the normal and light vectors
	OUT.normal.w = IN.position.x;
	OUT.lights[0].w = IN.position.y;
	OUT.lights[1].w = IN.position.z;

	// Accumulate the diffuse for both lights
	half  ndotL1	= dot(IN.normal, OUT.lights[0].xyz);				// N.L1
	half  ndotL2	= dot(IN.normal, OUT.lights[1].xyz);				// N.L2
	half3 diffuse	= saturate(ndotL1+0.3) * LocalColourMatrix[0].xyz;
	diffuse			+= saturate(ndotL2+0.3) * LocalColourMatrix[1].xyz;
	OUT.diffuse.xyz	*= IN.color.x * diffuse;
	
	// Calculate the specular for just the first light (i.e. the sun)
	half3 reflectionSpec  = 2*IN.normal*ndotL1 - OUT.lights[0].xyz;		// R = 2 * (N.L1) * N - L1
	half3 reflectDotView = saturate(dot(reflectionSpec, view_vector));
	half3 specular = pow(reflectDotView, SpecularPower) * 0.7; // S = (R.V) ^ n
	specular += pow(reflectDotView, SpecularPower*100) * SpecularHotSpot;			// S = (R.V) ^ n
	// Hot spot specular - helps define the sun centre
	specular *= LocalColourMatrix[0].xyz;
	OUT.specular.xyz *= specular * IN.color.x * OUT.diffuse.w;
	
	return OUT; 
}

float4 pixel_shader_lowlod(const VtoP IN) : COLOR0
{
	//
	// Implement phong specular model with environmental mapping
	// 
	half4 diffuse_sample	= tex2D(DIFFUSEMAP_SAMPLER, IN.t1.xy);
	half4 envmap_sample		= texCUBE( ENVIROMAP_SAMPLER, IN.t0);
	half3 envmap_color		= envmap_sample * IN.specular.w;
	
	//
	half4 result;
	result.xyz = IN.diffuse;			// diffuse
	result.xyz *= diffuse_sample;
	result.xyz += IN.specular;			// specular
	result.xyz += IN.diffuse.w * envmap_color;							// environ gloss mapping (2x)
	result.w   = IN.diffuse.w * diffuse_sample.w;												// alpha
	
	//result.xyz = float3(1, 1, 0);
	return result;
}

technique car_normalmap <int shader = 1;>
{
    pass p0
    {
		VertexShader = compile vs_3_0 vertex_shader_normalmap();
		PixelShader  = compile ps_3_0 pixel_shader_normalmap();
		//VertexShader = compile vs_3_0 vertex_shader_lowlod();
		//PixelShader  = compile ps_3_0 pixel_shader_lowlod();
    }
}

technique lowlod <int shader = 1;>
{
    pass p0
    {
		VertexShader = compile vs_3_0 vertex_shader_lowlod();
		PixelShader  = compile ps_3_0 pixel_shader_lowlod();
		//VertexShader = compile vs_3_0 vertex_shader_normalmap();
		//PixelShader  = compile ps_3_0 pixel_shader_normalmap();
    }
}


#include "ZPrePass_fx.h"

#include "shadowmap_fx.h"
