#include "ReShade.fxh"

uniform float Vibrance <
    ui_type = "slider";
    ui_min = -1.0; ui_max = 2.0;
    ui_step = 0.01;
    ui_label = "Vibrance";
    ui_tooltip = "0 = no change. Positive boosts muted colors more than saturated colors.";
> = 0.0; // neutral baseline

uniform float GlobalSat <
    ui_type = "slider";
    ui_min = 0.0; ui_max = 2.0;
    ui_step = 0.01;
    ui_label = "Global Saturation";
    ui_tooltip = "1 = no change.";
> = 1.0; // neutral baseline

uniform float MidtoneVibranceBoost <
    ui_type = "slider";
    ui_min = 0.0; ui_max = 2.0;
    ui_step = 0.01;
    ui_label = "Midtone Vibrance Boost";
    ui_tooltip = "0 = no change. Adds extra vibrance in midtones only.";
> = 0.0; // neutral baseline

uniform float HighlightDesat <
    ui_type = "slider";
    ui_min = 0.0; ui_max = 10.0;
    ui_step = 0.05;
    ui_label = "Highlight Desaturation";
    ui_tooltip = "0 = no change.";
> = 0.0; // neutral baseline

uniform float HighlightStart <
    ui_type = "slider";
    ui_min = 0.20; ui_max = 0.95;
    ui_step = 0.01;
    ui_label = "Highlight Start";
> = 0.45;

uniform float HighlightEnd <
    ui_type = "slider";
    ui_min = 0.30; ui_max = 1.20;
    ui_step = 0.01;
    ui_label = "Highlight End";
> = 0.90;

uniform float ShadowDesat <
    ui_type = "slider";
    ui_min = 0.0; ui_max = 2.0;
    ui_step = 0.01;
    ui_label = "Shadow Desaturation";
    ui_tooltip = "0 = no change.";
> = 0.0; // neutral baseline

uniform float SkinToneProtection <
    ui_type = "slider";
    ui_min = 0.0; ui_max = 1.0;
    ui_step = 0.01;
    ui_label = "Skin Tone Protection";
    ui_tooltip = "0 = disabled (no change).";
> = 0.0; // neutral baseline

uniform float AntiNeonCompression <
    ui_type = "slider";
    ui_min = 0.0; ui_max = 1.0;
    ui_step = 0.01;
    ui_label = "Anti-Neon Compression";
    ui_tooltip = "0 = disabled (identity-safe baseline).";
> = 0.0; // neutral baseline

texture BackBufferTex : COLOR;
sampler2D BackBufferSampler { Texture = BackBufferTex; };

float Luma709(float3 c) { return dot(c, float3(0.2126, 0.7152, 0.0722)); }

float3 RGBtoHSV(float3 c)
{
    float4 K = float4(0.0, -1.0/3.0, 2.0/3.0, -1.0);
    float4 p = lerp(float4(c.bg, K.wz), float4(c.gb, K.xy), step(c.b, c.g));
    float4 q = lerp(float4(p.xyw, c.r), float4(c.r, p.yzx), step(p.x, c.r));
    float d = q.x - min(q.w, q.y);
    float e = 1e-10;
    return float3(abs(q.z + (q.w - q.y) / (6.0 * d + e)), d / (q.x + e), q.x);
}

float3 HSVtoRGB(float3 c)
{
    float4 K = float4(1.0, 2.0/3.0, 1.0/3.0, 3.0);
    float3 p = abs(frac(c.xxx + K.xyz) * 6.0 - K.www);
    return c.z * lerp(K.xxx, saturate(p - K.xxx), c.y);
}

float SkinMask(float hue)
{
    float d = min(abs(hue - 0.07), 1.0 - abs(hue - 0.07));
    return 1.0 - smoothstep(0.04, 0.16, d);
}

float ApplyVibranceToSat(float s, float vib)
{
    float muted = 1.0 - saturate(s);
    muted *= muted; // stronger effect on very muted colors

    float factor = (vib >= 0.0)
        ? (1.0 + vib * muted)
        : (1.0 + vib * (0.35 + 0.65 * muted));

    return s * max(factor, 0.0);
}

float4 PS_FilmVibrance(float4 pos : SV_Position, float2 uv : TEXCOORD) : SV_Target
{
    float3 src = tex2D(BackBufferSampler, uv).rgb; // keep in backbuffer space (do NOT linearize for HSV)
    float3 hsv = RGBtoHSV(saturate(src));

    float h  = hsv.x;
    float s0 = hsv.y;
    float v  = hsv.z; // value channel for tonal masks in display-referred space

    float hi  = smoothstep(HighlightStart, max(HighlightEnd, HighlightStart + 1e-3), v);
    float sh  = 1.0 - smoothstep(0.02, 0.22, v);
    float mid = smoothstep(0.12, 0.40, v) * (1.0 - smoothstep(0.55, 0.90, v));

    // vibrance with optional midtone weighting
    float vibTone = Vibrance * (1.0 + MidtoneVibranceBoost * mid);
    float s = ApplyVibranceToSat(s0, vibTone);

    // global sat
    s *= GlobalSat;

    // shoulder/toe chroma compression
    s *= exp2(-HighlightDesat * hi);
    s *= exp2(-ShadowDesat * sh);

    // optional skin protection
    if (SkinToneProtection > 0.0)
    {
        float skin = SkinMask(h);
        s = lerp(s, s0 + (s - s0) * (1.0 - SkinToneProtection), skin);
    }

    // optional anti-neon compression (disabled at baseline)
    if (AntiNeonCompression > 0.0)
    {
        s = s / (1.0 + AntiNeonCompression * s);
    }

    hsv.y = saturate(s);
    float3 outCol = HSVtoRGB(hsv);

    return float4(outCol, 1.0);
}

technique FilmVibrance_IdentitySafe
{
    pass
    {
        VertexShader = PostProcessVS;
        PixelShader  = PS_FilmVibrance;
    }
}