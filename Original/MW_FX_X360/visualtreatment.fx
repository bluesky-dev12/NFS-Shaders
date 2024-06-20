///////////////////////////////////////////////////////////////////////////////
//
// Visual Treatment
//
///////////////////////////////////////////////////////////////////////////////
#include "global.h"

// CONSTANTS

// The per-color weighting to be used for luminance	calculations in	RGB	order.
const float3	LUMINANCE_VECTOR  =	float3(0.2125f,	0.7154f, 0.0721f);

// PARAMETERS

float4 DownSampleOffset0;
float4 DownSampleOffset1;

float VisualEffectBrightness	: VISUAL_EFFECT_BRIGHTNESS;
float VisualEffectVignette		: VISUAL_EFFECT_VIGNETTE;

float Desaturation				: DESATURATION;

float	g_fVignetteScale;

// Tone	mapping	variables
float	g_fAdaptiveLumCoeff;
float	g_fBloomScale;

// Depth of Field variables
float4 DepthOfFieldParams		: DEPTHOFFIELD_PARAMS;

bool	bHDREnabled				: HDR_ENABLED;
bool	bDepthOfFieldEnabled	: DEPTHOFFIELD_ENABLED;
float4	BlurParams				: IS_MOTIONBLUR_VIGNETTED;

float4	Coeffs0					: CURVE_COEFFS_0;
float4	Coeffs1					: CURVE_COEFFS_1;
float4	Coeffs2					: CURVE_COEFFS_2;
float4	Coeffs3					: CURVE_COEFFS_3;

float	CombinedBrightness		: COMBINED_BRIGHTNESS;

///////////////////////////////////////////////////////////////////////////////

sampler	DIFFUSEMAP_SAMPLER =	sampler_state
{
	AddressU = CLAMP;
	AddressV = CLAMP;
	MIPFILTER =	NONE;
	MINFILTER =	LINEAR;
	MAGFILTER =	LINEAR;
};

sampler	MISCMAP1_SAMPLER = sampler_state
{
	AddressU = CLAMP;
	AddressV = CLAMP;
	MIPFILTER =	NONE;
	MINFILTER =	LINEAR;
	MAGFILTER =	LINEAR;
};

sampler	MISCMAP2_SAMPLER = sampler_state
{
	AddressU = CLAMP;
	AddressV = WRAP;		// Use mirror for split screen so the vignette works
	MIPFILTER =	NONE;
	MINFILTER =	LINEAR;
	MAGFILTER =	LINEAR;
};

sampler	MISCMAP3_SAMPLER = sampler_state
{
	AddressU = CLAMP;
	AddressV = CLAMP;
	MIPFILTER =	NONE;
	MINFILTER =	LINEAR;
	MAGFILTER =	LINEAR;
};

sampler	MISCMAP4_SAMPLER;
sampler	HEIGHTMAP_SAMPLER;

///////////////////////////////////////////////////////////////////////////////

// should pack these two, reduce input bandwidth.   may not be significant
struct VS_INPUT_SCREEN
{
	float4 position	: POSITION;
	float4 tex0		: TEXCOORD0;
	float4 tex1		: TEXCOORD1;
	float4 tex2		: TEXCOORD2;
	float4 tex3		: TEXCOORD3;
	float4 tex4		: TEXCOORD4;
	float4 tex5		: TEXCOORD5;
	float4 tex6		: TEXCOORD6;
	float4 tex7		: TEXCOORD7;
};

struct VtoP
{
	float4 position	: POSITION;
	float4 tex01		: TEXCOORD0;
	float4 tex23		: TEXCOORD1;
	float4 tex45		: TEXCOORD2;
	float4 tex67		: TEXCOORD3;
};

VtoP vertex_shader_passthru(const VS_INPUT_SCREEN IN)
{
	VtoP OUT;
	OUT.position = IN.position;
	OUT.tex01.xy	= IN.tex0.xy;
	OUT.tex01.zw	= IN.tex1.xy;
	OUT.tex23.xy	= IN.tex2.xy;
	OUT.tex23.zw	= IN.tex3.xy;
	OUT.tex45.xy	= IN.tex4.xy;
	OUT.tex45.zw	= IN.tex5.xy;
	OUT.tex67.xy	= IN.tex6.xy;
	OUT.tex67.zw	= IN.tex7.xy;

	return OUT;
}

