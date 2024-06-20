/////////////////////////////////////////////////////////////////////////////////////////

VtoP_Light vertex_shader_light(const VS_INPUT IN)
{
	VtoP_Light OUT;
	float4 p = mul(IN.position, WorldViewProj);
	OUT.position = p;

	OUT.dist.xy = OUT.position.zw;

	OUT.diffuseTex.xy = IN.tex.xy;
	OUT.diffuseTex.zw = 1.0f;
	
	return OUT;
}

/////////////////////////////////////////////////////////////////////////////////////////

PS_OUTPUT pixel_shader_light_alpha_tex(const VtoP_Light IN)
{
	PS_OUTPUT	OUT;

	OUT.color = 1;

	if ( g_bShadowMapAlphaEnabled )
	{
		float4	vTex = tex2D(DIFFUSEMAP_SAMPLER, IN.diffuseTex);

		// check alpha
		if ( vTex.w <= g_fShadowMapAlphaMin )
		{
			// generate texkill
			float	vKill = -1.0f;
			clip( vKill );
		}
	}

	return OUT;
}

/////////////////////////////////////////////////////////////////////////////////////////

technique RenderLight <int shader = 1;>
{
    pass p0
    {
		VertexShader = compile vs_1_1 vertex_shader_light();
		PixelShader  = NULL;		// Fast Z-path enabled by setting PS NULL
    }
}

/////////////////////////////////////////////////////////////////////////////////////////

technique RenderLightAlphaTex <int shader = 1;>
{
    pass p0
    {
		VertexShader = compile vs_1_1 vertex_shader_light();
		PixelShader  = compile ps_3_0 pixel_shader_light_alpha_tex();
    }
}

/////////////////////////////////////////////////////////////////////////////////////////

struct VtoP_World
{
	float4 position : POSITION;
	float4 color    : COLOR0;
};

/////////////////////////////////////////////////////////////////////////////////////////

VtoP_World vertex_shader_world(const VS_INPUT IN)
{
	VtoP_World OUT;

	OUT.position = mul(IN.position, WorldViewProj);
	OUT.color	 = ( 1.0f, 1.0f, 1.0f, 1.0f );

	return OUT;
}

/////////////////////////////////////////////////////////////////////////////////////////

struct VtoP_World_Tex
{
	float4 position		: POSITION;
	float4 color		: COLOR0;
	float2 diffuseTex	: TEXCOORD0;
};

/////////////////////////////////////////////////////////////////////////////////////////

VtoP_World_Tex vertex_shader_world_tex(const VS_INPUT IN)
{
	VtoP_World_Tex OUT;

	OUT.position	= mul(IN.position, WorldViewProj);
	OUT.color		= ( 1.0f, 1.0f, 1.0f, 1.0f );
	OUT.diffuseTex	= IN.tex;

	return OUT;
}

/////////////////////////////////////////////////////////////////////////////////////////

PS_OUTPUT pixel_shader_white(const VtoP_World_Tex IN)
{
	PS_OUTPUT OUT;

	OUT.color = 1.0f;

	return OUT;
}

/////////////////////////////////////////////////////////////////////////////////////////

PS_OUTPUT pixel_shader_texel_density(const VtoP_World_Tex IN)
{
	PS_OUTPUT OUT;

	OUT.color.x   = fmod( floor( IN.diffuseTex.x*g_fDiffuseMapWidth /10 ), 2 );
	OUT.color.y   = fmod( floor( IN.diffuseTex.y*g_fDiffuseMapHeight/10 ), 2 );
	OUT.color.xyz = fmod( OUT.color.x+OUT.color.y, 2 );
	OUT.color.w   = 1.0f;

	return OUT;
}

/////////////////////////////////////////////////////////////////////////////////////////

PS_OUTPUT pixel_shader_white_alpha_tex( const VtoP_World_Tex IN )
{
	PS_OUTPUT OUT;

	float4	vTex = tex2D(DIFFUSEMAP_SAMPLER, IN.diffuseTex);

	// check alpha
	if ( vTex.w > g_fShadowMapAlphaMin )
	{
		OUT.color = ( 1.0f, 1.0f, 1.0f, 1.0f );
	}
	else
	{
		// generate texkill
		float	vKill = -1.0f;
		clip( vKill );
	}

	return OUT;
}

/////////////////////////////////////////////////////////////////////////////////////////

technique RenderWhite <int shader = 1;>
{
    pass p0
    {
		VertexShader = compile vs_1_1 vertex_shader_world();
        PixelShader  = compile ps_3_0 pixel_shader_white();
    }
}

/////////////////////////////////////////////////////////////////////////////////////////

technique RenderTexelDensity <int shader = 1;>
{
    pass p0
    {
		VertexShader = compile vs_1_1 vertex_shader_world_tex();
        PixelShader  = compile ps_3_0 pixel_shader_texel_density();
    }
}

/////////////////////////////////////////////////////////////////////////////////////////

technique RenderWhiteAlphaTex <int shader = 1;>
{
    pass p0
    {
		VertexShader = compile vs_1_1 vertex_shader_world_tex();
        PixelShader  = compile ps_3_0 pixel_shader_white_alpha_tex();
    }
}

/////////////////////////////////////////////////////////////////////////////////////////
