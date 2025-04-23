// Copyright (c) 2025 Outmode
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in all
// copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.

#include "ReShade.fxh"

texture2D screenTexture : COLOR;
sampler2D screenSampler {
	Texture = screenTexture;
	AddressU = BORDER;
	AddressV = BORDER;
	AddressW = BORDER;
};

texture2D depthTexture : DEPTH;
sampler2D depthSampler {
	Texture = depthTexture;
	AddressU = BORDER;
	AddressV = BORDER;
	AddressW = BORDER;
};

texture2D cursorTexture < source = "Rendepth/Cursor_64px.png"; > {
	Format = RGBA8;
	MipLevels = 7;
	Width = 64;
	Height = 64;
};
sampler2D cursorSampler {
	Texture = cursorTexture;
};

#define Anaglyph 0
#define Side_By_Side 1
#define Color_Plus_Depth 2
#define Horizontal 3
#define Vertical 4
#define Checkerboard 5

#define Left_Side 0
#define Right_Side 1
#define Both_Sides 2

static const float zNear = 0.1;
static const float zFar = 100.0;
static const float stereoScale = 50000.0;
static const float depthSamples[5] = { 0.16, 0.27, 0.41, 0.66, 1.0 };
static const int sampleCount = 5;
static const float3x3 leftFilter = float3x3(
	float3(0.4561, -0.400822, -0.0152161),
	float3(0.500484, -0.0378246, -0.0205971),
	float3(0.176381 , -0.0157589, -0.00546856));
static const float3x3 rightFilter = float3x3(
	float3(-0.0434706, 0.378476, -0.0721527),
	float3(-0.0879388 , 0.73364, -0.112961),
	float3(-0.00155529, -0.0184503, 1.2264));
static const float3 gammaMap = float3(1.6, 0.8, 1.0);
static const float2 cursorOffset = float2(0.0015, 0.0125);
static const float cursorSize = 64.0;

uniform int stereoMode <
	ui_label = "Display Mode";
	ui_tooltip = "3D Output Type";
	ui_type = "combo"; 
	ui_items = "Anaglyph\0Side-by-Side\0Color + Depth\0Horizontal\0Vertical\0Checkerboard\0";
> = 0;

uniform float stereoStrength <
	ui_label = "Stereo Strength";
	ui_tooltip = "Eye Separation";
	ui_type = "slider"; 
	ui_min = 0.0; 
	ui_max = 100.0;
	ui_step = 1.0;
> = 50.0;

uniform float stereoDepth <
	ui_label = "Depth Range";
	ui_tooltip = "Z-Buffer Scaling";
	ui_type = "slider"; 
	ui_min = 0.0; 
	ui_max = 100.0;
	ui_step = 1.0; 
> = 50.0;

uniform float stereoOffset <
	ui_label = "Parallax Overlap";
	ui_tooltip = "Zero Depth Plane";
	ui_type = "slider"; 
	ui_min = 0.0; 
	ui_max = 100.0;
	ui_step = 1.0; 
> = 50.0;

uniform bool swapLeftRight <
#if __RESHADE__ >= 40500
    ui_text = "Press \'+\' to toggle side-by-side mouse cursor.";
#endif
	ui_label = "Swap Left/Right";
	ui_tooltip = "Reverse Eyes";
	ui_category = "Advanced Options";
	ui_category_closed = true;
> = false;

uniform bool showDepth <
	ui_label = "Show Depth Buffer";
	ui_tooltip = "Z-Buffer Debug";
	ui_category = "Advanced Options";
> = false;

uniform bool toggleCursor < 
	source = "key"; 
	keycode = 0xBB; 
	mode = "toggle"; 
>;

uniform float2 mousePosition < 
	source = "mousepoint"; 
>;

float getStereoStrength() {
	return stereoStrength / 100.0 * 0.25 + 0.25;
}

float getStereoDepth() {
	return stereoDepth / 100.0 * 8.0 - 0.25;
}

float getStereoOffset() {
	return (1.0 - stereoOffset / 100.0) / 100.0;
}

float getParallax(float depth) {
	depth = -getStereoDepth() / depth;
	return depth;
}
 
float4 getColor(sampler2D tex, float2 uv) {
	float4 color = tex2Dlod(tex, float4(uv, 0.0, 0.0)).rgba;
	return color;
}

float3 correctColor(float3 original) {
	float3 corrected;
	corrected.r = pow(original.r, 1.0 / gammaMap.r);
	corrected.g = pow(original.g, 1.0 / gammaMap.g);
	corrected.b = pow(original.b, 1.0 / gammaMap.b);
	return corrected;
}

float getDepth(sampler2D tex, float2 uv, bool adjust = true) {
#if RESHADE_DEPTH_INPUT_IS_UPSIDE_DOWN
	uv.y = 1.0 - uv.y;
#endif
	float depth = tex2Dlod(tex, float4(uv, 0.0, 0.0)).r;
#if RESHADE_DEPTH_INPUT_IS_LOGARITHMIC
	depth = (exp(depth * log(1.01)) - 1.0) / 0.01;
#endif
#if RESHADE_DEPTH_INPUT_IS_REVERSED
	depth = 1.0 - depth;
#endif
	if (adjust) depth = 2.0 / (-99.0 * depth + 101.0);
	depth = (2.0 * zNear * zFar) / (zFar + zNear - depth * (zFar - zNear));
	depth /= zFar - zNear;
	return depth;
}

float2 getUV(float2 uv, int horz, int vert) {
	float2 result = uv;
	if (horz == Left_Side) {
		result.x = uv.x * 2.0;
	} else if (horz == Right_Side) {
		result.x = (uv.x - 0.5) * 2.0;
	}
	return result;
}

