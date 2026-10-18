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

#define Monoscopic 0
#define Anaglyph_Accurate 1
#define Anaglyph_Vivid 2
#define Side_By_Side 3
#define Top_Over_Bottom 4
#define Color_Plus_Depth 5
#define Free_View 6
#define Horizontal_Interlace 7
#define Vertical_Interlace 8
#define Checkerboard 9

#define Left_Side 0
#define Right_Side 1
#define Top_Side 2
#define Bottom_Side 3
#define Both_Sides 4

static const float zNear = 0.1;
static const float zFar = 100.0;
static const float stereoScale = 25000.0;
static const float depthSamples[9] = { -0.5, -0.25, -0.125, 0.0, 0.25, 0.3, 0.5, 0.75, 1.0 };
static const int sampleCount = 9;
static const float searchDepth = 0.02;
static const float originalDepthSamples[5] = { 0.125, 0.250, 0.375, 0.500, 0.625 };
static const int originalSampleCount = 5;
static const float3x3 leftAccurate = float3x3(
	float3(0.439, 0.0, 0.0),
	float3(0.447, 0.0, 0.0),
	float3(0.148, 0.0, 0.0));
static const float3x3 rightAccurate = float3x3(
	float3(0.0, 0.095, -0.018),
	float3(0.0, 0.934, -0.028),
	float3(0.0, -0.005, 1.057));
static const float3x3 leftVivid = float3x3(
	float3(0.4561, -0.400822, -0.0152161),
	float3(0.500484, -0.0378246, -0.0205971),
	float3(0.176381 , -0.0157589, -0.00546856));
static const float3x3 rightVivid = float3x3(
	float3(-0.0434706, 0.378476, -0.0721527),
	float3(-0.0879388 , 0.73364, -0.112961),
	float3(-0.00155529, -0.0184503, 1.2264));
static const float3 gammaMap = float3(1.10, 1.05, 1.05);
static const float2 cursorOffset = float2(0.0015, 0.0125);
static const float cursorSize = 512.0;
static const float2 screenSize = float2(BUFFER_WIDTH, BUFFER_HEIGHT);
static const float aspectRatio = (float)BUFFER_WIDTH / BUFFER_HEIGHT;
static const float2 cursorDim = float2(cursorSize / screenSize.x, cursorSize / screenSize.y);
static const float gutter = 0.001;
static const float2 minUV = float2(gutter, 0.0);
static const float2 maxUV = float2(1.0 - gutter, 1.0);
static const int letterboxStart = 5;
static const int letterboxSize = 8;

texture2D screenTexture : COLOR;
sampler2D screenSampler {
	Texture = screenTexture;
	AddressU = CLAMP;
	AddressV = CLAMP;
};

texture2D depthTexture : DEPTH;
sampler2D depthSampler {
	Texture = depthTexture;
	AddressU = BORDER;
	AddressV = BORDER;
};

texture2D cursorTexture < source = "Cursor_512px.png"; > {
	Format = RGBA8;
	MipLevels = 7;
	Width = 512;
	Height = 512;
};
sampler2D cursorSampler {
	Texture = cursorTexture;
	AddressU = CLAMP;
	AddressV = CLAMP;
};

uniform int stereoMode <
	ui_label = "Display Mode";
	ui_tooltip = "3D Output Type";
	ui_type = "combo"; 
	ui_items = "Stereo 3D Disabled\0Accurate Anaglyph\0Vivid Anaglyph\0Side-by-Side\0Top-Bottom\0Color+Depth\0Free-View\0Horizontal\0Vertical\0Checkerboard\0";
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

uniform bool anaglyphBoost <
#if __RESHADE__ >= 40500
	ui_text = "Press \'+\' to toggle side-by-side mouse cursor.\nPress \'-\' to toggle 2D mode for unsupported scenes.";
#endif
	ui_label = "Anaglyph Boost";
	ui_tooltip = "Saturate Colors for Anaglyph";
	ui_category = "Advanced Options";
	ui_category_closed = true;
> = false;

uniform bool letterboxFix <
	ui_label = "Letterbox Fix";
	ui_tooltip = "Reposition Depthmap Axis";
	ui_category = "Advanced Options";
> = false;

uniform bool disableDepthAA <
    ui_label = "Disable Depth AA";
    ui_tooltip = "Disable Depth AA and Stereo Reconstruction";
    ui_category = "Advanced Options";
