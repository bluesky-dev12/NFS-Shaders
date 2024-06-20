/////////////////////////////////////////////////////////////////////////////////////////

const float	SHADOW_EPSILON	= 0.00005f;

/////////////////////////////////////////////////////////////////////////////////////////

sampler SHADOWMAP_SAMPLER = sampler_state
{
	BorderColor = 0xFFFFFFFF;
	AddressU    = BORDER;
	AddressV    = BORDER;
	MIPFILTER   = LINEAR;
	MINFILTER   = LINEAR;
	MAGFILTER   = LINEAR;
};

/*sampler1D SHADOWMAPLOD_SAMPLER = sampler_state
{
	BorderColor = 0;
	MIPFILTER = LINEAR;
	MINFILTER = LINEAR;
	MAGFILTER = LINEAR;
	AddressU = BORDER;
	AddressV = BORDER;
};*/

/////////////////////////////////////////////////////////////////////////////////////////

struct VtoP_Light
{
	float4 position		: POSITION;
	float4 diffuseTex	: TEXCOORD0;
	float2 dist			: TEXCOORD1;
};

/////////////////////////////////////////////////////////////////////////////////////////

// shadow viewproj matrix array
float4x4	matShadowMapWVP					: SHADOWMAP_WVPMATRIX;
float		g_fShadowMapAlphaMin			: SHADOWMAP_ALPHAMIN;

float4x4	g_matWorld						: WORLD;				// world matrix

float		g_fShadowMapBias				: SHADOWMAP_BIAS;
float		g_fShadowMapScaleX				: SHADOWMAP_SCALE_X;
float		g_fShadowMapScaleY				: SHADOWMAP_SCALE_Y;
int			g_iShadowMapEnabled				: SHADOWMAP_ENABLED;
int			g_bShadowMapAlphaEnabled		: SHADOWMAP_ALPHA_ENABLED;
int			g_iShadowMapPCFLevel			: SHADOWMAP_PCF_LEVEL;
float4		AmbientColour					: AMBIENTCOLOUR;
float		g_fLodDistance					: SHADOWMAP_LOD_DISTANCE;
float		g_fDiffuseMapWidth				: DIFFUSEMAP_WIDTH;
float		g_fDiffuseMapHeight				: DIFFUSEMAP_HEIGHT;

//float    g_fCosTheta;							// Cosine of theta of the spot light

/////////////////////////////////////////////////////////////////////////////////////////

float4 vertex_shadow_tex( const float4 vPosition )
{
	return mul( vPosition, matShadowMapWVP );
}

/////////////////////////////////////////////////////////////////////////////////////////

float4 vertex_shadow_pos_view( const float4 vPosition )
{
	// Transform position to view space
	return mul( vPosition, WorldView );
}

/////////////////////////////////////////////////////////////////////////////////////////

float2 GetShadowMapTexCoord( const float4 sTex )
{
	float2	ShadowTexC = (0.5 * sTex.xy / sTex.w) + 0.5f;

	ShadowTexC.y = 1.0f - ShadowTexC.y;

	return ShadowTexC;
}

/////////////////////////////////////////////////////////////////////////////////////////
const float kShadowMapFallOff = 0.85f;
float GetDistantWeight(float dist)
{
	// Use linear equation y=mx+c where m=1/(kShadowMapFallOff-1) and c = -m to get the
	// correct falloff from 1 to 0 between kShadowMapFallOff and 1
	float m = 1.0f / (kShadowMapFallOff-1);
	float c = -m;
	return saturate(dist*m + c);
	//return tex1D( SHADOWMAPLOD_SAMPLER, dist).r;
}

/////////////////////////////////////////////////////////////////////////////////////////

float GetDepthSample( const float4 sTex )
{
	float	fV,
			fD    = tex2D( SHADOWMAP_SAMPLER, GetShadowMapTexCoord( sTex ) ).x,
			fDTex = sTex.z / sTex.w; 

	fV = step( fDTex + g_fShadowMapBias, fD );

	return fV;
}

/////////////////////////////////////////////////////////////////////////////////////////

//float DoShadowPCFDepth9( const float4 sTex )
//{
	//float	x,
			//y,
			//sum = 0;
