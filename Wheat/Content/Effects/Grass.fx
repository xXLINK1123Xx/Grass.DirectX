﻿Texture2D Texture;
Texture2D AlphaTexture;
sampler TextureSampler = sampler_state
{
	AddressU = WRAP;
	AddressV = WRAP;
	Filter = D3D11_FILTER_COMPARISON_ANISOTROPIC;
	MaxAnisotropy = 16;
    MaxLOD = 2.0f;
};

float3 HUEtoRGB(in float H)
{
	float R = abs(H * 6 - 3) - 1;
	float G = 2 - abs(H * 6 - 2);
	float B = 2 - abs(H * 6 - 4);
	return saturate(float3(R, G, B));
}

float3 HSVtoRGB(in float3 HSV)
{
	float3 RGB = HUEtoRGB(HSV.x);
	return ((RGB - 1) * HSV.y + 1) * HSV.z;
}

float4x4 World;
float4x4 View;
float4x4 Projection;

float3 AmbientColor;
float AmbientIntensity;

float3 DiffuseColor;
float DiffuseIntensity;

float3 LightPosition;
float3 CameraPosition;

float2 Time;
float2 WindVector;

// Our constants
static const float kHalfPi = 1.5707;
static const float kQuarterPi = 0.7853;
static const float kOscillateDelta = 0.35;
static const float kWindCoeff = 87.0f;

////////////////////////////////////////////////////////////////////////////////////
struct VSINPUT
{
	float4 Position : SV_POSITION;
	float4 Normal	: NORMAL0;
	float2 TexCoord	: TEXCOORD0;
};

struct GEO_IN
{
    float4 Position			: SV_POSITION;
	float4 Normal			: NORMAL0;
};

struct GEO_OUT
{
    float4 Position			: SV_POSITION;
    float2 TexCoord			: TEXCOORD;
	float4 Normal			: NORMAL0;
	float3 VertexToLight	: NORMAL1;
	float3 VertexToCamera	: NORMAL2;
	float3 LevelOfDetail	: NORMAL3;
	float Random			: NORMAL4;
};

GEO_OUT createGEO_OUT() {
	GEO_OUT output;
	
	output.Position = float4(0, 0, 0, 0);
	output.Normal = float4(0, 0, 0, 0);
	output.TexCoord = float2(0, 0);
	output.VertexToLight = float3(0, 0, 0);
	output.VertexToCamera = float3(0, 0, 0);
	output.LevelOfDetail = float3(0, 0, 0);
	output.Random = 0;

	return output;
}

////////////////////////////////////////////////////////////////////////////////////
void VS_Shader(in VSINPUT input, out GEO_IN output)
{
	output.Position = input.Position;
	output.Normal = input.Normal;
}