> = false;

uniform bool disableHotkeys <
	ui_label = "Disable Hotkeys";
	ui_tooltip = "Fix Key Binding Conflicts";
	ui_category = "Advanced Options";
> = false;

uniform bool swapLeftRight <
	ui_label = "Swap Left/Right";
	ui_tooltip = "Display Eyes Reversed";
	ui_category = "Advanced Options";
> = false;

uniform bool showDepth <
	ui_label = "View Depth Buffer";
	ui_tooltip = "Z-Buffer Split-Screen View";
	ui_category = "Advanced Options";
> = false;

uniform bool toggleCursor < 
	source = "key"; 
	keycode = 0xBB; 
	mode = "toggle"; 
>;

uniform bool toggleMono < 
	source = "key"; 
	keycode = 0xBD; 
	mode = "toggle"; 
>;

uniform float2 mousePosition < 
	source = "mousepoint"; 
>;

float getStereoStrength() {
	return stereoStrength / 100.0 * 2.0;
}

float getStereoDepth() {
	return stereoDepth / 100.0 * 2.0;
}

float getStereoOffset() {
	return (1.0 - stereoOffset / 100.0) / 50.0;
}

float getParallax(float depth) {
	return -getStereoDepth() / depth;
}
 
float4 getColor(sampler2D tex, float2 uv) {
	float4 color = tex2D(tex, uv).rgba;
	if (uv.x <= 0.0 || uv.x >= 1.0 || 
		uv.y <= 0.0 || uv.y >= 1.0) 
		color.rgb = float3(0, 0, 0);
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
	float depth = tex2D(tex, uv).r;
#if RESHADE_DEPTH_INPUT_IS_LOGARITHMIC
	depth = (exp(depth * log(1.01)) - 1.0) / 0.01;
#endif
#if RESHADE_DEPTH_INPUT_IS_REVERSED == 0
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
	} else if (vert == Top_Side) {
		result.y = uv.y * 2.0;
	} else if (vert == Bottom_Side) {
		result.y = (uv.y - 0.5) * 2.0;
	}
	return result;
}

float2 clampEdge(float2 inUV) {
	const float edgeStretch = 0.333;
	if (inUV.x < minUV.x) inUV.x = (minUV.x - inUV.x) * edgeStretch;
	if (inUV.x > maxUV.x) inUV.x = maxUV.x + (maxUV.x - inUV.x) * edgeStretch;
	return clamp(inUV, minUV, maxUV);
}

float getDepthAA(float2 uv) {
	const int blurSamples = 4;
	const float blurRadius = 1.0;
	const float blurSigma = blurSamples / 3.0;
	const float edgeScale = 0.25;
	const float centerDepth = getDepth(depthSampler, clampEdge(uv));
	const float2 texel = float2(BUFFER_RCP_WIDTH, BUFFER_RCP_HEIGHT);

	const float topLeft = getDepth(depthSampler, clampEdge(uv + float2(-texel.x, -texel.y)));
	const float top = getDepth(depthSampler, clampEdge(uv + float2(0.0, -texel.y)));
	const float topRight = getDepth(depthSampler, clampEdge(uv + float2(texel.x, -texel.y)));
	const float left = getDepth(depthSampler, clampEdge(uv + float2(-texel.x, 0.0)));
	const float right = getDepth(depthSampler, clampEdge(uv + float2(texel.x, 0.0)));
	const float bottomLeft = getDepth(depthSampler, clampEdge(uv + float2(-texel.x, texel.y)));
	const float bottom = getDepth(depthSampler, clampEdge(uv + float2(0.0, texel.y)));
	const float bottomRight = getDepth(depthSampler, clampEdge(uv + float2(texel.x, texel.y)));

	const float dx = ((topLeft + 2.0 * left + bottomLeft) - (topRight + 2.0 * right + bottomRight)) * 0.25;
	const float dy = ((topLeft + 2.0 * top + topRight) - (bottomLeft + 2.0 * bottom + bottomRight)) * 0.25;
	const float neighborMin = min(min(min(topLeft, top), min(topRight, left)),
		min(min(right, bottomLeft), min(bottom, bottomRight)));
	const float neighborMax = max(max(max(topLeft, top), max(topRight, left)),
		max(max(right, bottomLeft), max(bottom, bottomRight)));
	const float despeckled = clamp(centerDepth, neighborMin, neighborMax);
	const float neighborAverage = (topLeft + top + topRight + left
		+ right + bottomLeft + bottom + bottomRight) * 0.125;
	const float curvature = abs(despeckled - neighborAverage);

	const float2 gradient = float2(dx, dy);
	const float slope = length(gradient);
	const float2 direction = slope > 0.000001 ? gradient / slope : float2(0.0, 1.0);
	const float2 tangent = float2(-direction.y, direction.x) * texel * blurRadius;

	float depth = 0.0;
	float weightSum = 0.0;
	[unroll]
	for (int i = -blurSamples; i <= blurSamples; ++i) {
		const float weight = exp(-(i * i) / (2.0 * blurSigma * blurSigma));
		depth += getDepth(depthSampler, clampEdge(uv + tangent * i)) * weight;
		weightSum += weight;
	}
	depth /= weightSum;

	const float edge = saturate(curvature / (max(despeckled, 0.001) * edgeScale));
	return lerp(despeckled, depth, edge);
}