//
//	for (y = -1.0; y <= 1.0; y+= 1.0f)
//	{
//		float	fY = y * g_fShadowMapScaleY;
//
//		for (x = -1.0; x <= 1.0; x+= 1.0f)
//		{
//			float	fX = x * g_fShadowMapScaleX;
//
//			sum += GetDepthSample( sTex + float4(fX, fY, 0.0f, 0.0f) );
//		}
//	}
//
//	sum /= 4.0f;
//
//	return sum;
//}

/////////////////////////////////////////////////////////////////////////////////////////

//float DoShadowPCFDepth16( const float4 sTex )
//{
//	float	x,
//			y,
//			sum = 0;
//
//	for (y = -1.5; y <= 1.5; y+= 1.0f)
//	{
//		float	fY = y * g_fShadowMapScaleY;
//
//		for (x = -1.5; x <= 1.5; x+= 1.0f)
//		{
//			float	fX = x * g_fShadowMapScaleX;
//
//			sum += GetDepthSample( sTex + float4(fX, fY, 0.0f, 0.0f) );
//		}
//	}
//
//	sum /= 16.0f;
//
//	return sum;
//}

/////////////////////////////////////////////////////////////////////////////////////////

float4 tex2DOffset( sampler2D ss, float2 uv, float2 offset )
{
	float4 result;
	float offsetX = offset.x;
	float offsetY = offset.y;
	asm {
		tfetch2D result, uv, ss, OffsetX=offsetX, OffsetY=offsetY
	};
	return result;
}

/////////////////////////////////////////////////////////////////////////////////////////

float DoShadowPCFDepth9( const float4 sTex, const float NdotL )
{
    float2 shadowLookupUV = GetShadowMapTexCoord( sTex );

	float4 firstGroup = 0;
	firstGroup.x = tex2DOffset( SHADOWMAP_SAMPLER, shadowLookupUV, float2( -0.5, -0.5 ) ).r; 
	firstGroup.y = tex2DOffset( SHADOWMAP_SAMPLER, shadowLookupUV, float2( -0.5,  0 ) ).r; 
	firstGroup.z = tex2DOffset( SHADOWMAP_SAMPLER, shadowLookupUV, float2( -0.5,  0.5 ) ).r; 
	firstGroup.w = tex2DOffset( SHADOWMAP_SAMPLER, shadowLookupUV, float2(  0, -0.5 ) ).r; 
	float4 secondGroup = 0;
	secondGroup.x = tex2DOffset( SHADOWMAP_SAMPLER, shadowLookupUV, float2(  0,  0 ) ).r; 
	secondGroup.y = tex2DOffset( SHADOWMAP_SAMPLER, shadowLookupUV, float2(  0,  0.5 ) ).r; 
	secondGroup.z = tex2DOffset( SHADOWMAP_SAMPLER, shadowLookupUV, float2(  0.5, -0.5 ) ).r; 
	secondGroup.w = tex2DOffset( SHADOWMAP_SAMPLER, shadowLookupUV, float2(  0.5,  0 ) ).r; 
	float thirdGroup = 0;
	thirdGroup =    tex2DOffset( SHADOWMAP_SAMPLER, shadowLookupUV, float2(  0.5,  0.5 ) ).r; 

	float fDTexBiased = ( sTex.z / sTex.w ) + (g_fShadowMapBias*NdotL);
	firstGroup = step( fDTexBiased, firstGroup );
	secondGroup = step( fDTexBiased, secondGroup );
	thirdGroup = step( fDTexBiased, thirdGroup );

	float sum = dot( firstGroup, firstGroup ) + dot( secondGroup, secondGroup ) + thirdGroup;
	sum /= 9.0;
		
	return sum;
/*

	float	sum = 0;

	float	fX1 = -1.0 * g_fShadowMapScaleX,
			fX2 =  0.0,
			fX3 =  1.0 * g_fShadowMapScaleX,
			fY1 = -1.0 * g_fShadowMapScaleY,
			fY2 =  0.0,
			fY3 =  1.0 * g_fShadowMapScaleY;

	sum += GetDepthSample( sTex + float4(fX1, fY1, 0.0f, 0.0f) );
	sum += GetDepthSample( sTex + float4(fX1, fY2, 0.0f, 0.0f) );
	sum += GetDepthSample( sTex + float4(fX1, fY3, 0.0f, 0.0f) );

	sum += GetDepthSample( sTex + float4(fX2, fY1, 0.0f, 0.0f) );
	sum += GetDepthSample( sTex + float4(fX2, fY2, 0.0f, 0.0f) );
	sum += GetDepthSample( sTex + float4(fX2, fY3, 0.0f, 0.0f) );

	sum += GetDepthSample( sTex + float4(fX3, fY1, 0.0f, 0.0f) );
	sum += GetDepthSample( sTex + float4(fX3, fY2, 0.0f, 0.0f) );
	sum += GetDepthSample( sTex + float4(fX3, fY3, 0.0f, 0.0f) );

	sum /= 9.0f;
	
	return sum;
*/
}

