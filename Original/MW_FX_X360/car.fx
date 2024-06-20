//
// Car Effects
//
#include "global.h"

float4x4 WorldView       : WORLDVIEW ;
float4x4 LocalDirectionMatrix	: LOCALDIRECTIONMATRIX;
float4x4 LocalColourMatrix		: LOCALCOLOURMATRIX;

float4 LocalEyePos : LOCALEYEPOS;
//float4 CarLocalEyePos;

float  MetallicScale	 : METALLICSCALE;
float  SpecularHotSpot	 : SPECULARHOTSPOT;

float4 DiffuseMin		 : DIFFUSEMIN;
float4 DiffuseRange		 : DIFFUSERANGE;
float4 SpecularMin		 : SPECULARMIN;
float4 SpecularRange     : SPECULARRANGE;
float4 EnvmapMin		 : ENVMAPMIN;
float4 EnvmapRange       : ENVMAPANGE;
float  SpecularPower	 : SPECULARPOWER;
float  EnvmapPower		 : ENVMAPPOWER;

float4 ShadowColour		 : CARSHADOWCOLOUR; 

int	g_bDoCarShadowMap	 : SHADOWMAP_CAR_SHADOW_ENABLED;

float FocalRange		 : FOCALRANGE;

float RVMSkyBrightness	 : RVM_SKY_BRIGHTNESS;
float RVMWorldBrightness : RVM_WORLD_BRIGHTNESS;

float Desaturation				: DESATURATION;

float4	Coeffs0					: CURVE_COEFFS_0;
float4	Coeffs1					: CURVE_COEFFS_1;
float4	Coeffs2					: CURVE_COEFFS_2;
float4	Coeffs3					: CURVE_COEFFS_3;

float	CombinedBrightness		: COMBINED_BRIGHTNESS;

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
	half3  lights[1]	  : TEXCOORD5;
	half3  localPos		  : TEXCOORD6;
};


VtoP vertex_shader(const VS_INPUT IN)
{
	VtoP OUT;
	OUT.position = world_position(IN.position);
	OUT.normal	= IN.normal;
	OUT.t1	= IN.tex;
	OUT.t2  = vertex_shadow_tex( IN.position );
	
	float radiosity = saturate(IN.color.x*2);		// vertex colours: 0.5 = 1.0 to allow for overbrightening
	
	// Calculate parameters use for the grazingto facing colour shift
	// based on the viewing angle
	float3 ViewDir = LocalEyePos - IN.position;

	// Metallic paint distance falloff coeff
	OUT.view.w = saturate(length(ViewDir)*-0.25 + 1.2);	// line equation
	OUT.view.w *= 0.04*MetallicScale;
	
	half3 view_vector = normalize(ViewDir); 
	half vdotn		= dot( view_vector, IN.normal );
		 vdotn		= max( 0.01f, vdotn );
	half specvdotn	= pow( vdotn, SpecularPower );
	half envvdotn	= pow( vdotn, EnvmapPower );
	// Grazing=Min, Facing = Min+Range
	//OUT.diffuse  = DiffuseMin*0.1  + (vdotn * DiffuseRange/0.1);
	OUT.diffuse  = DiffuseMin  + (vdotn * DiffuseRange);
	OUT.specular = SpecularMin + (specvdotn * SpecularRange);
	OUT.specular *= radiosity;
	OUT.specular.w	= (EnvmapMin.x + envvdotn * EnvmapRange.x);
	OUT.specular.w *= radiosity;

	// Leave view and lights in local space
	OUT.view.xyz		= ViewDir;
	OUT.lights[0].xyz	= LocalDirectionMatrix._m00_m10_m20;
	// Environment mapping texture coords
	half4 reflection = half4(2.0f*vdotn*IN.normal - view_vector, 0.0f); // R = 2 * (N.V) * N - V
	OUT.t0 = half4(mul( reflection, WorldView ).xyz, 1.0f);

	// Accumulate the diffuse for both lights
	half  ndotL1 = dot(IN.normal, LocalDirectionMatrix._m00_m10_m20);				// N.L1
	half  ndotL2 = dot(IN.normal, LocalDirectionMatrix._m01_m11_m21);				// N.L2
	half  ndotL3 = dot(IN.normal, LocalDirectionMatrix._m02_m12_m22);				// N.L2
	half3 diffuse  = saturate(ndotL1+0.1)  * LocalColourMatrix[0].xyz;
	diffuse		  += saturate(ndotL2+0.1) * LocalColourMatrix[1].xyz;
	diffuse		  += saturate(ndotL3)     * LocalColourMatrix[2].xyz;
	OUT.diffuse.xyz *= diffuse * radiosity;
	
	// We have run out of textcord slots so move the world position into the w components
	// of the normal and light vectors
	OUT.localPos    = IN.position * 20;
	
	return OUT; 
}

