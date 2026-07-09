#include <metal_stdlib>
using namespace metal;

/// 纸张材质着色器：分层 value-noise (fbm) + 域扭曲做出有机纤维颗粒，各向异性拉伸做宣纸纤维方向感，
/// 低频扭曲做羊皮纸做旧斑驳，径向渐晕收边。所有噪声都在 0~1 的 uv 空间取样——与视图尺寸无关，
/// 分辨率变化（旋转/分屏）只需换个像素尺寸重渲染一次，纹理"密度"本身不会跟着变粗变细。

struct VertexOut {
    float4 position [[position]];
    float2 uv;
};

/// 三角形覆盖全屏，免顶点缓冲。
vertex VertexOut paper_vertex(uint vertexID [[vertex_id]]) {
    float2 positions[3] = { float2(-1.0, -1.0), float2(3.0, -1.0), float2(-1.0, 3.0) };
    VertexOut out;
    float2 p = positions[vertexID];
    out.position = float4(p, 0.0, 1.0);
    out.uv = float2((p.x + 1.0) * 0.5, 1.0 - (p.y + 1.0) * 0.5);
    return out;
}

/// 每种纸张样式的着色器输入；字段顺序/类型需与 Swift 侧 `PaperShaderParams` 严格一致。
struct PaperParams {
    float4 baseColor;         // 纸底色，线性 0~1 RGBA
    float grainIntensity;     // 细颗粒强度（对应旧 noiseOpacity，量级放大后仍克制）
    float grainScale;         // 颗粒频率（uv 空间，故与分辨率无关）
    float fiberDirectionality;// 0=各向同性细颗粒，1=宣纸式方向性纤维条纹
    float fiberAngle;         // 纤维方向角（弧度）
    float warmth;             // 做旧/暖色强度（羊皮纸边缘发黄发深）
    float vignetteStrength;   // 径向收边强度
    float aspect;             // 宽/高，用于把半径校正成视觉上的正圆
    float seed;               // 按样式区分噪声相位，避免四种纸看起来像同一张贴图换色
};

static inline float hash21(float2 p) {
    p = fract(p * float2(123.34, 456.21));
    p += dot(p, p + 45.32);
    return fract(p.x * p.y);
}

static inline float valueNoise(float2 p) {
    float2 i = floor(p);
    float2 f = fract(p);
    float a = hash21(i);
    float b = hash21(i + float2(1.0, 0.0));
    float c = hash21(i + float2(0.0, 1.0));
    float d = hash21(i + float2(1.0, 1.0));
    float2 u = f * f * (3.0 - 2.0 * f);
    return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

static inline float2 rotate(float2 p, float theta) {
    float c = cos(theta);
    float s = sin(theta);
    return float2(c * p.x - s * p.y, s * p.x + c * p.y);
}

/// 分层噪声：每一层旋转+倍频，破坏网格感，做出有机纹理。
static inline float fbm(float2 p, int octaves) {
    float value = 0.0;
    float amplitude = 0.5;
    for (int i = 0; i < octaves; i++) {
        value += amplitude * valueNoise(p);
        p = rotate(p, 2.4) * 2.02;
        amplitude *= 0.5;
    }
    return value;
}

fragment float4 paper_fragment(VertexOut in [[stage_in]],
                                constant PaperParams &p [[buffer(0)]]) {
    float2 uv = in.uv;
    // 按宽高比校正，让噪声格与渐晕在物理尺寸上是"圆"的，不会在长边被压扁/拉伸。
    float2 uvCorrected = float2((uv.x - 0.5) * p.aspect, uv.y - 0.5);
    float radius = length(uvCorrected);

    // 域扭曲：先用一层低频 fbm 位移采样坐标，避免规则噪声网格的"人工感"。
    float2 np = float2(uv.x * p.aspect, uv.y) * p.grainScale + p.seed;
    float2 warpVec = float2(fbm(np * 0.5, 3), fbm(np * 0.5 + float2(19.0, 7.0), 3)) - 0.5;
    float2 warped = np + warpVec * 0.9;

    // 各向同性细颗粒（素笺/横线信纸/羊皮纸的基础纹理）。
    float fineGrain = fbm(warped, 4) - 0.5;

    // 各向异性纤维条纹（宣纸）：沿纤维方向旋转后压缩一轴，做出拉长的条状纤维。
    float2 fiberSpace = rotate(np, p.fiberAngle);
    float2 stretched = float2(fiberSpace.x * 0.12, fiberSpace.y);
    float fiberGrain = fbm(stretched, 4) - 0.5;

    float grain = mix(fineGrain, fiberGrain, p.fiberDirectionality);

    // 低频斑驳做旧（羊皮纸），频率远低于细颗粒。
    float mottle = fbm(np * 0.16 + p.seed * 3.3, 3) - 0.5;

    // 书写区（页面中心）保持克制、克制变化往边缘推：中心 falloff 越低，颗粒/斑驳越弱。
    float centerFalloff = smoothstep(0.12, 0.62, radius);

    float grainAmt = p.grainIntensity * mix(0.3, 1.0, centerFalloff);
    float mottleAmt = p.warmth * mottle * mix(0.35, 1.0, centerFalloff);

    float3 color = p.baseColor.rgb;
    color += grain * grainAmt * 0.16;
    color += mottleAmt * 0.11;

    // 做旧暖色偏移：越靠边缘、warmth 越大，越往深棕靠。
    float agingAmt = p.warmth * smoothstep(0.32, 0.95, radius) * 0.14;
    float3 agingTarget = color * float3(0.72, 0.55, 0.34);
    color = mix(color, agingTarget, agingAmt);

    // 径向收边渐晕。
    float vig = smoothstep(0.38, 1.05, radius);
    color *= 1.0 - vig * p.vignetteStrength;

    return float4(clamp(color, 0.0, 1.0), 1.0);
}
