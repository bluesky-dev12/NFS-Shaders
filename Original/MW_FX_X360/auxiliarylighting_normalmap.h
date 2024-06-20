//
// Auxiliary Lighting
//
#include "auxiliarylighting.h"

struct VS_INPUT_AUX1
{
	float4 position		: POSITION;
	float4 normal		: NORMAL;
	float2 tex			: TEXCOORD0;
	float4 tangent		: TANGENT;
};


struct VtoP_AUXLGT
{
	float4 position		: POSITION;

	float3 AuxLight[MAX_LIGHTS]	: COLOR0;
	float4 tex			: TEXCOORD0;
	float3 View			: TEXCOORD1;
	float4 LocalPos		: TEXCOORD2;
};

VtoP_AUXLGT vertex_shader_normalmap_auxiliary_lighting(const VS_INPUT_AUX1 IN)
{
	VtoP_AUXLGT OUT;

	OUT.position	= world_position(IN.position);
	OUT.position.z -= 0.001f;	// bias the z depth
	OUT.tex.xy		= IN.tex;
	OUT.tex.z		= 1.0;
	OUT.tex.w		= MipMapBias;

	// compute transform matrix to transform from
	// world to tangent space
	float3x3 mToTangent;
	mToTangent[0]	= IN.tangent;
	mToTangent[2]	= IN.normal;
	mToTangent[1]	= cross( mToTangent[2], mToTangent[0] ) * IN.tangent.w;

	//Compute the reflection vector
	float3 Viewer	= normalize(LocalEyePos - IN.position);
	OUT.View		= mul( mToTangent, Viewer );

	OUT.AuxLight[0] = ActiveAuxiliaryLight0 ? mul( mToTangent, Lights[0][0].xyz - IN.position.xyz) : 0;
	OUT.AuxLight[1] = ActiveAuxiliaryLight1 ? mul( mToTangent, Lights[1][0].xyz - IN.position.xyz) : 0;
	OUT.AuxLight[2] = ActiveAuxiliaryLight2 ? mul( mToTangent, Lights[2][0].xyz - IN.position.xyz) : 0;
	OUT.AuxLight[3] = ActiveAuxiliaryLight3 ? mul( mToTangent, Lights[3][0].xyz - IN.position.xyz) : 0;
	OUT.AuxLight[4] = ActiveAuxiliaryLight4 ? mul( mToTangent, Lights[4][0].xyz - IN.position.xyz) : 0;
	OUT.AuxLight[5] = ActiveAuxiliaryLight5 ? mul( mToTangent, Lights[5][0].xyz - IN.position.xyz) : 0;
	OUT.LocalPos = IN.position;

	// shadowmap depth
	OUT.LocalPos.w = 1;

	return OUT;
}

float4 pixel_shader_normalmap_auxiliary_lighting(const VtoP_AUXLGT IN) : COLOR
{
	float4 baseMap	= tex2Dbias(DIFFUSEMAP_SAMPLER, IN.tex);
	float3 specMap	= tex2Dbias(SPECULARMAP_SAMPLER, IN.tex);

	//convert between unsigned and signed normal map data
	float4 norm		= tex2Dbias(NORMALMAP_SAMPLER, IN.tex); // normal map
	norm = (norm - 0.5)*2;
	norm = normalize(norm);

	float3 viewDir	= normalize(IN.View);	// V

	// Auxuliary Lights
	float3 auxLightingDiffuse = 0;
	float3 auxLightingSpecular = 0;
	if( ActiveAuxiliaryLight0 )	AuxiliaryLight(0, normalize(IN.AuxLight[0]), IN.LocalPos, norm, viewDir, auxLightingDiffuse, auxLightingSpecular);
	if( ActiveAuxiliaryLight1 )	AuxiliaryLight(1, normalize(IN.AuxLight[1]), IN.LocalPos, norm, viewDir, auxLightingDiffuse, auxLightingSpecular);
	if( ActiveAuxiliaryLight2 )	AuxiliaryLight(2, normalize(IN.AuxLight[2]), IN.LocalPos, norm, viewDir, auxLightingDiffuse, auxLightingSpecular);
	if( ActiveAuxiliaryLight3 )	AuxiliaryLight(3, normalize(IN.AuxLight[3]), IN.LocalPos, norm, viewDir, auxLightingDiffuse, auxLightingSpecular);
	if( ActiveAuxiliaryLight4 )	AuxiliaryLight(4, normalize(IN.AuxLight[4]), IN.LocalPos, norm, viewDir, auxLightingDiffuse, auxLightingSpecular);
	if( ActiveAuxiliaryLight5 )	AuxiliaryLight(5, normalize(IN.AuxLight[5]), IN.LocalPos, norm, viewDir, auxLightingDiffuse, auxLightingSpecular);
  
	float4 result;
	result.xyz  = auxLightingDiffuse  * baseMap;
	result.xyz += auxLightingSpecular * specMap;
	result.w    = 1;//baseMap.w;

	//result = 0;
	//result.z = 1;

	return result;
}
