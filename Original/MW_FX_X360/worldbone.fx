//
// World Effects
//
#include "global.h"

float4x4 WorldView			: WORLDVIEW;
float4 LocalEyePos			: LOCALEYEPOS;
float4x4 BlendMatrices[16]  : BLENDMATRICES;

float4x4 LocalDirectionMatrix	: LOCALDIRECTIONMATRIX;
float4x4 LocalColourMatrix		: LOCALCOLOURMATRIX;
float4	 DiffuseColour		: DIFFUSECOLOUR;

float  MetallicScale	 : METALLICSCALE;
float  SpecularHotSpot	 : SPECULARHOTSPOT;

float	Brightness		: STANDARD_BRIGHTNESS;

float4 DiffuseMin		 : DIFFUSEMIN;
float4 DiffuseRange		 : DIFFUSERANGE;
float4 SpecularMin		 : SPECULARMIN;
float4 SpecularRange     : SPECULARRANGE;
float4 EnvmapMin		 : ENVMAPMIN;
float4 EnvmapRange       : ENVMAPANGE;
float  SpecularPower	 : SPECULARPOWER;
float  EnvmapPower		 : ENVMAPPOWER;

float4 ShadowColour		 : CARSHADOWCOLOUR;

float	g_fSpecMapScale = 3.0f;

sampler DIFFUSEMAP_SAMPLER = sampler_state
{
	AddressU = WRAP;
	AddressV = WRAP;
	MIPFILTER = LINEAR;
	MINFILTER = LINEAR;
	MAGFILTER = LINEAR;
};

samplerCUBE ENVIROMAP_SAMPLER = sampler_state
{
	AddressU = MIRROR;
	AddressV = MIRROR;
	MIPFILTER = LINEAR;
	MINFILTER = LINEAR;
	MAGFILTER = LINEAR;
};

sampler NORMALMAP_SAMPLER = sampler_state
{
	MIPFILTER = LINEAR;
	MINFILTER = LINEAR;
	MAGFILTER = LINEAR;
	AddressU = WRAP;
	AddressV = WRAP;
};

sampler SPECULARMAP_SAMPLER = sampler_state
{
	AddressU	= WRAP;
	AddressV	= WRAP;
	MIPFILTER	= LINEAR;
	MINFILTER	= LINEAR;
	MAGFILTER	= LINEAR;
};

struct VS_INPUT
{
	float4 position : POSITION;
	float4 normal   : NORMAL;
	float4 color    : COLOR;
	float4 tex		: TEXCOORD;
	float4 weight   : BLENDWEIGHT;
	float4 index    : BLENDINDICES;
	float4 tangent	: TANGENT;
};

struct VtoP
{
	float4 position	: POSITION;
	half4  diffuse	: COLOR0;
	half4  specular	: COLOR1;
	half4  t0		: TEXCOORD0;	// Environment Map
	half4  t1		: TEXCOORD1;	// Base Texture Map
	half4  t2		: TEXCOORD2;	// Shadow Map
	half4  view		: TEXCOORD3;
	float3 vLight1	: TEXCOORD4;
	float3 vLight2	: TEXCOORD5;
	float3 vLight3	: TEXCOORD6;
};

struct PS_OUTPUT
{
	float4 color : COLOR0;
};

#include "shadowmap_fx_def.h"

VtoP vertex_shader(const VS_INPUT IN)
{
	VtoP OUT;
	
	float4 p;
	p  = mul(IN.position, BlendMatrices[ IN.index.x ])*IN.weight.x;
	p += mul(IN.position, BlendMatrices[ IN.index.y ])*IN.weight.y;
	p += mul(IN.position, BlendMatrices[ IN.index.z ])*IN.weight.z;

	// we have to do a transposed matrix multiply for the normals just using the first matrix    
	half4 n;
	n.xyz  = IN.normal.xxx * BlendMatrices[ IN.index.x ][0].xyz;
	n.xyz += IN.normal.yyy * BlendMatrices[ IN.index.x ][1].xyz;
	n.xyz += IN.normal.zzz * BlendMatrices[ IN.index.x ][2].xyz;
	n.w = 0;
	
	// we have to do a transposed matrix multiply for the tangents just using the first matrix    
	half4 t;
	t.xyz  = IN.tangent.xxx * BlendMatrices[ IN.index.x ][0].xyz;
	t.xyz += IN.tangent.yyy * BlendMatrices[ IN.index.x ][1].xyz;
	t.xyz += IN.tangent.zzz * BlendMatrices[ IN.index.x ][2].xyz;
	t.w = 0;

	OUT.position = world_position(p);
	OUT.t1	= IN.tex;
	OUT.t2  = vertex_shadow_tex( IN.position );
	
	// Calculate parameters use for the grazingto facing colour shift
	// based on the viewing angle

	half3 view_vector = normalize(LocalEyePos - p); 
	half vdotn		= dot( view_vector, n );
		 vdotn		= max( 0.01f, vdotn );
	half specvdotn	= pow( vdotn, SpecularPower );
	half envvdotn	= pow( vdotn, EnvmapPower );
	OUT.diffuse		= DiffuseMin  + (vdotn	 * DiffuseRange);
	OUT.specular = SpecularMin + (specvdotn * SpecularRange);
	OUT.specular.w	= 2 * (EnvmapMin + envvdotn * EnvmapRange);

	// Leave view and lights in local space
	OUT.view.xyz		= view_vector;
	OUT.view.w			= 1;

	// Environment mapping texture coords
	half4 reflection = half4(2.0f*vdotn*IN.normal - view_vector, 0.0f); // R = 2 * (N.V) * N - V
	OUT.t0 = half4(mul( reflection, WorldView ).xyz, 1.0f);
	
	// Accumulate the diffuse for all lights
	half	ndotL1	= dot(n, LocalDirectionMatrix._m00_m10_m20);				// N.L1

//	half	ndotL2	= dot(n, LocalDirectionMatrix._m01_m11_m21);				// N.L2
//	half	ndotL3	= dot(n, LocalDirectionMatrix._m02_m12_m22);				// N.L2
//	half3	diffuse = saturate(ndotL1+0.3) * LocalColourMatrix[0].xyz +
//					  saturate(ndotL2+0.3) * LocalColourMatrix[1].xyz +
//					  saturate(ndotL3+0.3) * LocalColourMatrix[2].xyz;
//	OUT.diffuse.xyz	*= diffuse;

	// Calculate the specular for just the first light (i.e. the sun)
	half3 reflectionSpec  = 2*n*ndotL1 - LocalDirectionMatrix._m00_m10_m20;		// R = 2 * (N.L1) * N - L1
	half3 reflectDotView = saturate(dot(reflectionSpec, view_vector));
	half3 specular = pow(reflectDotView, SpecularPower); // S = (R.V) ^ n
	//specular += pow(reflectDotView, SpecularPower*100) * SpecularHotSpot;			// S = (R.V) ^ n
	// Hot spot specular - helps define the sun centre
	specular *= LocalColourMatrix[0].xyz;
	OUT.specular.xyz *= specular * OUT.diffuse.w;

	// compute transform matrix to transform from
	// world to tangent space
	float3x3 mToTangent;
	mToTangent[0]	= t;
	mToTangent[1]	= cross( n, t ) * IN.tangent.w;
	mToTangent[2]	= n;

	OUT.vLight1.xyz	= normalize( mul( mToTangent, LocalDirectionMatrix._m00_m10_m20 ) );
	OUT.vLight2.xyz	= normalize( mul( mToTangent, LocalDirectionMatrix._m01_m11_m21 ) );
	OUT.vLight3.xyz	= normalize( mul( mToTangent, LocalDirectionMatrix._m02_m12_m22 ) );

	return OUT; 
}