float getMaskDepth(float2 uv) {
    if (disableDepthAA) return getDepth(depthSampler, uv);
	return getDepthAA(uv);
}

float3 getStereoColor(float2 uv) {
	const float pixelX = uv.x * BUFFER_WIDTH - 0.5;
	const float baseX = floor(pixelX);
	const float t = pixelX - baseX;
	const float2 centerUV = float2((baseX + 0.5) * BUFFER_RCP_WIDTH, uv.y);
	const float3 c0 = getColor(screenSampler, clampEdge(centerUV - float2(BUFFER_RCP_WIDTH, 0.0))).rgb;
	const float3 c1 = getColor(screenSampler, clampEdge(centerUV)).rgb;
	const float3 c2 = getColor(screenSampler, clampEdge(centerUV + float2(BUFFER_RCP_WIDTH, 0.0))).rgb;
	const float3 c3 = getColor(screenSampler, clampEdge(centerUV + float2(2.0 * BUFFER_RCP_WIDTH, 0.0))).rgb;
	const float t2 = t * t;
	const float t3 = t2 * t;
	const float3 color = 0.5 * (2.0 * c1 + (c2 - c0) * t
		+ (2.0 * c0 - 5.0 * c1 + 4.0 * c2 - c3) * t2
		+ (3.0 * c1 - c0 - 3.0 * c2 + c3) * t3);
	return clamp(color, min(c1, c2), max(c1, c2));
}

float3 combineStereoViews(float3 leftColor, float3 rightColor, float4 pixelPosition, int horz, int vert) {
	float3 result = float3(1, 1, 1);
	int2 currentPixel = int2(pixelPosition.xy);	
	if (swapLeftRight) {
		float3 tempColor = leftColor;
		leftColor = rightColor;
		rightColor = tempColor;
	}
	if (stereoMode == Anaglyph_Accurate) {
		result = saturate(mul(leftColor, leftAccurate)) + saturate(mul(rightColor, rightAccurate));
		if (anaglyphBoost) result = correctColor(result);
	} else if (stereoMode == Anaglyph_Vivid) {
		result = saturate(mul(leftColor, leftVivid)) + saturate(mul(rightColor, rightVivid));
		if (anaglyphBoost) result = correctColor(result);
	} else if (stereoMode == Side_By_Side) {
		if (horz == Left_Side) result = leftColor;
		else result = rightColor;
	} else if (stereoMode == Top_Over_Bottom) {
		if (vert == Top_Side) result = leftColor;
		else result = rightColor;
	} else if (stereoMode == Free_View) {
		if (horz == Left_Side) result = leftColor;
		else result = rightColor;
	} else if (stereoMode == Horizontal_Interlace) {
		if (currentPixel.y % 2.0 == 0.0) result = leftColor;
		else result = rightColor;
	} else if (stereoMode == Vertical_Interlace) {
		if (currentPixel.x % 2.0 == 0.0) result = leftColor;
		else result = rightColor;
	} else if (stereoMode == Checkerboard) {
		if (currentPixel.x % 2.0 == 0.0 && currentPixel.y % 2.0 == 0.0) result = leftColor;
		else if (currentPixel.x % 2.0 == 1.0 && currentPixel.y % 2.0 == 1.0) result = leftColor;
		else result = rightColor;
	}
	return result;
}

