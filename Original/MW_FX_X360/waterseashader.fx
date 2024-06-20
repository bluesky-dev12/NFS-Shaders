///////////////////////////////////////////////////////////////////////////////
#include "global.h"
#include "lightscattering.h"

float4x4 WorldView				: WORLDVIEW;
float4x4 World					: WORLDMAT;

float4	LightDirVec				: LOCALLIGHTDIRVECTOR;
float4	LocalEyePos				: LOCALEYEPOS;

float	SpecularScale			: SPECULARPOWER; 

float4	vTextureOffset			: TEXTUREANIMOFFSET;

sampler DIFFUSEMAP_SAMPLER = sampler_state
{
	AddressU = WRAP;
	AddressV = WRAP;
	MIPFILTER = LINEAR;
	MINFILTER = LINEAR;
	MAGFILTER = LINEAR;
};

// water normal map
sampler MISCMAP1_SAMPLER = sampler_state
{
	AddressU	= WRAP;
	AddressV	= WRAP;
	MIPFILTER	= LINEAR;
	MINFILTER	= LINEAR;
	MAGFILTER	= LINEAR;
};

// reflection map
sampler MISCMAP2_SAMPLER = sampler_state	// reflect texture sampler
{
	AddressU = CLAMP;
	AddressV = CLAMP;
	MIPFILTER = LINEAR;
	MINFILTER = LINEAR;
	MAGFILTER = LINEAR;
};

///////////////////////////////////////////////////////////////////////////////

struct VS_INPUT
{
	float4 position : POSITION;
	float4 color    : COLOR;
	float4 tex		: TEXCOORD;
	float3 normal	: NORMAL;
};

//struct VS_INPUT
//{
//	float4 position : POSITION;
//	float4 tex		: TEXCOORD;
//};

struct VtoP
{
	float4 position		: POSITION;
	float4 vPosLocal	: TEXCOORD0;
	float4 tex			: TEXCOORD1;
	float4 vTexR		: TEXCOORD2;
	float3 vTanToObj1	: TEXCOORD3;
	float3 vTanToObj2	: TEXCOORD4;
	float3 vTanToObj3	: TEXCOORD5;
	float3 FogAdd	    : TEXCOORD6;
	float3 FogMod	    : TEXCOORD7;
};

struct PS_OUTPUT
{
	float4 color : COLOR0;
};

///////////////////////////////////////////////////////////////////////////////
//
// wave functions

struct Wave
{
	float freq;  // 2*PI / wavelength
	float amp;   // amplitude
	float phase; // speed * 2*PI / wavelength
	float2 dir;
};

#define NWAVES 2

Wave wave0 =	{ 1.0, 0.0, 0.5, float2(-1, 0)		};
Wave wave1 =	{ 3.0, 0.0, 1.3, float2(-0.7, 0.7)	};

float evaluateWave(Wave w, float2 pos, float t)
{
  return w.amp * sin( dot(w.dir, pos)*w.freq + t*w.phase);
}

// derivative of wave function
float evaluateWaveDeriv(Wave w, float2 pos, float t)
{
  return w.freq*w.amp * cos( dot(w.dir, pos)*w.freq + t*w.phase);
}

// sharp wave functions
float evaluateWaveSharp(Wave w, float2 pos, float t, float k)
{
  return w.amp * pow(sin( dot(w.dir, pos)*w.freq + t*w.phase)* 0.5 + 0.5 , k);
}

float evaluateWaveDerivSharp(Wave w, float2 pos, float t, float k)
{
  return k*w.freq*w.amp * pow(sin( dot(w.dir, pos)*w.freq + t*w.phase)* 0.5 + 0.5 , k - 1) * cos( dot(w.dir, pos)*w.freq + t*w.phase);
}

///////////////////////////////////////////////////////////////////////////////