float4 pixel_shader(const VtoP IN) : COLOR0
{
	half4 diffuse_sample	= tex2D(DIFFUSEMAP_SAMPLER, IN.t1.xy);
	half4 envmap_sample		= texCUBE( ENVIROMAP_SAMPLER, IN.t0);
	half3 envmap_color		= envmap_sample * IN.specular.w;
	half4 normalmap_sample	= tex2Dbias( NORMALMAP_SAMPLER, IN.t1 );
	half4 specmap_sample	= tex2D( SPECULARMAP_SAMPLER, IN.t1.xy );

	//convert between unsigned and signed normal map data
	half4	vNorm = (normalmap_sample - 0.5)*2;
	vNorm = normalize( vNorm );

	half	ndotL1	= dot(vNorm, IN.vLight1),				// N.L1
			ndotL2	= dot(vNorm, IN.vLight2),				// N.L2
			ndotL3	= dot(vNorm, IN.vLight3);				// N.L3

	half4	diffuse = 0.0f;
	diffuse.xyz += saturate(ndotL1) * LocalColourMatrix[0].xyz;
	diffuse.xyz += saturate(ndotL2) * LocalColourMatrix[1].xyz;
	diffuse.xyz += saturate(ndotL3) * LocalColourMatrix[2].xyz;
	diffuse.w = IN.diffuse.w;
	
	half4 result;
//	result.xyz = IN.diffuse;										// diffuse
//	result.xyz += IN.specular;										// specular
	result.xyz = diffuse * diffuse_sample;							// diffuse
	result.xyz += IN.specular * specmap_sample * g_fSpecMapScale;	// specular
	result.xyz += IN.diffuse.w * envmap_color;						// environ gloss mapping (2x)
	result.xyz *= Brightness;										// PS2 brightness factor
	result.w   = IN.diffuse.w * diffuse_sample.w * 2.0f;			// alpha

	return result;
}

technique world <int shader = 1;>
{
    pass p0
    {
        VertexShader = compile vs_1_1 vertex_shader();
        PixelShader  = compile ps_1_1 pixel_shader();
    }
}

/////////////////////////////////////////////////////////////////////////////////////////
//
// Shadow maps
//
/////////////////////////////////////////////////////////////////////////////////////////

#include "shadowmap_fx.h"

/////////////////////////////////////////////////////////////////////////////////////////
//
// vertex_shader_light_skinned: simple position shader for shadow maps
//
/////////////////////////////////////////////////////////////////////////////////////////

VtoP_Light vertex_shader_light_skinned(const VS_INPUT IN)
{
	VtoP_Light OUT;

	float4 p;
	p  = mul(IN.position, BlendMatrices[ IN.index.x ])*IN.weight.x;
	p += mul(IN.position, BlendMatrices[ IN.index.y ])*IN.weight.y;
	p += mul(IN.position, BlendMatrices[ IN.index.z ])*IN.weight.z;

	OUT.position = world_position(p);
	
	// store depth in 'spare' coord
	OUT.dist.xy = OUT.position.zw;

	OUT.diffuseTex.xy = IN.tex.xy;
	OUT.diffuseTex.zw = 1.0f;
	
	return OUT;
}

/////////////////////////////////////////////////////////////////////////////////////////

technique RenderLightSkinned <int shader = 1;>
{
    pass p0
    {
		VertexShader = compile vs_1_1 vertex_shader_light_skinned();
        PixelShader  = NULL;
    }
}

/////////////////////////////////////////////////////////////////////////////////////////