float4 PS_DownScale4x4AlphaLuminance(	in float2 vScreenPosition :	TEXCOORD0 ) : COLOR
{
    // exploit bilinear interpolation mode to get 16 samples using only 
    // 4 texture lookup instructions (same bandwidth usage as previous)
    // note: offsets should have only four unique values, really only
    // need one parameter
	float4 result;
    float4 uv0 = vScreenPosition.xyxy + DownSampleOffset0;
    float4 uv1 = vScreenPosition.xyxy + DownSampleOffset1;
	result = tex2D( DIFFUSEMAP_SAMPLER, uv0.xy )
	       + tex2D( DIFFUSEMAP_SAMPLER, uv0.zw )
	       + tex2D( DIFFUSEMAP_SAMPLER, uv1.xy )
	       + tex2D( DIFFUSEMAP_SAMPLER, uv1.zw );
		
	// Store the luminance in alpha, scale all components 
	result.w = dot( result.xyz, LUMINANCE_VECTOR );
    result *= 0.25f;

	return result;
}

float4 PS_VisualTreatment(const VtoP IN) : COLOR 
{
	float4	vignette  = tex2D( MISCMAP2_SAMPLER,  float2( IN.tex01.x, IN.tex01.y*g_fVignetteScale ) );
	float   depth	  = tex2D( HEIGHTMAP_SAMPLER, IN.tex01.xy ).x;
	float	zDist	  = (1 / (1-depth));
	float4	result;

	// compute motion blurred image
	float4 screenTex0 = tex2D( DIFFUSEMAP_SAMPLER, IN.tex01.xy );
	float3 screenTex1 = tex2D( DIFFUSEMAP_SAMPLER, IN.tex01.zw );
	float3 screenTex2 = tex2D( DIFFUSEMAP_SAMPLER, IN.tex23.xy );
	float3 screenTex3 = tex2D( DIFFUSEMAP_SAMPLER, IN.tex23.zw );
	float3 screenTex4 = tex2D( DIFFUSEMAP_SAMPLER, IN.tex45.xy );
	float3 screenTex5 = tex2D( DIFFUSEMAP_SAMPLER, IN.tex45.zw );
	float3 screenTex6 = tex2D( DIFFUSEMAP_SAMPLER, IN.tex67.xy );
	float3 screenTex7 = tex2D( DIFFUSEMAP_SAMPLER, IN.tex67.zw );
	const float kBlurRatio = 0;
	const float kBlend = 1.0 / (16.0 + kBlurRatio);
	float3 radialBlur = screenTex0.xyz*(kBlend*3.0f)  
                      + screenTex1*(kBlend*3.0f) 
                      + screenTex2*(kBlend*2.0f) 
                      + screenTex3*(kBlend*2.0f) 
                      + screenTex4*(kBlend*2.0f)  
                      + screenTex5*(kBlend*1.5f) 
                      + screenTex6*(kBlend*1.5f)  
                      + screenTex7*(kBlend*1.0f);

	// mask motion blurred image with vignette and radial blur
	float blurDepth = saturate(-zDist/300+1.2);	
    float motionBlurMask = (vignette.x+BlurParams.x) * blurDepth;
    float radialBlurMask = vignette.w * BlurParams.y;
	result.xyz = lerp(screenTex0.xyz, radialBlur, saturate(motionBlurMask + radialBlurMask));

	// result	= DoVisualTreatment(IN, result, vignette);
	float4 scaledTex = tex2D( MISCMAP1_SAMPLER, IN.tex01.xy );
	
	// Get the luminance from the full screen image
	float luminance = dot( result.xyz, LUMINANCE_VECTOR ); 

    // compute the curves 
	float4 curve = Coeffs3*scaledTex.wwww + Coeffs2; 
	curve = curve*scaledTex.wwww + Coeffs1;                  
	curve = curve*scaledTex.wwww + Coeffs0;                 

	// Desaturate the original image by blending between the screen and the luminance
	float3 desatScreen = luminance.xxx + Desaturation * (result.xyz - luminance.xxx);

	// Black Bloom screen
    float3 bb_result = desatScreen * curve.x;

	// Add screen result to colour bloom 
	result.xyz = bb_result + curve.yzw * result.xyz;
	
	// Pursuit Breaker Vignette Effect
	result.xyz += vignette.y * VisualEffectVignette;
	
	// Vignette and brightness masking
	result.xyz *= vignette.z * CombinedBrightness;
	
	// result	= DoHDR( IN, result );
	float3 bloom = tex2D( MISCMAP3_SAMPLER, IN.tex01.xy );
	result.xyz += bloom * g_fBloomScale;		// add bloom
	
	result.w = screenTex0.w;

	return result;
}