float3 combineStereoViews(float3 leftColor, float3 rightColor, float4 pixelPosition, int horz, int vert) {
	float3 result = float3(1, 1, 1);
	int2 currentPixel = int2(pixelPosition.xy);	
	if (swapLeftRight) {
		float3 tempColor = leftColor;
		leftColor = rightColor;
		rightColor = tempColor;
	}
	if (stereoMode == Anaglyph) {
		result = saturate(mul(leftColor, leftFilter)) + saturate(mul(rightColor,rightFilter));
		result = correctColor(result);
	} else if (stereoMode == Side_By_Side) {
		if (horz == Left_Side) result = leftColor;
		else result = rightColor;
	} else if (stereoMode == Horizontal) {
		if (currentPixel.y % 2 == 0) result = leftColor;
		else result = rightColor;
	} else if (stereoMode == Vertical) {
		if (currentPixel.x % 2 == 0) result = leftColor;
		else result = rightColor;
	} else if (stereoMode == Checkerboard) {
		if (currentPixel.x % 2 == 0 && currentPixel.y % 2 == 0) result = leftColor;
		else if (currentPixel.x % 2 == 1 && currentPixel.y % 2 == 1) result = leftColor;
		else result = rightColor;
	}
	return result;
}

float3 generateStereoImage(float2 uv, float4 pixelPosition, int horz, int vert) {
	float minDepthLeft = 1.0;
	float minDepthRight = 1.0;
	float parallaxLeft = 0.0;
	float parallaxRight = 0.0;
	float3 colorLeft = float3(0, 0, 0);
	float3 colorRight = float3(0, 0, 0);
	float2 sampleUV = float2(0, 0);

	static const float gutter = 0.001;
	float2 minUV = float2(gutter, 0.0);
	float2 maxUV = float2(1.0 - gutter, 1.0);

	float aspectRatio = (float)BUFFER_WIDTH / BUFFER_HEIGHT;

	for (int i = 0; i < sampleCount; ++i) {
		sampleUV.x = (depthSamples[i] * getStereoStrength() / aspectRatio) / stereoScale + getStereoOffset();
		minDepthLeft = min(minDepthLeft, getDepth(depthSampler, clamp(uv + sampleUV, minUV, maxUV)));
		minDepthRight = min(minDepthRight, getDepth(depthSampler, clamp(uv - sampleUV, minUV, maxUV)));
	}

	parallaxLeft = (getStereoStrength() / aspectRatio * getParallax(minDepthLeft)) / stereoScale + getStereoOffset();
	parallaxRight = (getStereoStrength() / aspectRatio * getParallax(minDepthRight)) / stereoScale + getStereoOffset();

	colorLeft = getColor(screenSampler, clamp(uv + float2(parallaxLeft, 0.0), minUV, maxUV)).rgb;
	colorRight = getColor(screenSampler, clamp(uv  - float2(parallaxRight, 0.0), minUV, maxUV)).rgb;

	return combineStereoViews(colorLeft, colorRight, pixelPosition, horz, vert);
}

[shader("pixel")]
float4 StereoPS(float4 pixelPosition : SV_Position, float2 uv : TEXCOORD0) : SV_Target {
	float4 color = float4(0, 0, 0, 1);
	float2 screenSize = float2(BUFFER_WIDTH, BUFFER_HEIGHT);
	int currentSide = pixelPosition.x < BUFFER_WIDTH * 0.5 ? Left_Side : Right_Side;
	if (stereoMode == Side_By_Side) {
		color.rgb = generateStereoImage(getUV(uv, currentSide, Both_Sides), pixelPosition, currentSide, Both_Sides);
		float2 cursorCoord = mousePosition / float2(BUFFER_WIDTH, BUFFER_HEIGHT) * float2(0.5, 1.0) + 
			currentSide * float2(0.5, 0.0);
		float2 cursorDim = float2(cursorSize / screenSize.x, cursorSize / screenSize.y);
		if (toggleCursor && abs(uv.x - cursorCoord.x) < cursorDim.x  && 
			abs(uv.y - cursorCoord.y) < cursorDim.y) {
			float4 iconColor = tex2D(cursorSampler, float2(((uv.x - cursorOffset.x) / cursorDim.x) * 2.0, 
				(uv.y - cursorOffset.y) / cursorDim.y) - (cursorCoord / cursorDim) * float2(2, 1)  + 
				float2(0.5 + cursorOffset.x, 0.5 + cursorOffset.y));
			if (iconColor.a > 0.0) iconColor.rgb /= iconColor.a;
			color.rgb = lerp(color.rgb, iconColor.rgb, iconColor.a);
		}
	} else if (stereoMode == Color_Plus_Depth) {
		float2 scaled = uv * float2(1.0, 2.0) - float2(0.0, 0.5);
		if (all(scaled > float2(0, 0)) && all(scaled < float2(1, 1))) {
			if (currentSide == Left_Side) {
				color.rgb = getColor(screenSampler, getUV(scaled, currentSide, Both_Sides)).rgb;
			} else {
				float depth = 1.0 - getDepth(depthSampler, getUV(scaled, currentSide, Both_Sides), false);
				color.rgb = depth.rrr;
			}
		}
	} else {
		color.rgb = generateStereoImage(uv, pixelPosition, Both_Sides, Both_Sides);
	}

	if (showDepth) {
		if (currentSide == Left_Side) {
			color.rgb = getColor(screenSampler, uv).rgb;
		} else {
			float depth = 1.0 - getDepth(depthSampler, uv, false);
			color.rgb = depth.rrr;
		}
		return color;
	}
	
	return color;
}

technique Rendepth < ui_tooltip = "Stereoscopic 2D-to-3D Conversion"; >{
	pass StereoPass {
		VertexShader = PostProcessVS;
		PixelShader = StereoPS;
	}
}