/////////////////////////////////////////////////////////////////////////////////////////

float DoShadowPCFDepth16( const float4 sTex )
{
	float	sum = 0;

	float	fX1 = -1.5 * g_fShadowMapScaleX,
			fX2 = -0.5 * g_fShadowMapScaleX,
			fX3 =  0.5 * g_fShadowMapScaleX,
			fX4 =  1.5 * g_fShadowMapScaleX,
			fY1 = -1.5 * g_fShadowMapScaleY,
			fY2 = -0.5 * g_fShadowMapScaleY,
			fY3 =  0.5 * g_fShadowMapScaleY,
			fY4 =  1.5 * g_fShadowMapScaleY;

	sum += GetDepthSample( sTex + float4(fX1, fY1, 0.0f, 0.0f) );
	sum += GetDepthSample( sTex + float4(fX1, fY2, 0.0f, 0.0f) );
	sum += GetDepthSample( sTex + float4(fX1, fY3, 0.0f, 0.0f) );
	sum += GetDepthSample( sTex + float4(fX1, fY4, 0.0f, 0.0f) );

	sum += GetDepthSample( sTex + float4(fX2, fY1, 0.0f, 0.0f) );
	sum += GetDepthSample( sTex + float4(fX2, fY2, 0.0f, 0.0f) );
	sum += GetDepthSample( sTex + float4(fX2, fY3, 0.0f, 0.0f) );
	sum += GetDepthSample( sTex + float4(fX2, fY4, 0.0f, 0.0f) );

	sum += GetDepthSample( sTex + float4(fX3, fY1, 0.0f, 0.0f) );
	sum += GetDepthSample( sTex + float4(fX3, fY2, 0.0f, 0.0f) );
	sum += GetDepthSample( sTex + float4(fX3, fY3, 0.0f, 0.0f) );
	sum += GetDepthSample( sTex + float4(fX3, fY4, 0.0f, 0.0f) );

	sum += GetDepthSample( sTex + float4(fX4, fY1, 0.0f, 0.0f) );
	sum += GetDepthSample( sTex + float4(fX4, fY2, 0.0f, 0.0f) );
	sum += GetDepthSample( sTex + float4(fX4, fY3, 0.0f, 0.0f) );
	sum += GetDepthSample( sTex + float4(fX4, fY4, 0.0f, 0.0f) );

	sum /= 16.0f;

	return sum;
}

/////////////////////////////////////////////////////////////////////////////////////////

