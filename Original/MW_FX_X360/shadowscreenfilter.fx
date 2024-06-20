//
// Shadow screen filter
//

// Used to render a full screen quad over the stencil buffer
//
float4		ShadowColour		: SHADOWVOLUME_COLOUR;

struct VS_INPUT
{
	float4 position : POSITION;
	float4 texcoord : TEXCOORD;
};

struct VtoP
{
	float4 position : POSITION;
};

struct PS_OUTPUT
{
	float4 color : COLOR0;
};

VtoP vertexShader(const VS_INPUT IN)
{
	VtoP OUT;
	OUT.position = IN.position;
	return OUT;
}

PS_OUTPUT pixelShader(VtoP IN)
{
	PS_OUTPUT OUT;
	OUT.color = float4(ShadowColour.rgb, ShadowColour.a);
	return OUT;
}

technique debugRenderStencilBuffer <int shader = 1;>
{
    pass p0
    {
        VertexShader = compile vs_1_1 vertexShader();
        PixelShader  = compile ps_1_1 pixelShader();
    }
}

