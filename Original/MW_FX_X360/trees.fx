//
// Standard Effect
//

#include "global.h"
#include "lightscattering.h"

float4x4 WorldView		: WORLDVIEW;
float4x4 World			: WORLDMAT;
float4 TextureOffset		: TEXTUREANIMOFFSET;
float4x4 TextureOffsetMatrix : TEXTUREOFFSETMATRIX;

float4 Params			: STANDARD_BRIGHTNESS;

float4 LightDirVec		: LOCALLIGHTDIRVECTOR;
float4 LocalCentre		: LOCALCENTER;
float4 DiffuseColour	: DIFFUSECOLOUR;
float3 LocalEyePos		: LOCALEYEPOS;


sampler DIFFUSEMAP_SAMPLER = sampler_state
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
	float4 tex		: TEXCOORD;
	float4 tex1		: TEXCOORD1;
};

struct VtoP
{
	float4 position		: POSITION;
	float4 vertexColour	: COLOR0;
	float4 tex			: TEXCOORD0;
	float4 diffuse		: TEXCOORD1;
	float3 FogAdd		: TEXCOORD2;
	float3 FogMod		: TEXCOORD3;
};

#include "shadowmap_fx_def.h"

VtoP vertex_shader(const VS_INPUT IN)
{
	VtoP OUT;
	float brightness	= Params[1];
	float mipmapBias	= Params[2];
	float diffuseFalloff= Params[3];
	
	OUT.position	= world_position(IN.position);
	OUT.tex			= IN.tex;
	OUT.tex.w		= mipmapBias;
	OUT.vertexColour= IN.color; 
	

	// We can fake diffuse lighting of billboard objects using and object's
	// center point as an origin and use directions from the vertices to the
	// origin as fake normals
	float3 normal = normalize(IN.position.xyz - LocalCentre.xyz);
	float  ndotL = saturate(dot(normal, LightDirVec));
	OUT.diffuse =  brightness * saturate(ndotL + diffuseFalloff) * DiffuseColour;

	// Shadow coordinates
	/*p.y   = -p.y;
	p.xy +=  p.w; // add "one" - texture bias
	p.xy *=  0.5;
	OUT.shadowMatTex = p;*/

	float3 lightDir = normalize(LightDirVec);
	float3 viewer = normalize(LocalEyePos.xyz - IN.position.xyz);

	float dist = mul(IN.position, WorldView).z;
	float cos_theta = dot(lightDir, viewer);
	CalcFog(dist, cos_theta, OUT.FogAdd.xyz, OUT.FogMod.xyz);
	
	return OUT;
}

float4 pixel_shader(const VtoP IN) : COLOR0
{
	float4 result;

	float ambient		= Params[0];
	
	float4 baseTex = tex2Dbias(DIFFUSEMAP_SAMPLER, IN.tex);
	
	result.xyz  = ambient;//AmbientColour;
	result.xyz += IN.diffuse;
	result.xyz *= baseTex;
	result.xyz  *= 2;//Brightness;
	result.xyz *= IN.FogMod;
	result.xyz += IN.FogAdd;
	result.w    = baseTex.w;

	return result;
}

//
// Two pass technique used to reduce sort problems within a meshs polygons.  
//
technique standard <int shader = 1;>
{
    pass p0	// punch through a portion of the billboard based on alpha
    {
        VertexShader = compile vs_1_1 vertex_shader();
        PixelShader  = compile ps_2_0 pixel_shader();
    }
    pass p1	// punch through a portion of the billboard based on alpha
    {
        VertexShader = compile vs_1_1 vertex_shader();
        PixelShader  = compile ps_2_0 pixel_shader();
    }
}

struct PS_OUTPUT
{
	float4 color : COLOR0;
};

#include "ZPrePass_fx.h"
#include "shadowmap_fx.h"