float letterboxAdjust(bool pillar) {
	const float blackThreshold = 0.01;
	const int sampleStart = 2;
	const int letterboxProbeCount = 4;
	int edgeBlackCount = 0;
	for (int i = sampleStart; i < sampleStart + letterboxProbeCount; i++) {
		float2 samplePoint = pillar ? float2(letterboxSize - 1, i) : float2(i, letterboxSize - 1);
		float3 color = getColor(screenSampler, samplePoint / letterboxSize).rgb;
		if (max(max(color.r, color.g), color.b) <= blackThreshold) edgeBlackCount++;
	}
	if (edgeBlackCount < 3) return 0.0;

	for (int j = letterboxSize - 2; j >= letterboxStart; j--) {
		int contentCount = 0;
		for (int i = sampleStart; i < sampleStart + letterboxProbeCount; i++) {
			float2 samplePoint = pillar ? float2(j, i) : float2(i, j);
			float3 color = getColor(screenSampler, samplePoint / letterboxSize).rgb;
			if (max(max(color.r, color.g), color.b) > blackThreshold) contentCount++;
		}
		if (contentCount >= 2)
			return clamp((letterboxStart - j + (pillar ? 1 : 0)) / (float)letterboxSize, -1.0, 1.0);
	}
	return 0.0;
}

float3 generateOriginalStereoImage(float2 uv, float4 pixelPosition, int horz, int vert, float2 displace) {
	const float centerDepth = getDepth(depthSampler, clampEdge(uv + displace));
	float minDepthLeft = centerDepth;
	float minDepthRight = centerDepth;
	float2 sampleUV = float2(0, 0);

	for (int i = 0; i < originalSampleCount; ++i) {
		sampleUV.x = (originalDepthSamples[i] * getStereoStrength() / aspectRatio) / stereoScale + getStereoOffset() / aspectRatio;
		minDepthLeft = min(minDepthLeft, getDepth(depthSampler, clampEdge(uv + displace + sampleUV)));
		minDepthRight = min(minDepthRight, getDepth(depthSampler, clampEdge(uv + displace - sampleUV)));
	}

	float parallaxLeft = (getStereoStrength() / aspectRatio * getParallax(minDepthLeft)) / stereoScale + getStereoOffset() / aspectRatio;
	float parallaxRight = (getStereoStrength() / aspectRatio * getParallax(minDepthRight)) / stereoScale + getStereoOffset() / aspectRatio;

	if (toggleMono && !disableHotkeys) {
		parallaxLeft = 0.0;
		parallaxRight = 0.0;
	}

	float3 colorLeft = getColor(screenSampler, clampEdge(uv + float2(parallaxLeft, 0.0))).rgb;
	float3 colorRight = getColor(screenSampler, clampEdge(uv - float2(parallaxRight, 0.0))).rgb;

	return combineStereoViews(colorLeft, colorRight, pixelPosition, horz, vert);
}

float3 generateReconstructedStereoImage(float2 uv, float4 pixelPosition, int horz, int vert, float2 displace) {
	if (toggleMono && !disableHotkeys) {
		float3 monoColor = getColor(screenSampler, clampEdge(uv)).rgb;
		return combineStereoViews(monoColor, monoColor, pixelPosition, horz, vert);
	}

	const float offset = getStereoOffset() / aspectRatio;
	const float2 leftUV = uv + float2(offset, 0.0);
	const float2 rightUV = uv - float2(offset, 0.0);
	float minDepthLeft = getMaskDepth(clampEdge(leftUV + displace));
	float minDepthRight = getMaskDepth(clampEdge(rightUV + displace));

	const float searchSpan = (getStereoStrength() / aspectRatio * getParallax(searchDepth)) / stereoScale;
	float2 sampleUV = float2(0, 0);
	for (int i = 0; i < sampleCount; ++i) {
		sampleUV.x = depthSamples[i] * searchSpan;
		minDepthLeft = min(minDepthLeft, getMaskDepth(clampEdge(leftUV + displace + sampleUV)));
		minDepthRight = min(minDepthRight, getMaskDepth(clampEdge(rightUV + displace - sampleUV)));
	}

	float parallaxLeft = (getStereoStrength() / aspectRatio * getParallax(minDepthLeft)) / stereoScale;
	float parallaxRight = (getStereoStrength() / aspectRatio * getParallax(minDepthRight)) / stereoScale;

	float3 colorLeft = getStereoColor(leftUV + float2(parallaxLeft, 0.0));
	float3 colorRight = getStereoColor(rightUV - float2(parallaxRight, 0.0));

	return combineStereoViews(colorLeft, colorRight, pixelPosition, horz, vert);
}

