///////////////////////////////////////////////////////////////////////////////
//
// HDR Effects
//
///////////////////////////////////////////////////////////////////////////////

float4x4 WorldViewProj : WORLDVIEWPROJECTION ;
shared float4 TextureOffset   : TEXTUREANIMOFFSET;

static const int	MAX_SAMPLES			   = 16;	// Maximum texture grabs
const float			BRIGHT_PASS_OFFSET	   = 10.0f;	// Offset for BrightPass filter

// The per-color weighting to be used for luminance	calculations in	RGB	order.
const float3	LUMINANCE_VECTOR  =	float3(0.2125f,	0.7154f, 0.0721f);

// Contains	sampling offsets used by the techniques
shared float4	g_avSampleOffsets[MAX_SAMPLES];// : register(c0);
shared float4	g_avSampleWeights[MAX_SAMPLES];// : register(c16);

// Tone	mapping	variables
float	g_fMiddleGray;			//	The	middle gray	key	value
float	g_fElapsedTime;			//	Time in	seconds	since the last calculation
float	g_fBloomScale;			// Bloom process multiplier
float	g_fAdaptedLum;
float	g_fBrightPassThreshold;	// Threshold for BrightPass	filter

float2 TexelOffsets[MAX_SAMPLES];

float BlackBloomIntensity	= 0.58f;
float ColourBloomIntensity	= 0.15f;
float DetailMapIntensity	= 1.0f;
float VisualLookBrightness	= 0.0f;
float VisualLookRadialBlur	= 1.0f;
float RadialBlurOffset		= 0.1f;
float4x4 BlackBloomCurve;
float4x4 ColourBloomCurve;
float4x4 DetailMapCurve;
float4	ColourBloomTint = float4(0.517, 0.80, 0.90, 1);
float Desaturation	= 1.0f;

float YUV_ratio = 0.0f;

///////////////////////////////////////////////////////////////////////////////

sampler	DIFFUSEMAP_SAMPLER = sampler_state
{
	AddressU = CLAMP;
	AddressV = CLAMP;
	MIPFILTER =	LINEAR;
	MINFILTER =	LINEAR;
	MAGFILTER =	LINEAR;
};

sampler	MISCMAP1_SAMPLER = sampler_state
{
	AddressU = CLAMP;
	AddressV = CLAMP;
	MIPFILTER =	LINEAR;
	MINFILTER =	LINEAR;
	MAGFILTER =	LINEAR;
};

sampler	MISCMAP2_SAMPLER = sampler_state
{
	AddressU = CLAMP;
	AddressV = CLAMP;
	MIPFILTER =	LINEAR;
	MINFILTER =	LINEAR;
	MAGFILTER =	LINEAR;
};

///////////////////////////////////////////////////////////////////////////////

struct VS_INPUT_WORLD
{
	float4 position : POSITION;
	float4 color    : COLOR;
	float4 texcoord : TEXCOORD;
};

struct VS_INPUT_SCREEN
{
	float4 position	: POSITION;
	float4 texcoord	: TEXCOORD;
};

struct VtoP
{
	float4 position	: POSITION;
	float4 color	: COLOR0;
	float4 tex		: TEXCOORD0;
};

///////////////////////////////////////////////////////////////////////////////

VtoP vertex_shader_worldviewproj(const VS_INPUT_WORLD IN)
{
	VtoP OUT;
	float4 p = mul(IN.position, WorldViewProj);
	OUT.position = p;
	OUT.tex = IN.texcoord + TextureOffset;
	OUT.color = IN.color;

	return OUT;
}

///////////////////////////////////////////////////////////////////////////////

VtoP vertex_shader_passthru(const VS_INPUT_SCREEN IN)
{
	VtoP OUT;
	OUT.position = IN.position;
	OUT.tex	= IN.texcoord;
	OUT.color =	0x77777777;

	return OUT;
}

///////////////////////////////////////////////////////////////////////////////
 