////////////////////////////////////////////////////////////////////////////////////
void GS_Shader(point GEO_IN points[1], in uint vertexDifference, inout TriangleStream<GEO_OUT> output)
{
	float4 root = points[0].Position;

	// Generate a random number between 0.0 to 1.0 by using the root position (which is randomized by the CPU)
	float random = sin(kHalfPi * frac(root.x) + kHalfPi * frac(root.z));
	float randomRotation = random;

	float cameraDistance = length(CameraPosition.xz - root.xz);

	// Properties of the grass blade
	float minHeight = 2.3;
	float minWidth = 0.1 + (cameraDistance * 0.001);
	float sizeX = minWidth + (random / 50);
	float sizeY = minHeight + (random / 5);

	// Animation
	float toTheLeft = sin(Time.x);

	// Rotate in Z-axis
	float3x3 rotationMatrix = {		cos(randomRotation),	0,	sin(randomRotation),
									0,						1,	0,
									-sin(randomRotation),	0,	cos(randomRotation) };

	/////////////////////////////////
	// Generating vertices
	/////////////////////////////////

	const uint vertexCount = 12;
	float3 levelOfDetail = { vertexDifference * 0.0, 1, vertexDifference * 0.0 };
	const float realVertexCount = (vertexCount - vertexDifference);
	GEO_OUT v[vertexCount] = {
		createGEO_OUT(), createGEO_OUT(), createGEO_OUT(), createGEO_OUT(),
		createGEO_OUT(), createGEO_OUT(), createGEO_OUT(), createGEO_OUT(),
		createGEO_OUT(), createGEO_OUT(), createGEO_OUT(), createGEO_OUT()
	};

	float3 positionWS[vertexCount];

	// This is used to calculate the current V position of our TexCoords.
	// We know the U position, because even vertices (0, 2, 4, ...) always have X = 0
	// And uneven vertices (1, 3, 5, ...) always have X = 1
	float currentV = 1;
	float VOffset = 1 / ((realVertexCount / 2) - 1);
	float currentNormalY = 0;
	float currentHeightOffset = sqrt(sizeY);
	float currentVertexHeight = 0;

	// Wind
	float windCoEff = 0;

	// We don't want to interpolate linearly for the normals. The bottom vertex should be 0, top vertex should be 1.
	// If we interpolate linearly and we have 4 vertices, we get 0, 0.33, 0.66, 1. 
	// Using pow, we can adjust the curve so that we get lower values on the bottom and higher values on the top.
	float steepnessFactor = 1; 
	
	// Transform into projection space and calculate vectors needed for light calculation
	[unroll]
	for(uint i = 0; i < vertexCount - vertexDifference; i++)
	{
		// Fake creation of the normal. Pointing downwards on the bottom. Pointing upwards on the top. And then interpolating in between.
		v[i].Normal = normalize(float4(0, pow(currentNormalY, steepnessFactor), 0, 1));

		// Creating vertices and calculating Texcoords (UV)
		// Vertices start at the bottom and go up. v(0) and v(1) are left bottom and right bottom.
		if (i % 2 == 0) { // 0, 2, 4
			v[i].Position = float4(root.x - sizeX, root.y + currentVertexHeight, root.z, 1);
			v[i].TexCoord = float2(0, currentV);
		} else { // 1, 3, 5
			v[i].Position = float4(root.x + sizeX, root.y + currentVertexHeight, root.z, 1);
			v[i].TexCoord = float2(1, currentV);
		}

		// First rotate (translate to origin)
		v[i].Position = float4(v[i].Position.x - root.x, v[i].Position.y - root.y, v[i].Position.z - root.z, 1);
		v[i].Position = float4(mul(v[i].Position.xyz, rotationMatrix), 1);
		v[i].Position = float4(v[i].Position.x + root.x, v[i].Position.y + root.y, v[i].Position.z + root.z, 1);

		// Wind
		float2 windVec = WindVector;
		windVec.x += sin(Time.x + root.x / 10);
		//windVec.y += cos(Time.x + root.z / 2.5);
		windVec *= lerp(0.7, 1.0, 1.0 - random);

		// Oscillate wind
		float sinSkewCoeff = random;
		float oscillationStrength = 4.0f;
		float lerpCoeff = (sin(oscillationStrength * Time.x + sinSkewCoeff) + 1.0) / 2;
		float2 leftWindBound = windVec * (1.0 - kOscillateDelta);
		float2 rightWindBound = windVec * (1.0 + kOscillateDelta);
		windVec = lerp(leftWindBound, rightWindBound, lerpCoeff);

		// Randomize wind by adding a random wind vector
		float randAngle = lerp(-3.14, 3.14, random);
		float randMagnitude = lerp(0, 1.0, random);
		float2 randWindDir = float2(sin(randAngle), cos(randAngle));
		windVec += randWindDir * randMagnitude;

		float windForce = length(windVec);

		// Calculate final vertex position based on wind
		v[i].Position.xz += windVec.xy * windCoEff;
		v[i].Position.y -= windForce * windCoEff * 0.5;
		positionWS[i] = mul(v[i].Position, World).xyz;

		// Calculate output
		v[i].Position = mul(mul(mul(v[i].Position, World), View), Projection);
		v[i].VertexToLight = normalize(LightPosition - positionWS[i].xyz);
		v[i].VertexToCamera = normalize(CameraPosition - positionWS[i].xyz);
		v[i].Random = random;
		v[i].LevelOfDetail = levelOfDetail;

		if (i % 2 != 0) {
			// General
			currentV -= VOffset;
			currentNormalY += VOffset * 2;
			levelOfDetail.r += VOffset;

			// Height
			currentHeightOffset -= VOffset;
			float currentHeight = sizeY - (currentHeightOffset * currentHeightOffset);
			currentVertexHeight = currentHeight;

			// Wind
			windCoEff += VOffset; // TODO: Check these values
		}
	}

	// Connect the vertices
	[unroll]
	for (uint p = 0; p < (vertexCount - vertexDifference - 2); p++) {
		output.Append(v[p]);
		output.Append(v[p+2]);
		output.Append(v[p+1]);
	}
}

