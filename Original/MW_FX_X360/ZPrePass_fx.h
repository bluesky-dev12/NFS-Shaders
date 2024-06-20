/////////////////////////////////////////////////////////////////////////////////////////

struct VtoPZ
{
	float4 position		: POSITION;
};

VtoPZ ZPass_vertex_shader(const VS_INPUT IN)
{
	VtoPZ OUT;

	OUT.position = mul(IN.position, WorldViewProj);

	return OUT;
}

technique ZPrePass <int shader = 1;>
{
	pass p0
	{
		VertexShader		= compile vs_1_1 ZPass_vertex_shader();
		PixelShader			= NULL;
	}
}

/////////////////////////////////////////////////////////////////////////////////////////
struct VtoP_vertex_colour
{
	float4 position		: POSITION;
	float4 color		: COLOR;
};

VtoP_vertex_colour vertex_shader_vertex_colour(	float4 position : POSITION,
												float4 color    : COLOR)
{
	VtoP_vertex_colour OUT;

	OUT.position = mul(position, WorldViewProj);
	OUT.color	 = color;

	return OUT;
}

float4 pixel_shader_vertex_colour(const VtoP_vertex_colour IN) : COLOR0
{
	return IN.color;
}

technique RenderVertexColour <int shader = 1;>
{
	pass p0
	{
		VertexShader = compile vs_1_1 vertex_shader_vertex_colour();
		PixelShader  = compile ps_2_0 pixel_shader_vertex_colour();
	}
}

/////////////////////////////////////////////////////////////////////////////////////////