float4 pixel_shader_yuvmovie(const VtoP IN) : COLOR
{
    // U,V in range [-0.5,0.5]
    float3x3 yuvToRgbMatrix = {	1.164383,         0, +1.596027,	
								1.164383, -0.391762, -0.812968,
								1.164383, +2.017232,         0 };
 
	float3 yuv;
	float2 tex1 = float2(IN.tex.x * YUV_ratio, IN.tex.y);
	yuv.r = tex2D(DIFFUSEMAP_SAMPLER, IN.tex)-(16/256);
    yuv.g = tex2D(MISCMAP1_SAMPLER, tex1)-0.5;
    yuv.b = tex2D(MISCMAP2_SAMPLER, tex1)-0.5;

    float4 OUT;
    OUT.rgb = mul(yuvToRgbMatrix, yuv);
    OUT.a = 0;

	return OUT;
}

///////////////////////////////////////////////////////////////////////////////

float4 pixel_shader(const VtoP IN) : COLOR
{
	float4 OUT;

	float4 diffuse = tex2D(DIFFUSEMAP_SAMPLER, IN.tex);	// * IN;
	
	OUT.xyz	= diffuse;

	OUT.w =	diffuse.w;

	return OUT;
}

///////////////////////////////////////////////////////////////////////////////

float4 pixel_shader_masked( in float2 vScreenPosition :	TEXCOORD0 ) : COLOR
{
	float4	fZero         = 0.0f,
			fMask         = tex2D( DIFFUSEMAP_SAMPLER, vScreenPosition ),
			fSample       = tex2D( MISCMAP1_SAMPLER, vScreenPosition ),
			fMaskedSample = fMask * fSample;

//	if ( ((fMaskedSample.x != 0.0f) && (fSample.x != 0.0f)) &&
//		 ((fMaskedSample.y != 0.0f) && (fSample.y != 0.0f)) &&
//		 ((fMaskedSample.z != 0.0f) && (fSample.z != 0.0f))    )
//	{
//		return float4( 0.0f, 0.0f, 0.0f, 1.0f );
//	}
//	else
//	{
//		return fSample;
//	}
	
	return fMaskedSample;
}


///////////////////////////////////////////////////////////////////////////////
// Name: DownScale2x2PS
// Desc: Scale the source texture down to 1/4 scale
///////////////////////////////////////////////////////////////////////////////

float4 PS_DownScale2x2(	in float2 vScreenPosition :	TEXCOORD0 )	: COLOR
{
	float4 sample =	0.0f;

	for( int i=0; i	< 4; i++ )
	{
		sample += tex2D( DIFFUSEMAP_SAMPLER,	vScreenPosition	+ g_avSampleOffsets[i].xy );
	}
	
	return sample /	4;
}

///////////////////////////////////////////////////////////////////////////////

float4 PS_PassThruAlphaTag( const VtoP IN ) : COLOR
{
	float4	vDiffuse = tex2D(DIFFUSEMAP_SAMPLER, IN.tex);

	// save alpha tag
	float	fAlphaTag = vDiffuse.w;

	// get average luminance in alpha 
	vDiffuse.w = dot( vDiffuse.xyz, LUMINANCE_VECTOR );

	// filter sample colour by alpha tag
	vDiffuse.xyz *= fAlphaTag;

	return vDiffuse;	
}

///////////////////////////////////////////////////////////////////////////////
// Name: PS_DownScale4x4
// Desc: Scale the source texture down to 1/16 scale
///////////////////////////////////////////////////////////////////////////////

struct PS_OUT
{
	float4 scaledColour		: COLOR0;	// render target 0
	float4 scaledHDRColour	: COLOR1;	// render target 1
};