////////////////////////////////////////////////////////////////////////////////////
float4 PS_Shader(in GEO_OUT input) : SV_TARGET
{
	float4 textureColor = Texture.Sample(TextureSampler, input.TexCoord);
	float4 alphaColor = AlphaTexture.Sample(TextureSampler, input.TexCoord);

	// Phong
	float3 r = normalize(reflect(input.VertexToLight.xyz, input.Normal.xyz));
	float shininess = 100;

	float ambientLight = 0.1;
	float diffuseLight = saturate(dot(input.VertexToLight, input.Normal.xyz));
	float specularLight = saturate(dot(-input.VertexToCamera, r));
	specularLight = saturate(pow(specularLight, shininess));
	
	float light = ambientLight + (diffuseLight * 2) + (specularLight * 0.5);
	
	float3 grassColorHSV = { 0.1 + (input.Random / 6), 0.67, 1 };
	float3 grassColorRGB = HSVtoRGB(grassColorHSV);

	float3 lightColor = float3(1.0, 0.8, 0.8);

	// Debugging: Show level of detail
	if (alphaColor.g <= 0.95) {
		alphaColor.g = 0;
	}

	return float4(light * textureColor.rgb, alphaColor.g);
	return float4(light * textureColor.rgb * grassColorRGB, alphaColor.g);
	//return float4(light * input.LevelOfDetail.xyz , alphaColor.g);
	return float4((textureColor.rgb * grassColorRGB) * (light * lightColor), textureColor.a);
}


////////////////////////////////////////////////////////////////////////////////////
[maxvertexcount(40)]
void GS_LOD1(point GEO_IN points[1], inout TriangleStream<GEO_OUT> output) 
{
	GS_Shader(points, 0, output);
}

[maxvertexcount(40)]
void GS_LOD2(point GEO_IN points[1], inout TriangleStream<GEO_OUT> output)
{
	GS_Shader(points, 4, output);
}

[maxvertexcount(40)]
void GS_LOD3(point GEO_IN points[1], inout TriangleStream<GEO_OUT> output)
{
	GS_Shader(points, 6, output);
}

[maxvertexcount(40)]
void GS_LOD4(point GEO_IN points[1], inout TriangleStream<GEO_OUT> output)
{
	GS_Shader(points, 8, output);
}

technique LevelOfDetail1
{
	pass Pass1
	{
		VertexShader = compile vs_4_0 VS_Shader();
		GeometryShader = compile gs_4_0 GS_LOD1();
		PixelShader = compile ps_4_0 PS_Shader();
	}
}

technique LevelOfDetail2
{
	pass Pass1
	{
		VertexShader = compile vs_4_0 VS_Shader();
		GeometryShader = compile gs_4_0 GS_LOD2();
		PixelShader = compile ps_4_0 PS_Shader();
	}
}

technique LevelOfDetail3
{
	pass Pass1
	{
		VertexShader = compile vs_4_0 VS_Shader();
		GeometryShader = compile gs_4_0 GS_LOD3();
		PixelShader = compile ps_4_0 PS_Shader();
	}
}

technique LevelOfDetail4
{
	pass Pass1
	{
		VertexShader = compile vs_4_0 VS_Shader();
		GeometryShader = compile gs_4_0 GS_LOD4();
		PixelShader = compile ps_4_0 PS_Shader();
	}
}