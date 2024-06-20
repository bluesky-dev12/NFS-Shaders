//
// Auxiliary Lighting
//

#define		MAX_LIGHTS			6				// must match NUM_AUXILIARY_LIGHTS in eSolidPlat.hpp
float4x4	Lights[MAX_LIGHTS]					: AUXILIARY_LIGHTS;
int			ActiveAuxiliaryLight0				: ACTIVE_AUXILIARY_LIGHT0;
int			ActiveAuxiliaryLight1				: ACTIVE_AUXILIARY_LIGHT1;
int			ActiveAuxiliaryLight2				: ACTIVE_AUXILIARY_LIGHT2;
int			ActiveAuxiliaryLight3				: ACTIVE_AUXILIARY_LIGHT3;
int			ActiveAuxiliaryLight4				: ACTIVE_AUXILIARY_LIGHT4;
int			ActiveAuxiliaryLight5				: ACTIVE_AUXILIARY_LIGHT5;
int			ActiveAuxiliaryLight6				: ACTIVE_AUXILIARY_LIGHT6;
int			ActiveAuxiliaryLight7				: ACTIVE_AUXILIARY_LIGHT7;

void AuxiliaryLight(int lightIndex, float3 lightDir, float3 position, float3 normal, float3 viewDir, in out float3 diffuse, in out float3 specular)
{
	float4 light = Lights[lightIndex][0];
	float4 colourIlluminance = Lights[lightIndex][2];
	float3 dist = light.xyz - position;
	float dist2 = dot(dist, dist);
//// habib coloring lights hack
float3 lightColor;
lightColor.x = 1.0;
lightColor.y = 0.65;
lightColor.z = 0.15;
        //// habib added multiply by 2 for dist2 for faster falloff
	float3 intensity = colourIlluminance.xyz * lightColor/ (dist2*2.0+colourIlluminance.w);// Colour and inverse squared falloff  
	// Diffuse
	float  ndotl = dot(normal, lightDir);
	diffuse += saturate(ndotl) * intensity;
//// habib faster falloff hack
//diffuse = pow(diffuse,1.5);	

	// Specular
	float specularCoeff = saturate(dot(2*ndotl*normal-lightDir, viewDir));
	specular += pow(specularCoeff, 25) * intensity * 1.75;
}