float4 pixel_shader(const VtoP IN) : COLOR0
{
	//
	// Implement phong specular model with environmental mapping
	// 
	half4	diffuse_sample	= tex2D(DIFFUSEMAP_SAMPLER, IN.t1.xy);
	float3	position		= IN.localPos;
	half4	noise_sample	= tex3Dbias(VOLUMEMAP_SAMPLER, float4(position, -3));
	half3	flakeNoise		= (noise_sample - 0.5) * 2;
	half	shadow = 1.0;

	if ( g_bDoCarShadowMap )
	{
		shadow = DoShadow( IN.t2, 1 );
	}

	// Use the vertex normal
	half3 normal = normalize(IN.normal.xyz);				// N

	half4 envmap_sample = texCUBE( ENVIROMAP_SAMPLER, IN.t0);
	// The environment maps alpha channel stores a light bloom mask
	half3 envmap_bloom = envmap_sample.w*envmap_sample.xyz*2;
	half3 envmap_color = (envmap_sample + envmap_bloom) * IN.specular.w; 

	// Apply a metallic flake to the specular
    half3 viewDir	  = normalize(IN.view.xyz);			// V
	half3 normalFlake = normalize(normal + flakeNoise*IN.view.w);
	half  ndotL1Flake = dot(normalFlake, IN.lights[0].xyz);				// N.L1

	// Calculate the specular for just the first light (i.e. the sun)
	// Base specular falloff	
	half3 reflection  = 2*normalFlake*ndotL1Flake - IN.lights[0].xyz;		// R = 2 * (N.L1) * N - L1
	half3 rdotV = saturate(dot(reflection, viewDir));
	half3 specular = pow(rdotV, SpecularPower); // S = (R.V) ^ n
	// Hot spot specular - helps define the sun centre
	half3 hotSpot = pow(rdotV, SpecularPower*80) * shadow.r * SpecularHotSpot * 5;
	specular += hotSpot;			// S = (R.V) ^ n
	specular *= LocalColourMatrix[0].xyz;
	
	half4 result;
	result.xyz = IN.diffuse * diffuse_sample;								// diffuse
	result.xyz += IN.diffuse.w * specular * IN.specular * shadow.r;			// specular
	result.xyz *= lerp(ShadowColour.xyz, 1, shadow.r);						// shadow;
	result.xyz += IN.diffuse.w * envmap_color;								// environ gloss mapping
	result.w   =  IN.diffuse.w * diffuse_sample.w;		// alpha
	
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
	// Environment mapping texture coords
	half4 reflection = half4(2.0f*vdotn*IN.normal - view_vector, 0.0f); // R = 2 * (N.V) * N - V
	OUT.t0 = half4(mul( reflection, WorldView ).xyz, 1.0f);
	
	// We have run out of textcord slots so move the world position into the w components
	// of the normal and light vectors
	OUT.localPos    = IN.position;

	// Accumulate the diffuse for both lights
	half  ndotL1	= dot(IN.normal, LocalDirectionMatrix._m00_m10_m20);				// N.L1
	half  ndotL2	= dot(IN.normal, LocalDirectionMatrix._m01_m11_m21);				// N.L2
	half3 diffuse	= saturate(ndotL1+0.3) * LocalColourMatrix[0].xyz;
	diffuse			+= saturate(ndotL2+0.3) * LocalColourMatrix[1].xyz;
	OUT.diffuse.xyz	*= diffuse * IN.color.x;
	
	// Calculate the specular for just the first light (i.e. the sun)
	/*half3 reflectionSpec  = 2*IN.normal*ndotL1 - OUT.lights[0].xyz;		// R = 2 * (N.L1) * N - L1
	half3 reflectDotView = saturate(dot(reflectionSpec, view_vector));
	half3 specular = pow(reflectDotView, SpecularPower) * 0.7; // S = (R.V) ^ n
	specular += pow(reflectDotView, SpecularPower*100) * SpecularHotSpot;			// S = (R.V) ^ n
	// Hot spot specular - helps define the sun centre
	specular *= LocalColourMatrix[0].xyz;
	OUT.specular.xyz *= specular * IN.color.x * OUT.diffuse.w; */
	OUT.specular.xyz = 0;
	
	return OUT; 
}