float4 PS_VisualTreatment_Branching(const VtoP IN) : COLOR 
{
	float4	vignette  = tex2D( MISCMAP2_SAMPLER,  float2( IN.tex01.x, IN.tex01.y*g_fVignetteScale ) );
	float   depth	  = tex2D( HEIGHTMAP_SAMPLER, IN.tex01.xy ).x;
	float	zDist	  = (1 / (1-depth));
	float4	result;

	// compute motion blurred image
	float4 screenTex0 = tex2D( DIFFUSEMAP_SAMPLER, IN.tex01.xy );
	float3 screenTex1 = tex2D( DIFFUSEMAP_SAMPLER, IN.tex01.zw );
	float3 screenTex2 = tex2D( DIFFUSEMAP_SAMPLER, IN.tex23.xy );
	float3 screenTex3 = tex2D( DIFFUSEMAP_SAMPLER, IN.tex23.zw );
	float3 screenTex4 = tex2D( DIFFUSEMAP_SAMPLER, IN.tex45.xy );
	float3 screenTex5 = tex2D( DIFFUSEMAP_SAMPLER, IN.tex45.zw );
	float3 screenTex6 = tex2D( DIFFUSEMAP_SAMPLER, IN.tex67.xy );
	float3 screenTex7 = tex2D( DIFFUSEMAP_SAMPLER, IN.tex67.zw );
	const float kBlurRatio = 0;
	const float kBlend = 1.0 / (16.0 + kBlurRatio);
	float3 radialBlur = screenTex0.xyz*(kBlend*3.0f)  
                      + screenTex1*(kBlend*3.0f) 
                      + screenTex2*(kBlend*2.0f) 
                      + screenTex3*(kBlend*2.0f) 
                      + screenTex4*(kBlend*2.0f)  
                      + screenTex5*(kBlend*1.5f) 
                      + screenTex6*(kBlend*1.5f)  
                      + screenTex7*(kBlend*1.0f);

	// mask motion blurred image with vignette and radial blur
	float blurDepth = saturate(-zDist/300+1.2);	
    float motionBlurMask = saturate(vignette.x+BlurParams.x) * blurDepth;
    float radialBlurMask = vignette.w * BlurParams.y;
	result.xyz = lerp(screenTex0.xyz, radialBlur, motionBlurMask + radialBlurMask);

	if( bDepthOfFieldEnabled )
	{
		// result = DoDepthOfField(IN, result, zDist);
	    float focalDist		= DepthOfFieldParams.x;
	    float depthOfField	= DepthOfFieldParams.y;
	    float scale			= DepthOfFieldParams.z;
	    float blur			= saturate(scale*(abs(zDist-focalDist)-depthOfField));

	    float3 scaledTex	= tex2D( MISCMAP4_SAMPLER,  IN.tex01.xy );
	    result.xyz = lerp(result.xyz, scaledTex, blur);
	}

	// result	= DoVisualTreatment(IN, result, vignette);
	float4 scaledTex = tex2D( MISCMAP1_SAMPLER, IN.tex01.xy );
	
	// Get the luminance from the full screen image
	float luminance = dot( result.xyz, LUMINANCE_VECTOR ); 

    // compute the curves 
	float4 curve = Coeffs3*scaledTex.wwww + Coeffs2; 
	curve = curve*scaledTex.wwww + Coeffs1;                  
	curve = curve*scaledTex.wwww + Coeffs0;                 

	// Desaturate the original image by blending between the screen and the luminance
	float3 desatScreen = lerp(luminance, result.xyz, Desaturation);

	// Black Bloom screen
    float3 bb_result = desatScreen * curve.x;

	// Add screen result to colour bloom
	result.xyz = bb_result + curve.yzw * result.xyz;
	
	// Pursuit Breaker Vignette Effect
	result.xyz += vignette.y * VisualEffectVignette;
	
	// Pulse Brightness Effect (cannot use CombinedBrightness here)
	result.xyz *= VisualEffectBrightness;
	
	// Normal vignette that darkens the edges
	result.xyz *= vignette.z;

	result.w = screenTex0.w;
	
	if( bHDREnabled )	
	{
	    // result = DoHDR( IN, result );
	    float3 bloom = tex2D( MISCMAP3_SAMPLER, IN.tex01.xy );
	    result.xyz *= g_fAdaptiveLumCoeff;	
	    result.xyz += bloom * g_fBloomScale;		// add bloom
    }

	return result;
}

///////////////////////////////////////////////////////////////////////////////

technique downscale4x4alphaluminance <int	shader = 1;>
{
	pass p0
	{
		VertexShader = compile vs_1_1 vertex_shader_passthru();
		PixelShader	 = compile ps_2_0 PS_DownScale4x4AlphaLuminance();
	}
}

///////////////////////////////////////////////////////////////////////////////

technique visualtreatment
{
	pass p0
	{
		VertexShader = compile vs_1_1 vertex_shader_passthru();
		PixelShader	 = compile ps_3_0 PS_VisualTreatment();
	}
}

technique visualtreatment_branching
{
	pass p0
	{
		VertexShader = compile vs_1_1 vertex_shader_passthru();
		PixelShader	 = compile ps_3_0 PS_VisualTreatment_Branching();
	}
}

///////////////////////////////////////////////////////////////////////////////
