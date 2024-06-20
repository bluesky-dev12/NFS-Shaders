///////////////////////////////////////////////////////////////////////////////
//
// GRASS SHADER
//
// Use a shell technique to render volumetric grass
//
// Colin O'Connor
// Nov-2004
//
///////////////////////////////////////////////////////////////////////////////
#include "global.h" 
#include "lightscattering.h" 

///////////////////////////////////////////////////////////////////////////////
// RUNTIME SETTINGS

// These parameters should be set by the runtime engine
float4	 LocalEyePos			: LOCALEYEPOS;
float4x4 WorldView				: WORLDVIEW;
float4x4 World					: WORLDMAT;

float4	 LocalLightVec			: LOCALLIGHTDIRVECTOR;
float4	 SpecularColour			: SPECULARCOLOUR;
float	 SpecularPower			: SPECULARPOWER;
float4	 DiffuseColour			: DIFFUSECOLOUR;

///////////////////////////////////////////////////////////////////////////////
// LIGHT MATERIAL TWEAKABLES 

float4	GRASSCOLOUR = {0.627f, 0.9f, 0.627f, 1};
float	MAXSHELLS;
float	GRASSHEIGHT = 0.01;
float	DIFFUSESPACE = 1.0f;
float	DIFFUSEMIPMAPBIAS = -5.5f;
float	NOISESPACE = 2.0f;
float	NOISEMIPMAPBIAS = -2.0f;
float	LOWNOISESPACE = 0.008f;
float	LOWNOISEINTENSITY = 0.035f;
float	SCRUFF = .033f;
float	CURLTIGHTNESS = 1.05f;
float	LODSTART = 3.7f;
float	LODRAMP = 0.3f;
float	GRASSGAMMA = 1.8f;
const bool	IS_PARALLEX_MAPPED;

///////////////////////////////////////////////////////////////////////////////
// LOD LOOKUP TABLE

#define MAX_MAXSHELLS	5
#define NUM_LODS		2

///////////////////////////////////////////////////////////////////////////////
// TEXTURE SAMPLERS