float DoShadowPCFDepth64( const float4 sTex )
{
	float sum = 0;
	sum += GetDepthSample( sTex + float4(-3.5 * g_fShadowMapScaleX, -3.5 * g_fShadowMapScaleY, 0.0f, 0.0f) );
	sum += GetDepthSample( sTex + float4(-2.5 * g_fShadowMapScaleX, -3.5 * g_fShadowMapScaleY, 0.0f, 0.0f) );
	sum += GetDepthSample( sTex + float4(-1.5 * g_fShadowMapScaleX, -3.5 * g_fShadowMapScaleY, 0.0f, 0.0f) );
	sum += GetDepthSample( sTex + float4(-0.5 * g_fShadowMapScaleX, -3.5 * g_fShadowMapScaleY, 0.0f, 0.0f) );
	sum += GetDepthSample( sTex + float4( 0.5 * g_fShadowMapScaleX, -3.5 * g_fShadowMapScaleY, 0.0f, 0.0f) );
	sum += GetDepthSample( sTex + float4( 1.5 * g_fShadowMapScaleX, -3.5 * g_fShadowMapScaleY, 0.0f, 0.0f) );
	sum += GetDepthSample( sTex + float4( 2.5 * g_fShadowMapScaleX, -3.5 * g_fShadowMapScaleY, 0.0f, 0.0f) );
	sum += GetDepthSample( sTex + float4( 3.5 * g_fShadowMapScaleX, -3.5 * g_fShadowMapScaleY, 0.0f, 0.0f) );

	sum += GetDepthSample( sTex + float4(-3.5 * g_fShadowMapScaleX, -2.5 * g_fShadowMapScaleY, 0.0f, 0.0f) );
	sum += GetDepthSample( sTex + float4(-2.5 * g_fShadowMapScaleX, -2.5 * g_fShadowMapScaleY, 0.0f, 0.0f) );
	sum += GetDepthSample( sTex + float4(-1.5 * g_fShadowMapScaleX, -2.5 * g_fShadowMapScaleY, 0.0f, 0.0f) );
	sum += GetDepthSample( sTex + float4(-0.5 * g_fShadowMapScaleX, -2.5 * g_fShadowMapScaleY, 0.0f, 0.0f) );
	sum += GetDepthSample( sTex + float4( 0.5 * g_fShadowMapScaleX, -2.5 * g_fShadowMapScaleY, 0.0f, 0.0f) );
	sum += GetDepthSample( sTex + float4( 1.5 * g_fShadowMapScaleX, -2.5 * g_fShadowMapScaleY, 0.0f, 0.0f) );
	sum += GetDepthSample( sTex + float4( 2.5 * g_fShadowMapScaleX, -2.5 * g_fShadowMapScaleY, 0.0f, 0.0f) );
	sum += GetDepthSample( sTex + float4( 3.5 * g_fShadowMapScaleX, -2.5 * g_fShadowMapScaleY, 0.0f, 0.0f) );

	sum += GetDepthSample( sTex + float4(-3.5 * g_fShadowMapScaleX, -1.5 * g_fShadowMapScaleY, 0.0f, 0.0f) );
	sum += GetDepthSample( sTex + float4(-2.5 * g_fShadowMapScaleX, -1.5 * g_fShadowMapScaleY, 0.0f, 0.0f) );
	sum += GetDepthSample( sTex + float4(-1.5 * g_fShadowMapScaleX, -1.5 * g_fShadowMapScaleY, 0.0f, 0.0f) );
	sum += GetDepthSample( sTex + float4(-0.5 * g_fShadowMapScaleX, -1.5 * g_fShadowMapScaleY, 0.0f, 0.0f) );
	sum += GetDepthSample( sTex + float4( 0.5 * g_fShadowMapScaleX, -1.5 * g_fShadowMapScaleY, 0.0f, 0.0f) );
	sum += GetDepthSample( sTex + float4( 1.5 * g_fShadowMapScaleX, -1.5 * g_fShadowMapScaleY, 0.0f, 0.0f) );
	sum += GetDepthSample( sTex + float4( 2.5 * g_fShadowMapScaleX, -1.5 * g_fShadowMapScaleY, 0.0f, 0.0f) );
	sum += GetDepthSample( sTex + float4( 3.5 * g_fShadowMapScaleX, -1.5 * g_fShadowMapScaleY, 0.0f, 0.0f) );

	sum += GetDepthSample( sTex + float4(-3.5 * g_fShadowMapScaleX, -0.5 * g_fShadowMapScaleY, 0.0f, 0.0f) );
	sum += GetDepthSample( sTex + float4(-2.5 * g_fShadowMapScaleX, -0.5 * g_fShadowMapScaleY, 0.0f, 0.0f) );
	sum += GetDepthSample( sTex + float4(-1.5 * g_fShadowMapScaleX, -0.5 * g_fShadowMapScaleY, 0.0f, 0.0f) );
	sum += GetDepthSample( sTex + float4(-0.5 * g_fShadowMapScaleX, -0.5 * g_fShadowMapScaleY, 0.0f, 0.0f) );
	sum += GetDepthSample( sTex + float4( 0.5 * g_fShadowMapScaleX, -0.5 * g_fShadowMapScaleY, 0.0f, 0.0f) );
	sum += GetDepthSample( sTex + float4( 1.5 * g_fShadowMapScaleX, -0.5 * g_fShadowMapScaleY, 0.0f, 0.0f) );
	sum += GetDepthSample( sTex + float4( 2.5 * g_fShadowMapScaleX, -0.5 * g_fShadowMapScaleY, 0.0f, 0.0f) );
	sum += GetDepthSample( sTex + float4( 3.5 * g_fShadowMapScaleX, -0.5 * g_fShadowMapScaleY, 0.0f, 0.0f) );

	sum += GetDepthSample( sTex + float4(-3.5 * g_fShadowMapScaleX,  0.5 * g_fShadowMapScaleY, 0.0f, 0.0f) );
	sum += GetDepthSample( sTex + float4(-2.5 * g_fShadowMapScaleX,  0.5 * g_fShadowMapScaleY, 0.0f, 0.0f) );
	sum += GetDepthSample( sTex + float4(-1.5 * g_fShadowMapScaleX,  0.5 * g_fShadowMapScaleY, 0.0f, 0.0f) );
	sum += GetDepthSample( sTex + float4(-0.5 * g_fShadowMapScaleX,  0.5 * g_fShadowMapScaleY, 0.0f, 0.0f) );
	sum += GetDepthSample( sTex + float4( 0.5 * g_fShadowMapScaleX,  0.5 * g_fShadowMapScaleY, 0.0f, 0.0f) );
	sum += GetDepthSample( sTex + float4( 1.5 * g_fShadowMapScaleX,  0.5 * g_fShadowMapScaleY, 0.0f, 0.0f) );
	sum += GetDepthSample( sTex + float4( 2.5 * g_fShadowMapScaleX,  0.5 * g_fShadowMapScaleY, 0.0f, 0.0f) );
	sum += GetDepthSample( sTex + float4( 3.5 * g_fShadowMapScaleX,  0.5 * g_fShadowMapScaleY, 0.0f, 0.0f) );

	sum += GetDepthSample( sTex + float4(-3.5 * g_fShadowMapScaleX,  1.5 * g_fShadowMapScaleY, 0.0f, 0.0f) );
	sum += GetDepthSample( sTex + float4(-2.5 * g_fShadowMapScaleX,  1.5 * g_fShadowMapScaleY, 0.0f, 0.0f) );
	sum += GetDepthSample( sTex + float4(-1.5 * g_fShadowMapScaleX,  1.5 * g_fShadowMapScaleY, 0.0f, 0.0f) );
	sum += GetDepthSample( sTex + float4(-0.5 * g_fShadowMapScaleX,  1.5 * g_fShadowMapScaleY, 0.0f, 0.0f) );
	sum += GetDepthSample( sTex + float4( 0.5 * g_fShadowMapScaleX,  1.5 * g_fShadowMapScaleY, 0.0f, 0.0f) );
	sum += GetDepthSample( sTex + float4( 1.5 * g_fShadowMapScaleX,  1.5 * g_fShadowMapScaleY, 0.0f, 0.0f) );
	sum += GetDepthSample( sTex + float4( 2.5 * g_fShadowMapScaleX,  1.5 * g_fShadowMapScaleY, 0.0f, 0.0f) );
	sum += GetDepthSample( sTex + float4( 3.5 * g_fShadowMapScaleX,  1.5 * g_fShadowMapScaleY, 0.0f, 0.0f) );

	sum += GetDepthSample( sTex + float4(-3.5 * g_fShadowMapScaleX,  2.5 * g_fShadowMapScaleY, 0.0f, 0.0f) );
	sum += GetDepthSample( sTex + float4(-2.5 * g_fShadowMapScaleX,  2.5 * g_fShadowMapScaleY, 0.0f, 0.0f) );
	sum += GetDepthSample( sTex + float4(-1.5 * g_fShadowMapScaleX,  2.5 * g_fShadowMapScaleY, 0.0f, 0.0f) );
	sum += GetDepthSample( sTex + float4(-0.5 * g_fShadowMapScaleX,  2.5 * g_fShadowMapScaleY, 0.0f, 0.0f) );
	sum += GetDepthSample( sTex + float4( 0.5 * g_fShadowMapScaleX,  2.5 * g_fShadowMapScaleY, 0.0f, 0.0f) );
	sum += GetDepthSample( sTex + float4( 1.5 * g_fShadowMapScaleX,  2.5 * g_fShadowMapScaleY, 0.0f, 0.0f) );
	sum += GetDepthSample( sTex + float4( 2.5 * g_fShadowMapScaleX,  2.5 * g_fShadowMapScaleY, 0.0f, 0.0f) );
	sum += GetDepthSample( sTex + float4( 3.5 * g_fShadowMapScaleX,  2.5 * g_fShadowMapScaleY, 0.0f, 0.0f) );

	sum += GetDepthSample( sTex + float4(-3.5 * g_fShadowMapScaleX, 3.5 * g_fShadowMapScaleY, 0.0f, 0.0f) );
	sum += GetDepthSample( sTex + float4(-2.5 * g_fShadowMapScaleX, 3.5 * g_fShadowMapScaleY, 0.0f, 0.0f) );
	sum += GetDepthSample( sTex + float4(-1.5 * g_fShadowMapScaleX, 3.5 * g_fShadowMapScaleY, 0.0f, 0.0f) );
	sum += GetDepthSample( sTex + float4(-0.5 * g_fShadowMapScaleX, 3.5 * g_fShadowMapScaleY, 0.0f, 0.0f) );
	sum += GetDepthSample( sTex + float4( 0.5 * g_fShadowMapScaleX, 3.5 * g_fShadowMapScaleY, 0.0f, 0.0f) );
	sum += GetDepthSample( sTex + float4( 1.5 * g_fShadowMapScaleX, 3.5 * g_fShadowMapScaleY, 0.0f, 0.0f) );
	sum += GetDepthSample( sTex + float4( 2.5 * g_fShadowMapScaleX, 3.5 * g_fShadowMapScaleY, 0.0f, 0.0f) );
	sum += GetDepthSample( sTex + float4( 3.5 * g_fShadowMapScaleX, 3.5 * g_fShadowMapScaleY, 0.0f, 0.0f) );

	sum /= 64.0f;

	return sum;
}