VtoP vertex_shader(const VS_INPUT IN)
{
	VtoP OUT;

	float4 pWorld = IN.position;

	// sum waves	
	pWorld.z = 0.0;
	float	ddx = 0.0,
			ddy = 0.0,
			fTime = vTextureOffset.x*10;

//	for( int i=0; i<NWAVES; i++ )
//	{
//    	pWorld.z += evaluateWave( wave[i], pWorld.xy, fTime );
//
//    	float deriv = evaluateWaveDeriv( wave[i], pWorld.xy, fTime );
//		ddx += deriv * wave[i].dir.x;
//		ddy += deriv * wave[i].dir.y;
//    }


	float deriv;
	deriv = wave0.freq*wave0.amp * cos( dot(wave0.dir, pWorld.xy)*wave0.freq + fTime*wave0.phase);
	ddx += deriv * wave0.dir.x;
	ddy += deriv * wave0.dir.y;

	deriv = wave1.freq*wave1.amp * cos( dot(wave1.dir, pWorld.xy)*wave1.freq + fTime*wave1.phase);
	ddx += deriv * wave1.dir.x;
	ddy += deriv * wave1.dir.y;

	// compute tangent basis
    float3 B = float3(1, ddx, 0);
    float3 T = float3(0, ddy, 1);
    float3 N = float3(-ddx, 1, -ddy);

	// compute the 3x3 tranform from tangent space to object space
	float3x3 objToTangentSpace;
	// first rows are the tangent and binormal scaled by the bump scale
	float	fBumpScale = 1.0f;
	objToTangentSpace[0] = fBumpScale * normalize(T);
	objToTangentSpace[1] = fBumpScale * normalize(B);
	objToTangentSpace[2] = normalize(N);

	// first rows are the tangent and binormal scaled by the bump scale
	// swap y and z for BBG coords
	OUT.vTanToObj1.xyz = mul(objToTangentSpace, World[0].xyz);
	OUT.vTanToObj2.xyz = mul(objToTangentSpace, World[2].xyz);
	OUT.vTanToObj3.xyz = mul(objToTangentSpace, World[1].xyz);

	//OUT.tex = IN.tex*2;
	OUT.tex = float4(IN.position.xy*0.009, 0, -4);

	float4	p = world_position( pWorld );

	OUT.position = p;
	
	OUT.vPosLocal = IN.position;

	OUT.vTexR = p;

	float4	vView = normalize(LocalEyePos - IN.position);
	float3	lightDir = normalize(LightDirVec);

	float dist = mul( pWorld, WorldView ).z;
	CalcFog(dist, dot(lightDir, vView), OUT.FogAdd.xyz, OUT.FogMod.xyz);
		
	return OUT;
}

PS_OUTPUT pixel_shader(const VtoP IN)
{
	PS_OUTPUT OUT;

	float4 diffuse	= tex2D( DIFFUSEMAP_SAMPLER, IN.tex );

	// mix two time-shifted versions of normal map
	float4	vTexN1,
			vTexN2;

	vTexN1 = IN.tex;
	vTexN2 = vTexN1;
	vTexN1.x -= vTextureOffset.x;
	vTexN2.y += vTextureOffset.y;

	float4	vN1 = (tex2Dbias( MISCMAP1_SAMPLER, vTexN1 ) * 2.0) - 1.0f;
	float4	vN2 = (tex2Dbias( MISCMAP1_SAMPLER, vTexN2 ) * 2.0) - 1.0f;
	vN1.x = vN1.w;		// for some reason the red channel is very blocky!?! so use the alpha
	vN2.x = vN2.w;
	//convert between unsigned and signed normal map data
	//float4  normal = normalize( abs(vN1) * abs(vN2) );
	float4  normal = abs(vN1) * abs(vN2);
	float4  foam = saturate(normal - 0.4);
	normal = normalize(normal);
	
	float3x3 m; // tangent to world matrix
	m[0] = IN.vTanToObj1;
	m[1] = IN.vTanToObj2;
	m[2] = IN.vTanToObj3;
	normal.xyz = normalize(mul(m, normal.xyz));

	float4	vView = normalize(LocalEyePos - IN.vPosLocal);

	float3	lightDir = normalize(LightDirVec);
	float	ndotL = dot(normal, lightDir);
	float3	reflection = 2*ndotL*normal - lightDir;
	float3	fSpec = saturate(dot(reflection, vView));
	//float3	fSpec = dot(pow(reflection,0.88), vView);

	fSpec = pow(fSpec, 30.0f)*SpecularScale;

	float4	vTexR = normalize(IN.vTexR);

	vTexR.y   = -vTexR.y;
	vTexR.xy += vTexR.w; // add "one" - texture bias
	vTexR.xy *= 0.5;

	vTexR.xy += normal.xy * 0.1;
	//vTexR.y -= 0.001;

	float4	vR = 0.2 + tex2Dproj( MISCMAP2_SAMPLER, normalize(vTexR) )*0.4;
    float	ndotV = dot(normal, vView);
    float4	waterColor = float4(0.565f,	0.594f, 0.643f, 1.0f);

	OUT.color.xyz  = diffuse * 0.5;
	OUT.color.xyz += waterColor * 0.5;
	OUT.color.xyz -= (ndotV-0.2) * 1.5;
	OUT.color.xyz *= vR;
	OUT.color.xyz += fSpec + foam.x;
	OUT.color.xyz *= IN.FogMod;
	OUT.color.xyz += IN.FogAdd;
	OUT.color.w = 1;
	
	
	//OUT.color.xyz = vN2;
//OUT.color = IN.tex;
//OUT.color = diffuse;
//OUT.color = normal;
//OUT.color = vR;
//OUT.color = float4( fSpec, 1.0f );
//OUT.color = normalize(IN.vTexR);
//OUT.color = float4( reflection, 1.0f );
//OUT.color = normalize(vView);

	return OUT;
}

technique watersea <int shader = 1;>
{
    pass p0
    {
        VertexShader = compile vs_1_1 vertex_shader();
        PixelShader  = compile ps_2_0 pixel_shader();
    }
}

///////////////////////////////////////////////////////////////////////////////

#include "ZPrePass_fx.h"

///////////////////////////////////////////////////////////////////////////////