PS_OUT PS_DownScale4x4ToUvesHdr(in float2 vScreenPosition :	TEXCOORD0 )
{
	PS_OUT result;
	
	result.scaledColour = 0.0f;

	float motionBlurMask = 0;
	for( int i=0; i	< 16; i++ )
	{	
		result.scaledColour += tex2D( DIFFUSEMAP_SAMPLER, vScreenPosition + g_avSampleOffsets[i].xy );
	}
		
	result.scaledHDRColour = result.scaledColour;
	
	// Store the scaled luminance in alpha and a motion blur mask in the red channel
	//result.scaledColour.r = result.scaledColour.w;
	result.scaledColour.w = dot( result.scaledColour.xyz, LUMINANCE_VECTOR );
	result.scaledColour /= 16;
	// For the motion blur mask, only want motion blur where there is absolute zero
	//result.scaledColour.r = 1 - result.scaledColour.r*10;
	//result.scaledColour.r = result.scaledColour.r > 0.4 ? 0 : result.scaledColour.r;
	
	//result.scaledColour.r = motionBlurMask / 16;
	//result.scaledColour.r = 1 - result.scaledColour.r*10;
	
	// The source alpha is a mask for the HDR bloom - the mask is inverted i.e. bloom the black 
	float	fAlphaMask = 1 - result.scaledHDRColour.w / 16;
	// filter sample colour by alpha mask
	result.scaledHDRColour.xyz *= fAlphaMask;
	result.scaledHDRColour /= 16;
	
	return result;
}


float4 PS_DownScale4x4(	in float2 vScreenPosition :	TEXCOORD0 ) : COLOR
{
	float4 result;
	
	result = 0.0f;

	for( int i=0; i	< 16; i++ )
	{
		result += tex2D( DIFFUSEMAP_SAMPLER, vScreenPosition + g_avSampleOffsets[i].xy );
	}
		
	// Store the scaled luminance in alpha 
	result.w = dot( result.xyz, LUMINANCE_VECTOR );
	result /= 16;

	return result;
}

///////////////////////////////////////////////////////////////////////////////

float4 PS_GaussBlur5x5(	const VtoP IN )	: COLOR
{
	float4	sample = 0.0f;

	for( int i=0; i	< 13; i++ )
	{
		sample += g_avSampleWeights[i] * tex2D(	DIFFUSEMAP_SAMPLER, IN.tex.xy + g_avSampleOffsets[i].xy );
	}

	return sample;
}

///////////////////////////////////////////////////////////////////////////////

float4 PS_Bloom( const VtoP	IN ) : COLOR
{
	float4 sample;

	sample = 0.0f;

	for( int i=0; i	< 16; i++ )
	{
		sample += g_avSampleWeights[i] * tex2D(	DIFFUSEMAP_SAMPLER, IN.tex.xy + g_avSampleOffsets[i].xy );
	}
	
	return sample;
}

///////////////////////////////////////////////////////////////////////////////

static const float fWhiteCutoff	= 0.8f;

///////////////////////////////////////////////////////////////////////////////

float4 PS_BrightPassFilter(	const VtoP IN )	: COLOR
{
	float4	vSample = tex2D( DIFFUSEMAP_SAMPLER, IN.tex );

	float3	ColorOut;

	ColorOut = vSample.xyz;

	ColorOut *= g_fMiddleGray/(g_fAdaptedLum + 0.001f);

	// Subtract out dark pixels
	ColorOut -= g_fBrightPassThreshold;

	// Clamp to 0
	ColorOut = max(ColorOut, 0.0f);

	// Map the resulting value into the 0 to 1 range. Higher values for
	// BRIGHT_PASS_OFFSET will isolate lights from illuminated scene 
	// objects.
//	ColorOut /= (BRIGHT_PASS_OFFSET+ColorOut); 

	return float4( ColorOut, vSample.a );
}

///////////////////////////////////////////////////////////////////////////////
// Name: PS_SampleLuminance
// Desc: Sample	the	luminance of the source	image using	a kernal of	sample
//		 points, and return	a scaled image containing the log()	of averages
///////////////////////////////////////////////////////////////////////////////

float4 PS_SampleLuminance(	in float2 vScreenPosition :	TEXCOORD0 )	: COLOR
{
	float fLogLumSum = 0.0f;

	for( int iSample = 0; iSample <	9; iSample++ )
	{
		// Compute the sum of log(luminance) throughout	the	sample points
		float4 vColor	  =	tex2D( DIFFUSEMAP_SAMPLER, vScreenPosition + g_avSampleOffsets[iSample].xy );
		fLogLumSum += vColor.w;
//		fLogLumSum += log( fLuminance +	0.0001f	);
	}
	
	// Divide the sum to complete the average
	fLogLumSum /= 9;

	return float4( fLogLumSum, fLogLumSum, fLogLumSum, 1.0f	);
}

///////////////////////////////////////////////////////////////////////////////

