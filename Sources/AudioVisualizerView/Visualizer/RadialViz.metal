#include <metal_stdlib>
using namespace metal;
#include "ShaderHeaders.h"

struct VertexIn {
    vector_float2 pos;
};

struct FragmentUniforms {
    float time;
    float screen_width;
    float screen_height;
    float screen_scale;
};

struct VertexOut {
    float4 pos [[position]];
    float4 color;
};

float3 palette(float t) {
    float3 a = float3(0.738, 0.870, 0.870);
    float3 b = float3(0.228, 0.500, 0.500);
    float3 c = float3(1.0, 1.0, 1.0);
    float3 d = float3(0.000, 0.333, 0.667);

    return a + b * cos(6.28318 * (c * t + d));
}

vertex VertexOut radial_viz_vertex(const device VertexIn *vertices [[buffer(0)]], unsigned int vid [[vertex_id]]) {
    VertexOut in;
    in.pos = {vertices[vid].pos.x, vertices[vid].pos.y, 0, 1};
    return in;
}

struct LiveCodeUniforms {
    uint samplesCount;
};

struct VizUniforms {
    float binsCount;
};

float sin01(float v)
{
    return 0.5 + 0.5 * sin(v);
}

float drawCircle(float r, float polarRadius, float thickness)
{
    return     smoothstep(r, r + thickness, polarRadius) -
            smoothstep(r + thickness, r + 2.0 * thickness, polarRadius);
}


fragment float4 radial_viz_fragment(
                                       VertexOut interpolated [[stage_in]],
                                       constant FragmentUniforms &uniforms [[buffer(0)]],
                                       const constant float *loudnessBuffer [[buffer(1)]],
                                       const constant float *frequenciesBuffer [[buffer(2)]],
                                    constant VizUniforms &vizUniforms [[buffer(3)]]
) {



    float loudness = loudnessBuffer[0];
    float2 uv = {interpolated.pos.x / uniforms.screen_width, 1 - interpolated.pos.y/uniforms.screen_height};
    uv = 2 * (uv - 0.5);
    if (uniforms.screen_width > uniforms.screen_height) {
        uv.x *= uniforms.screen_width/uniforms.screen_height;
    } else {
        uv.y *= uniforms.screen_height/uniforms.screen_width;
    }

    float p = length(uv);
    float pa = atan2(uv.y, uv.x);

    // Frequency:
    // map -1 → 1 to 0 → 361
    // int index = int(lerp(uv.x, -1.0, 1.0, 0, 361));
    float indexRad = (0.5 * pa / 3.1415 + 1) / 2.0; // 0 → 1

    float binsCount = vizUniforms.binsCount;
    int index = lerp(indexRad, 0, 1, 0, binsCount);

    float freq = frequenciesBuffer[index];
//    freq = sin(indexRad ) * freq;
    float o = 0;
    float inc = 0;

    float numRings = 7;
    float ringSpacing = 0.01;
    float ringThickness = 0.03;
    float rotationDistortion = 0.2 * sin01(uniforms.time);
    for (float i = 0; i < numRings; i += 1.0) {
        float baseR;
        baseR = 0.3 * sin01(freq);
        float r = baseR + inc;

        r += rotationDistortion * (0.1 + 0.2 * sin(pa + uniforms.time * (i - 0.1)/4));

//        r += rotationDistortion * (0.1 + 0.1 * sin(uniforms.time * (i - 0.1)));
        r += loudness/3;
        r = min(0.5, r);
        o += drawCircle(r, p, ringThickness * (1.0 + 0.22 * freq * (i - 1.0)));

        inc += ringSpacing;
    }

    float3 bgCol = float3(0.5 - cos(uniforms.time/2) * 0.2 * uv.y, 0.32, 0.6 - sin(uniforms.time/2) * 0.2 * uv.y);

    float ringColSin = lerp(sin(uniforms.time), -1, 1, 0.8, 0.1);

    float3 ringCol = float3(147.0/255.0 , 141.0/255.0, 253/255.0 * ringColSin);
    float3 col = mix(bgCol, ringCol, o);

    return float4(col, 1);



}

