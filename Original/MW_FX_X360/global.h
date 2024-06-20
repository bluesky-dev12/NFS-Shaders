/////////////////////////////////////////////////////////////////////////////////////////
float4x4 WorldViewProj   : WORLDVIEWPROJECTION ;
shared float4 ScreenOffset		: SCREENOFFSET;

float4 world_position( float4 screen_pos )
{
 	float4 p = mul(screen_pos, WorldViewProj);
	p.xy += ScreenOffset.xy * p.w;
    return p;
}

float4 screen_position( float4 screen_pos )
{
	screen_pos.xy += ScreenOffset.xy;
    return screen_pos;
}