float4 PS_FinalHDRPass(	const VtoP IN )	: COLOR
{
	float4	vSample		= tex2D( DIFFUSEMAP_SAMPLER, IN.tex),
			vBloom		= tex2D( MISCMAP1_SAMPLER,	 IN.tex );
	float	fAdaptedLum = tex2D( MISCMAP2_SAMPLER, float2((0.5f), (0.5f)) );

	float4 result;
	result.rgb = vSample.rgb *  2.0f * g_fMiddleGray/(g_fAdaptedLum + 0.001f);

	result.rgb += vBloom * g_fBloomScale;
	result.a = vSample.a;
	
	return result;
}

///////////////////////////////////////////////////////////////////////////////

technique finalhdrpass <int	shader = 1;>
{
	pass p0
	{
		VertexShader = compile vs_1_1 vertex_shader_passthru();
		PixelShader	 = compile ps_2_0 PS_FinalHDRPass();
	}
}

///////////////////////////////////////////////////////////////////////////////

technique world_masked	<int shader	= 1;>
{
	pass p0
	{
		VertexShader = compile vs_1_1 vertex_shader_worldviewproj();
		PixelShader	 = compile ps_2_0 pixel_shader_masked();
	}
}

///////////////////////////////////////////////////////////////////////////////

technique screen_passthru <int shader	= 1;>
{
	pass p0
	{
		VertexShader = compile vs_1_1 vertex_shader_passthru();
		PixelShader	 = compile ps_2_0 pixel_shader();
	}
}

///////////////////////////////////////////////////////////////////////////////

technique yuvmovie <int shader	= 1;>
{
	pass p0
	{
		VertexShader = compile vs_1_1 vertex_shader_passthru();
		PixelShader	 = compile ps_2_0 pixel_shader_yuvmovie();
	}
}
///////////////////////////////////////////////////////////////////////////////

technique screen_passthru_alpha_tag <int shader	= 1;>
{
	pass p0
	{
		VertexShader = compile vs_1_1 vertex_shader_passthru();
		PixelShader	 = compile ps_2_0 PS_PassThruAlphaTag();
	}
}

///////////////////////////////////////////////////////////////////////////////

technique downscale2x2 <int	shader = 1;>
{
	pass p0
	{
		VertexShader = compile vs_1_1 vertex_shader_passthru();
		PixelShader	 = compile ps_2_0 PS_DownScale2x2();
	}
}

///////////////////////////////////////////////////////////////////////////////

technique downscale4x4 <int	shader = 1;>
{
	pass p0
	{
		VertexShader = compile vs_1_1 vertex_shader_passthru();
		PixelShader	 = compile ps_2_0 PS_DownScale4x4();
	}
}

technique downscale4x4_t0_uves_hdr <int	shader = 1;>
{
	pass p0
	{
		VertexShader = compile vs_1_1 vertex_shader_passthru();
		PixelShader	 = compile ps_2_0 PS_DownScale4x4ToUvesHdr();
	}
}

///////////////////////////////////////////////////////////////////////////////

technique bloom	<int shader	= 1;>
{
	pass p0
	{
		VertexShader = compile vs_1_1 vertex_shader_passthru();
		PixelShader	 = compile ps_2_0 PS_Bloom();
	}
}

///////////////////////////////////////////////////////////////////////////////

technique blur	<int shader	= 1;>
{
	pass p0
	{
		VertexShader = compile vs_1_1 vertex_shader_passthru();
		PixelShader	 = compile ps_2_0 PS_GaussBlur5x5();
	}
}

///////////////////////////////////////////////////////////////////////////////

technique brightpass <int shader = 1;>
{
	pass p0
	{
		VertexShader = compile vs_1_1 vertex_shader_passthru();
		PixelShader	 = compile ps_2_0 PS_BrightPassFilter();
	}
}

///////////////////////////////////////////////////////////////////////////////

technique calculate_luminance <int shader =	1;>
{
	pass p0
	{
		VertexShader = compile vs_1_1 vertex_shader_passthru();
		PixelShader	 = compile ps_2_0 PS_SampleLuminance();
	}
}

///////////////////////////////////////////////////////////////////////////////