// For sampler state purposes, these samplers should be defined in the order listed 
// in the eSolidPlat.hpp TextureMapsIndicies enum
sampler DIFFUSEMAP_SAMPLER = sampler_state 
{
    MIPFILTER = LINEAR;
    MINFILTER = LINEAR;
    MAGFILTER = LINEAR;
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

sampler OPACITYMAP_SAMPLER = sampler_state 
{
    MIPFILTER = LINEAR;
    MINFILTER = LINEAR;
    MAGFILTER = LINEAR;
};

sampler3D VOLUMEMAP_SAMPLER = sampler_state 
{
    AddressU  = WRAP;        
    AddressV  = WRAP;
    AddressW  = WRAP;
    MIPFILTER = LINEAR;
    MINFILTER = LINEAR;
    MAGFILTER = LINEAR;
};

sampler MISCMAP1_SAMPLER = sampler_state // noise 3d sampler
{
    AddressU  = WRAP;        
    AddressV  = WRAP;
    MIPFILTER = LINEAR;
    MINFILTER = LINEAR;
    MAGFILTER = LINEAR;
};


///////////////////////////////////////////////////////////////////////////////
// SHADER INPUT/OUTPUT STRUCTURES

struct VS_INPUT
{
	float4 position : POSITION;
	float3 normal	: NORMAL;
	float4 color    : COLOR;
	float4 tex		: TEXCOORD;
	float4 tangent	: TANGENT;
};

struct VtoP
{
	float4 position		: POSITION;
	float4 ambient		: COLOR0;
	float4 diffuse		: COLOR1;
	float3 FogMod		: COLOR2;
	float3 FogAdd		: COLOR3;
	float4 tex			: TEXCOORD0;
	float3 Light		: TEXCOORD1;
	float4 noiseUV		: TEXCOORD2;
	float4 shadowTex	: TEXCOORD3;
	float4 noise3DPos   : TEXCOORD4;
	float3 normal		: TEXCOORD5;
	float3 View			: TEXCOORD6;
};

struct PS_OUTPUT
{
	float4 color : COLOR0;
};

#include "shadowmap_fx_def.h"

///////////////////////////////////////////////////////////////////////////////
// VERTEX SHADERS
VtoP VertexShaderGrass(VS_INPUT IN, uniform float shellHeight, uniform int shellIndex) 
{
    VtoP OUT;

	float3 position = IN.position.xyz;

	// Specular calculations.  Default them to use non-tangent space
	OUT.Light = LocalLightVec;
	OUT.View.xyz = float3(LocalEyePos - position);

	//
	// Adjust the shell height down as the vertex moves away from the camera
	// so we can transition to one shell at a distance and not have seams
	//
	float shellLODHeight = shellHeight * shellIndex;
	float shellLODValue = 1;
	float distFromCamera = length(OUT.View.xyz);
	if( distFromCamera > LODSTART )
	{
		shellLODHeight = 0;		
		shellLODValue = 0;
	}

	//
	// Offset the vertex shell in the direction of the eye position.  This eliminates
	// seams related to sorting order
	//
	float3 viewNormal = normalize(OUT.View.xyz);
	float heightScale = clamp(1.0f / dot(IN.normal, viewNormal), 1, 40);
	
	float3 P = position + heightScale * viewNormal * shellLODHeight;
	float4 p = float4(P, 1.0f);
	OUT.position = world_position(p);

	OUT.shadowTex = vertex_shadow_tex( IN.position );

	//
	// Offset the uv back torwards the normal so the grass grows up the normal axis
	// not towards the eye position
	//
	float3 uvoffset = (IN.normal - heightScale * viewNormal) * shellLODHeight;
	
	float scruffOffset = shellIndex ? shellIndex / MAXSHELLS : 1;
	OUT.tex = float4(DIFFUSESPACE*IN.tex.xy, OUT.position.w, scruffOffset * SCRUFF);
	// Build the high and low noise UV set using world position
	float4 worldPos = mul(float4(position, 1.0f), World);
	OUT.noiseUV = float4(worldPos.xy*LOWNOISESPACE, (IN.position.xy+uvoffset.xy)*NOISESPACE);
	
	OUT.noise3DPos.xyz = CURLTIGHTNESS * P * NOISESPACE; 
	OUT.ambient	= IN.color * float4(AmbientColour.xyz * AmbientColour.w, 1.0f);
	
	float ndotL = saturate(dot(IN.normal, LocalLightVec));
	OUT.diffuse = (ndotL * DiffuseColour);
	OUT.normal = IN.normal;

  	OUT.noise3DPos.w = shellLODValue;

	float dist = mul(IN.position, WorldView).z;
	float cos_theta = dot(normalize(LocalLightVec), viewNormal);
	CalcFog(dist, cos_theta, OUT.FogAdd.xyz, OUT.FogMod.xyz);
	if( shellIndex > 0 )
	{
		OUT.ambient = float4(0, 0, 0, 1); 
	}

    return OUT;
}

// These tables supply coefficients to the pixel shader to try and correct
// colour discrepencies between rendering with 1 shell or 5 shells
//
const float AmbientShellTable[6] = { 0, 0.300, 0.275, 0.250, 0.225, 0.200 };
const float AmbientNoiseTable[6] = { 0, 1.000, 0.450, 0.270, 0.220, 0.160 };
const float DiffuseShellTable[6] = { 0, 1.200, 1.225, 1.250, 1.075, 1.200 };
float4 PixelShaderGrass( VtoP IN, uniform int shellIndex): COLOR
{
	float shadow = DoShadow( IN.shadowTex, 1 );

	//
	// Determine LOD shell information.  IN.noise3DPos.w yields a float between 0 and 1 that
	// determines the desired LOD - 0 is the lowest, 1 is the highest. 
	//		LOD 0: only render layer 0
	//		LOD 1: render all MAXSHELL layers
	int isMaxLod = (IN.noise3DPos.w > 0) ? 1 : 0;//clamp(IN.noise3DPos.w, 0, NUM_LODS-1);
	if( isMaxLod || (isMaxLod == 0 && shellIndex == 0))
	{
		//
		// APPLY 3D NOISE OFFSET TO UV
		//
		
		// Offset set uv's according to a 3d vector defined by a noise 3D lookup texture.  This
		// gives the effect of "growing" the grass blades in different directions
		float4 noise3d = tex3D(VOLUMEMAP_SAMPLER, IN.noise3DPos.xyz) - 0.5f;
		float2 offsetUV = IN.noiseUV.zw + IN.tex.w * noise3d;
		
		// Shell ambient influence
		int numShellsAtLOD = isMaxLod ? MAXSHELLS : 1;
		float kAmbientShell = AmbientShellTable[numShellsAtLOD];
		float kAmbientNoise = AmbientNoiseTable[numShellsAtLOD];
		float kDiffuseShell = DiffuseShellTable[numShellsAtLOD];
		
		// 
		// EXTRACT INFORMATION FROM TEXTURES
		//
		float3 grassBlendColour = GRASSCOLOUR / numShellsAtLOD; 
		// Extract High frequency noise from the x channel in noise2d texture
		float highNoiseTexture = tex2Dbias( MISCMAP1_SAMPLER, float4(offsetUV.xy, 0.0, NOISEMIPMAPBIAS) ).x; 
		float4 highNoiseColour = float4(grassBlendColour.xyz, GRASSCOLOUR.w) * highNoiseTexture;
		// Extract a Low Frequency noise from the y channel in noise2d texture 
		float lowNoiseValue = tex2D( MISCMAP1_SAMPLER, IN.noiseUV.xy ).y; 
		lowNoiseValue = (lowNoiseValue - 0.5f) * LOWNOISEINTENSITY;
		float4 lowNoiseColour = float4(grassBlendColour.xyz, GRASSCOLOUR.w) * lowNoiseValue;
		// Extract colour from diffuse map
		float4 diffuseTexture = tex2Dbias( DIFFUSEMAP_SAMPLER, float4(IN.tex.xy, 0.0, DIFFUSEMIPMAPBIAS) );

		//				
		// DIFFUSE COLOUR COMPONENT
		//
		
		// Basic diffuse calculation
		float4 diffuse = IN.diffuse * kDiffuseShell * diffuseTexture;
		// Modulate with high noise frquencency
		diffuse *= highNoiseColour;
		// Modulate with shadow
		diffuse.xyz *= shadow;

		//	
		// AMBIENT COLOUR COMPONENT
		//
		
		// Add a percentage of high noise into the ambient to give contrast and texture in the shadows.  Add
		// more in when rendering fewer shells
		float4 ambient = IN.ambient + highNoiseColour*kAmbientNoise;
		// Modulate with the shell index to darken the bottom and and brighten the top
		ambient *= (shellIndex+kAmbientShell);
		// Add in the low noise frequency to provide soft variation over large areas
		ambient += lowNoiseColour;
		// Modulate with the diffuse texture	
		ambient *= diffuseTexture;

		// Combine 
		float4 result = ambient + diffuse;
		
		// PSX gamma correction
		result.xyz *= 2;

		if( MAXSHELLS == 1 )
		{
			//result.xyz *= IN.FogMod;
			//result.xyz += IN.FogAdd;
		}
	

		// The blend mode is colour addition so set the alpha to one to add all this colour
		result.w = GRASSCOLOUR.w;

		return result;
	}
	else
	{
		clip(-1);
		return 0;
	}
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

float4 PixelShaderWorldNormal( VtoP IN): COLOR
{
    float3 viewDir	= normalize(IN.View);	// V
	// Offset parallex mapping
	float4 tex = float4(IN.tex.xy, 0, -1);
	if( IS_PARALLEX_MAPPED )	
	{
		tex = ParallexMapped(viewDir, IN);
	}
	
	float4 base		= tex2Dbias(DIFFUSEMAP_SAMPLER, tex); //diffuse map
	float3 norm		= tex2Dbias(NORMALMAP_SAMPLER, tex); // normal map
	float3 specMap	= tex2Dbias(SPECULARMAP_SAMPLER, tex); // normal map
	float4 shadow	= DoShadow( IN.shadowTex, 1 ); //shadow map

	//convert between unsigned and signed normal map data
	norm = (norm - 0.5)*2;
	
	norm = normalize(norm);
	
	float3 lightDir	= normalize(IN.Light);	// L

    float ndotL = dot(norm, lightDir);	
	float diff	= saturate(ndotL);
	
	float3 reflection = 2*ndotL*norm - lightDir;
	
	float specular = saturate(dot(reflection, viewDir)); //specular comp.
	specular = pow(specular, SpecularPower);

	float shadowMult	= saturate(4 * dot(IN.normal, LocalLightVec));				// compute self-shadowing term 

	float4 result = base * diff * DiffuseColour;	//diffuse
	result.xyz += specular * SpecularColour * specMap;	
	result.xyz *= shadowMult * shadow;
	result.xyz += base * IN.ambient;				//ambient
	result.xyz *= 2;
	//result.xyz *= IN.FogMod;
	//result.xyz += IN.FogAdd;

	result.w = base.w;

	return result;
}

///////////////////////////////////////////////////////////////////////////////
// GRASS TECHNIQUE
//

technique Grass
{
    pass Shell0
    {		
		VertexShader = compile vs_2_0 VertexShaderGrass(GRASSHEIGHT/MAXSHELLS, 0);
		PixelShader  = compile ps_3_0 PixelShaderGrass(0);
    }
    pass Shell1
    {		
		VertexShader = compile vs_2_0 VertexShaderGrass(GRASSHEIGHT/MAXSHELLS, 1);
		PixelShader  = compile ps_3_0 PixelShaderGrass(1);
    }
    pass Shell2
    {		
		VertexShader = compile vs_2_0 VertexShaderGrass(GRASSHEIGHT/MAXSHELLS, 2);
		PixelShader  = compile ps_3_0 PixelShaderGrass(2);
    }
    pass Shell3
    {		
		VertexShader = compile vs_2_0 VertexShaderGrass(GRASSHEIGHT/MAXSHELLS, 3);
		PixelShader  = compile ps_3_0 PixelShaderGrass(3);
    }
    pass Shell4
    {		
		VertexShader = compile vs_2_0 VertexShaderGrass(GRASSHEIGHT/MAXSHELLS, 4);
		PixelShader  = compile ps_3_0 PixelShaderGrass(4);
    }
}


///////////////////////////////////////////////////////////////////////////////
// GRASS TRANSITION PIXEL SHADER AND TECHNIQUE
//
// Use the opacity map to determine where to draw grass.  Where there is no
// grass use a normal map shader.  Mip mapping on the opacity map will yield
// grey opacity values, use a blend when this occurs.  Only blend/transition
// the first pass, the remaining layers should ignore/clip the non grass pixels.
//

VtoP VertexShaderGrassTransition(VS_INPUT IN, uniform float shellHeight, uniform int shellIndex) 
{
	VtoP OUT;
	OUT = VertexShaderGrass(IN, shellHeight, shellIndex); 

	// More complex specular calculations.  Only used in grass transitions.
	float3x3 mToTangent;
	mToTangent[0]	= IN.tangent;
	mToTangent[2]	= IN.normal;
	mToTangent[1]	= cross( mToTangent[2], mToTangent[0] ) * IN.tangent.w;
	OUT.Light.xyz	= mul( mToTangent, LocalLightVec );
	float3 Viewer	= LocalEyePos - IN.position;
	OUT.View		= mul( mToTangent, Viewer );	//Compute the reflection vector

	return OUT;
}

float4 PixelShaderTransitionFirstPass( VtoP IN, uniform int shellIndex): COLOR
{
	float4 result;
	float opacityValue = tex2D( OPACITYMAP_SAMPLER, IN.tex.xy ).x;
	if( opacityValue <= 0.5f )
	{
		result = PixelShaderWorldNormal(IN);
	}
	else
	{
		result = PixelShaderGrass(IN, shellIndex);
	}

	return result;
}

float4 PixelShaderTransitionMultiPass( VtoP IN, uniform int shellIndex): COLOR
{
	float4 result;
	// The opacity value determines where to draw grass - good for transitions
	float opacityValue = tex2D( OPACITYMAP_SAMPLER, IN.tex.xy ).x;
	if( opacityValue <= 0.5f )
	{
		// The world pixel shader only renders on the first pass - so clip the rest
		clip(-1);
	}
	else
	{
		result = PixelShaderGrass(IN, shellIndex);
	}
	
	return result;
}

technique GrassTransition
{
    pass Shell0
    {		
		VertexShader = compile vs_2_0 VertexShaderGrassTransition(GRASSHEIGHT/MAXSHELLS, 0);
		PixelShader  = compile ps_3_0 PixelShaderTransitionFirstPass(0);
    }
    pass Shell1
    {		
		VertexShader = compile vs_2_0 VertexShaderGrassTransition(GRASSHEIGHT/MAXSHELLS, 1);
		PixelShader  = compile ps_3_0 PixelShaderTransitionMultiPass(1);
    }
    pass Shell2
    {		
		VertexShader = compile vs_2_0 VertexShaderGrassTransition(GRASSHEIGHT/MAXSHELLS, 2);
		PixelShader  = compile ps_3_0 PixelShaderTransitionMultiPass(2);
    }
    pass Shell3
    {		
		VertexShader = compile vs_2_0 VertexShaderGrassTransition(GRASSHEIGHT/MAXSHELLS, 3);
		PixelShader  = compile ps_3_0 PixelShaderTransitionMultiPass(3);
    }
    pass Shell4
    {		
		VertexShader = compile vs_2_0 VertexShaderGrassTransition(GRASSHEIGHT/MAXSHELLS, 4);
		PixelShader  = compile ps_3_0 PixelShaderTransitionMultiPass(4);
    }
}


#include "ZPrePass_fx.h"
#include "shadowmap_fx.h"