/////////////////////////////////////////////////////////////////////////////////////////

float4 DoShadowPCF( const float4 sTex )
{
	float	x,
			y;

	float4	sum = 0;

	for (y = -1.5; y <= 1.5; y+= 1.0f)
	{
		float	fY = y * g_fShadowMapScaleY;

		for (x = -1.5; x <= 1.5; x+= 1.0f)
		{
			float	fX = x * g_fShadowMapScaleX;
			sum += tex2D(SHADOWMAP_SAMPLER, GetShadowMapTexCoord( sTex + float4(fX, fY, 0.0f, 0.0f)) );
		}
	}

	sum /= 16.0f;

	sum.y = 1.0f - sum.y;

	return sum;
}

/////////////////////////////////////////////////////////////////////////////////////////

float DoShadow( const float4 sTex, const float NdotL )
{
	float	fV = 1;
	if ( g_iShadowMapEnabled )
	{
		fV = DoShadowPCFDepth9( sTex, NdotL );

		// fade shadow in the distance
		float	fY = sTex.y/sTex.w;

		// fFade = saturate((fY - g_fLodDistance) / (1 - g_fLodDistance));
		// fixed (g_fLodDistance = 0.5) version of above calc
		float	fFade = saturate( (fY-0.5) * 2.0 );

		fV = saturate( fV + fFade );
	}
	
	/*
	if ( g_iShadowMapEnabled )
	{
		if ( g_iShadowMapPCFLevel == 2 )
		{
			fV = DoShadowPCFDepth64( sTex );
		}
		else if ( g_iShadowMapPCFLevel == 1 )
		{
			if ( fDepth < g_fLodDistance )
			{
				fV = DoShadowPCFDepth9( sTex );
//				fV = DoShadowPCFDepth16( sTex );
			}
		}
		else
		{
			fV = GetDepthSample( sTex );
		}
	}
	*/

	return fV;
}

/////////////////////////////////////////////////////////////////////////////////////////

float DoShadowMapAlpha( const float4 sTex)
{
	float result = 1;
	if ( g_iShadowMapEnabled )
	{
		result = GetDepthSample( sTex );
	}
	return result;
}

/////////////////////////////////////////////////////////////////////////////////////////

float DoShadowMapMediumLod( const float4 sTex)
{
	float result = 1;
	if ( g_iShadowMapEnabled )
	{
		result = GetDepthSample( sTex );
	}
	return result;
}

/////////////////////////////////////////////////////////////////////////////////////////

float DoShadowMapLowLOD( const float4 sTex)
{
	float result = 1;
	if ( g_iShadowMapEnabled )
	{
		result = GetDepthSample( sTex );
	}
	return result;
}

/////////////////////////////////////////////////////////////////////////////////////////
