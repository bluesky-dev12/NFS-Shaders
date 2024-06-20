//
// Debug Polygon Effect
//

sampler DIFFUSEMAP_SAMPLER = sampler_state
{
	AddressU = CLAMP;
	AddressV = CLAMP;
	MIPFILTER = LINEAR;
	MINFILTER = LINEAR;
	MAGFILTER = LINEAR;
};

sampler1D MISCMAP1D_SAMPLER = sampler_state
{
	AddressU = CLAMP;
	AddressV = CLAMP;
	MIPFILTER = LINEAR;
	MINFILTER = LINEAR;
	MAGFILTER = LINEAR;
};

sampler MISCMAP1_SAMPLER = sampler_state
{
	AddressU = CLAMP;
	AddressV = CLAMP;
	MIPFILTER = POINT;
	MINFILTER = POINT;
	MAGFILTER = POINT;
};

struct VS_INPUT
{
	float4 position : POSITION;
	float4 texcoord : TEXCOORD;
};

struct VtoP
{
	float4 position : POSITION;
	float4 color    : COLOR0;
	float4 tex      : TEXCOORD0;
};

struct PS_OUTPUT
{
	float4 color : COLOR0;
};

float2	g_vPixelizationScale;

VtoP vertex_shader(const VS_INPUT IN)
{
	VtoP OUT;
	OUT.position = IN.position;
	OUT.tex = IN.texcoord;
	OUT.color = 0x77777777;

	return OUT;
}

PS_OUTPUT pixel_shader_1d_rgba(const VtoP IN)
{
	PS_OUTPUT OUT;

	OUT.color = tex1D(MISCMAP1D_SAMPLER, IN.tex.x);	// * IN.color;

	return OUT;
}

PS_OUTPUT pixel_shader_alpha(const VtoP IN)
{
	PS_OUTPUT OUT;

	float alpha = tex2D(DIFFUSEMAP_SAMPLER, IN.tex).a;
	OUT.color = float4(alpha, alpha, alpha, 1);	// * IN.color;

	return OUT;
}

PS_OUTPUT pixel_shader_rgba(const VtoP IN)
{
	PS_OUTPUT OUT;

	OUT.color = tex2D(DIFFUSEMAP_SAMPLER, IN.tex);	// * IN.color;
	//OUT.color.xyz = OUT.color.w;

	return OUT;
}

PS_OUTPUT pixel_shader_fp32(const VtoP IN)
{
	PS_OUTPUT OUT;

	float	fVal = tex2D(DIFFUSEMAP_SAMPLER, IN.tex).x;
	OUT.color.x = fVal;
	OUT.color.y = fVal;
	OUT.color.z = fVal;
	OUT.color.w = 1.0f;

	return OUT;
}

PS_OUTPUT pixel_shader_white_half_alpha(const VtoP IN)
{
	PS_OUTPUT OUT;

	OUT.color.r = 1.0f;
	OUT.color.g = 1.0f;
	OUT.color.b = 1.0f;
	OUT.color.a = 0.5f;
	return OUT;
}

PS_OUTPUT pixel_shader_multiply_textures_alpha(const VtoP IN)
{
	PS_OUTPUT OUT;

	float4	vDiffuse = tex2D(DIFFUSEMAP_SAMPLER, IN.tex),
			vAlpha   = tex2D(MISCMAP1_SAMPLER,   IN.tex);

	OUT.color.rgb = vDiffuse.rgb * vAlpha.a;
	OUT.color.a   = vAlpha.a;

	return OUT;
}

PS_OUTPUT pixel_shader_pixel_double( const VtoP IN )
{
	PS_OUTPUT OUT;

	float2	vOffset = round( IN.tex*g_vPixelizationScale ) / g_vPixelizationScale;

	OUT.color = tex2D( MISCMAP1_SAMPLER, vOffset );

	return OUT;
}

technique screen_poly_rgba_texture <int shader = 1;>
{
    pass p0
    {
        VertexShader = compile vs_1_1 vertex_shader();
        PixelShader  = compile ps_1_1 pixel_shader_rgba();
    }
}
technique screen_poly_alpha_texture <int shader = 1;>
{
    pass p0
    {
        VertexShader = compile vs_1_1 vertex_shader();
        PixelShader  = compile ps_1_1 pixel_shader_alpha();
    }
}

technique screen_poly_1d_texture <int shader = 1;>
{
    pass p0
    {
        VertexShader = compile vs_1_1 vertex_shader();
        PixelShader  = compile ps_1_1 pixel_shader_1d_rgba();
    }
}

technique screen_poly_fp32_texture <int shader = 1;>
{
    pass p0
    {
        VertexShader = compile vs_1_1 vertex_shader();
        PixelShader  = compile ps_1_1 pixel_shader_fp32();
    }
}

technique screen_poly_multiply_textures_alpha <int shader = 1;>
{
	pass p0
	{
        VertexShader = compile vs_1_1 vertex_shader();
        PixelShader  = compile ps_2_0 pixel_shader_multiply_textures_alpha();
	}
}

technique screen_poly_alpha <int shader = 1;>
{
	pass p0
	{
        VertexShader = compile vs_1_1 vertex_shader();
		PixelShader  = compile ps_2_0 pixel_shader_white_half_alpha();
	}
}

technique screen_poly_double <int shader = 1;>
{
	pass p0
	{
        VertexShader = compile vs_1_1 vertex_shader();
		PixelShader  = compile ps_2_0 pixel_shader_pixel_double();
	}
}
