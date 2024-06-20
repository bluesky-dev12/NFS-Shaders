#define fog_g1 0
#define fog_g2 1
#define fog_g3 2
#define fog_multiplier 3

float3 Fog_Br_Plus_Bm : FOG_BR_PLUS_BM; // br+bm
float3 Fog_One_Over_BrBm : FOG_ONE_OVER_BRBM; // 1/(br+bm)
float3 Fog_Const_1 : FOG_CONST1; // 3/(16 * PI) * br, w=distance scale
float3 Fog_Const_2 : FOG_CONST2; // 1/(4 * PI) * bm

float4 Fog_Const_3 : FOG_CONST3; // (1-g)^2, 1+g*g, -2 * g, multiplier
//float4 SunColor : SUNCOLOR; // Sun color and intensity

const float kMaxDist = 7000;
// I tried to put this in Fog_Const_1.w but is wasn't being transfered through
// correctly to some of the shaders... probably a D3D bug.
float   Fog_DistanceScale : FOG_DISTANCE_SCALE;		

void CalcFogNoDistScale(in float dist, in float cos_theta, out float3 fogAdd, out float3 fogMod)
{
	//float3 t = Fog_Br_Plus_Bm.xyz * -min(dist, kMaxDist);
	float3 t = Fog_Br_Plus_Bm.xyz * -dist;//-min(dist, 7000.0);

	float3 extinct = exp(t.xyz);

	//OUT.FogMod.xyz = saturate(extinct.xyz * SunColor.xyz * SunColor.w);
	fogMod.xyz = saturate(extinct.xyz);

	float cos_sq = cos_theta * cos_theta;

	float phase1 = 1.0 + cos_sq;
	float phase2 = Fog_Const_3[fog_g2] + Fog_Const_3[fog_g3] * cos_theta;
	phase2 = rsqrt(phase2);
	phase2 = phase2 * phase2 * phase2 * Fog_Const_3[fog_g1];

	float3 br_theta, bm_theta;

	br_theta = Fog_Const_1.xyz * phase1;
	bm_theta = Fog_Const_2 * phase2;
	float3 lin = (br_theta + bm_theta) * Fog_One_Over_BrBm * (1.0 - extinct);

	//OUT.FogAdd = saturate(SunColor.xyz * lin * SunColor.w * Fog_Const_3[fog_multiplier]);
	fogAdd = saturate(lin * Fog_Const_3[fog_multiplier]);
}

void CalcFog(in float dist, in float cos_theta, out float3 fogAdd, out float3 fogMod)
{
	CalcFogNoDistScale(min(dist * Fog_DistanceScale, kMaxDist), cos_theta, fogAdd, fogMod);
}