float3 generateStereoImage(float2 uv, float4 pixelPosition, int horz, int vert, float2 displace) {
    if (disableDepthAA) return generateOriginalStereoImage(uv, pixelPosition, horz, vert, displace);
	return generateReconstructedStereoImage(uv, pixelPosition, horz, vert, displace);
}

float2 iconUV(float2 uv, float2 cursorCoord) {
	return float2(((uv.x - cursorOffset.x) / cursorDim.x) * 2.0, 
		(uv.y - cursorOffset.y) / cursorDim.y) - (cursorCoord / cursorDim) * float2(2, 1) + 
		float2(0.5 + cursorOffset.x, 0.5 + cursorOffset.y);
}

[shader("pixel")]
float4 StereoPS(float4 pixelPosition : SV_Position, float2 uv : TEXCOORD0) : SV_Target {
	float4 color = float4(0, 0, 0, 1);
	int horizontalSide = pixelPosition.x < screenSize.x * 0.5 ? Left_Side : Right_Side;
	int verticalSide = pixelPosition.y < screenSize.y * 0.5 ? Top_Side : Bottom_Side;
	float2 cursorCoord = float2(0, 0);

	float2 letterboxOffset = float2(0, 0);
	if (letterboxFix) letterboxOffset = float2(letterboxAdjust(true), letterboxAdjust(false));

	if (stereoMode == Monoscopic) {
		color.rgb = getColor(screenSampler, uv).rgb;
	} else if (stereoMode == Side_By_Side) {
		color.rgb = generateStereoImage(getUV(uv, horizontalSide, Both_Sides), pixelPosition, horizontalSide, Both_Sides, letterboxOffset);
		cursorCoord = mousePosition / screenSize * float2(0.5, 1.0) + horizontalSide * float2(0.5, 0.0);
	} else if (stereoMode == Top_Over_Bottom) {
		color.rgb = generateStereoImage(getUV(uv, Both_Sides, verticalSide), pixelPosition, Both_Sides, verticalSide, letterboxOffset);
		cursorCoord = mousePosition / screenSize * float2(1.0, 0.5) + (verticalSide - 2) * float2(0.0, 0.5);
	} else if (stereoMode == Color_Plus_Depth) {
		if (horizontalSide == Left_Side) {
			color.rgb = getColor(screenSampler, uv).rgb;
		} else {
			float depth = 1.0 - getDepth(depthSampler, uv + letterboxOffset, false);
			color.rgb = depth.rrr;
		}
	} else if (stereoMode == Free_View) {
		float2 freeUV = getUV(uv, horizontalSide, Both_Sides);
		freeUV.y = freeUV.y * 2.0 - 0.5;
		color.rgb = generateStereoImage(freeUV, pixelPosition, horizontalSide, Both_Sides, letterboxOffset);
		cursorCoord = mousePosition / screenSize * float2(0.5, 1.0) + horizontalSide * float2(0.5, 0.0);
		cursorCoord.y = cursorCoord.y * 0.5 + 0.25;
	} else {
		color.rgb = generateStereoImage(uv, pixelPosition, Both_Sides, Both_Sides, letterboxOffset);
	}

	if ((toggleCursor && !disableHotkeys) && (stereoMode == Side_By_Side || stereoMode == Top_Over_Bottom || stereoMode == Free_View) &&
			abs(uv.x - cursorCoord.x) < cursorDim.x && abs(uv.y - cursorCoord.y) < cursorDim.y) {
		float2 iconCoords = iconUV(uv, cursorCoord);
		if (stereoMode == Free_View) iconCoords.y = iconCoords.y * 2.0 - 0.5;
		float4 iconColor = tex2D(cursorSampler, iconCoords);
		if (iconColor.a > 0.0) iconColor.rgb /= iconColor.a;
		color.rgb = lerp(color.rgb, iconColor.rgb, iconColor.a);
	}

	if (showDepth) {
		if (horizontalSide == Left_Side) {
			color.rgb = getColor(screenSampler, uv).rgb;
		} else {
			float depth = 1.0 - getDepth(depthSampler, uv + letterboxOffset, false);
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