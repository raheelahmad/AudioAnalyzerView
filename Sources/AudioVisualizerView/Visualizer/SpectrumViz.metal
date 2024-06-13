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

vertex VertexOut spectrum_vertex(const device VertexIn *vertices [[buffer(0)]], unsigned int vid [[vertex_id]]) {
    VertexOut in;
    in.pos = {vertices[vid].pos.x, vertices[vid].pos.y, 0, 1};
    return in;
}

struct VizUniforms {
    float barsCount;
};

#define S smoothstep
float4 Line(float2 uv, float speed, float height, float3 col, float time) {
    float sinHeightModulator = sin(time * speed + uv.x * height);
    uv.y += S(0., 0., abs(uv.x)) * sinHeightModulator * .2;

    float colModulator = S(.4 * S(.1, .2, abs(uv.y)), 0., abs(uv.y) - .004);
    return float4(colModulator * col, 1.0) * S(0., .3, 1);
}


fragment float4 spectrum_fragment(
                                       VertexOut interpolated [[stage_in]],
                                       constant FragmentUniforms &uniforms [[buffer(0)]],
                                       const constant float *loudnessBuffer [[buffer(1)]],
                                       const constant float *frequenciesBuffer [[buffer(2)]],
                                  constant VizUniforms &vizUniforms [[buffer(3)]]
) {
    float width_to_height = uniforms.screen_width / uniforms.screen_height;
    float2 uv = {interpolated.pos.x / uniforms.screen_width, 1 - interpolated.pos.y/uniforms.screen_height};
    float2 radUV = float2(uv.x, uv.y) - 0.5;

    float4 col = float4(0);


    float maxFrequency = width_to_height > 1.0 ? 15 : 12;

    // There are these many bars on X axis
    float barsCount = vizUniforms.barsCount;
    int index = lerp(uv.x, 0, 1, 0, barsCount);
    // The frequency of this bar
    float freq = frequenciesBuffer[index];
    float val = lerp(freq, 0, maxFrequency, 0, 1);

    val /= 4.2;
    radUV.y /= val;
    //    radUV.y *= loudness*4;
    for (float i = 0.; i <= 5.; i += 1.) {
        float t = i / 4.11;
        float speed = /*speed*/ 0.8 + t;
        float height = t/22;
        float3 colForWave = float3(.3 + t * 1.2, .2 + t * .4, 0.7);
        col += Line(radUV, speed, height, colForWave, uniforms.time);
        //        col += float4(colForWave, 1);
    }

    // Bars Viz
    //    col.xyz += step(uv.y, val);

    return col;
}