float4 pixel_shader_lowlod(const VtoP IN) : COLOR0
{
	half4 diffuse_sample	= tex2D(DIFFUSEMAP_SAMPLER, IN.t1.xy);
	half4 envmap_sample		= texCUBE( ENVIROMAP_SAMPLER, IN.t0);
	half3 envmap_color		= envmap_sample * IN.specular.w;
	half  shadow = 1.0;
	
	if ( g_bDoCarShadowMap )
	{
		shadow = DoShadow( IN.t2, 1 );
	}

	half4 result;
	result.xyz = IN.diffuse;			// diffuse
	result.xyz *= diffuse_sample;
	result.xyz *= lerp(ShadowColour.xyz, 1, shadow.r);						// shadow;
	//result.xyz += IN.specular;;			// specular
	result.xyz += IN.diffuse.w * envmap_color;							// environ gloss mapping (2x)
	result.w   = IN.diffuse.w * diffuse_sample.w;												// alpha
	
	//result.xyz = float3(0, 1, 0);
	return result;
}

/////////////////////////////////////////////////////////////////////////////////////////
//
// Rear View Mirror Shader
//
//
struct VtoP_RVM
{
	float4 position       : POSITION;
	half4  t0             : TEXCOORD0;	// Opacity Texture Map
	half4  t1             : TEXCOORD1;	// Environment Map
};

VtoP_RVM vertex_shader_rvm(const VS_INPUT IN)
{
//	struct VS_INPUT
//	{
//		float4 position : POSITION;		// Position in screen space
//		float4 normal   : NORMAL;		// Texture coordinates for opacity texture
//		float4 color    : COLOR;
//		float4 tex		: TEXCOORD;		// Look up for environment map
//		float4 tangent	: TANGENT;
//	};

	VtoP_RVM OUT;
	OUT.position	= IN.position;
	OUT.t0			= IN.normal;
	OUT.t1			= IN.tex;

	return OUT; 
}

float4 pixel_shader_rvm(const VtoP_RVM IN) : COLOR0
{
	float4 result;

	float4 normal = normalize(IN.t0);

	half4 opacity = tex2D(DIFFUSEMAP_SAMPLER,IN.t1.xy);
	half4 envmap = texCUBE(ENVIROMAP_SAMPLER,normal);
	
	result.xyz = envmap.xyz * RVMWorldBrightness;
	
	// Get the luminance from the full screen image
	float luminance = dot( result.xyz, LUMINANCE_VECTOR );
	
	// compute the curves 
	float4 curve = Coeffs3*luminance + Coeffs2; 
	curve = curve*luminance + Coeffs1;                  
	curve = curve*luminance + Coeffs0;
	
	// Desaturate the original image by blending between the screen and the luminance
	float3 desatScreen = luminance.xxx + Desaturation * (result.xyz - luminance.xxx);

	// Black Bloom screen
	float3 bb_result = desatScreen * curve.x;

	// Add screen result to colour bloom
	result.xyz = bb_result + curve.yzw * result.xyz;

	// Brightness masking
	result.xyz *= CombinedBrightness;

	result.w = opacity.w;

	return result;
}


technique car <int shader = 1;>
{
    pass p0
    {
		VertexShader = compile vs_3_0 vertex_shader();
		PixelShader  = compile ps_3_0 pixel_shader();
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
		//VertexShader = compile vs_3_0 vertex_shader();
		//PixelShader  = compile ps_3_0 pixel_shader();
    }
}

technique rvm <int shader = 1;>
{
    pass p0
    {
		VertexShader = compile vs_3_0 vertex_shader_rvm();
		PixelShader  = compile ps_3_0 pixel_shader_rvm();
    }
}

#include "ZPrePass_fx.h"

#include "shadowmap_fx.h"
