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

vertex VertexOut bars_vertex(const device VertexIn *vertices [[buffer(0)]], unsigned int vid [[vertex_id]]) {
    VertexOut in;
    in.pos = {vertices[vid].pos.x, vertices[vid].pos.y, 0, 1};
    return in;
}

struct VizUniforms {
    float binsCount;
    float buffersCount;
    float maxAmplitude;
};

float3 barsViz(float2 uv, float w_to_h, float barsCount, float buffersCount, float maxAmplitude, constant float *frequenciesBuffer) {
    float3 col;
    // Set a cap, but otherwise we are using the actual max amplitude
    // Scale so that we the bars never reach the top:
    maxAmplitude *= 1.8;

    float squareInset = 0.3;
    float numColSegments = barsCount;

#define HISTORICAL 1

    float freq = 0;

    float buffersToUse = buffersCount - 1;
    if (HISTORICAL == 0) {
        buffersToUse = 1;
    }
    for(float i=0; i < buffersToUse; i++) {
        int frequencyIndex = lerp(uv.x, 0, 1, 0, barsCount);

        frequencyIndex = (buffersToUse - i) * barsCount + frequencyIndex;

        // The frequency of this bar
        freq += frequenciesBuffer[frequencyIndex];
    }

    freq = freq/buffersToUse; // average
    float freqNorm = lerp(freq, 0, maxAmplitude, 0, 1.0);
    float yvFract = step(uv.y, freqNorm);

    float yv = uv.y * numColSegments / w_to_h;
    float yvInSquareFract = step(squareInset, fract(yv));
    // TODO: could use a step() here probably
    float isTopSquare = ceil(freqNorm * numColSegments / w_to_h) == ceil(yv);

    float xv = uv.x * barsCount;
    float xvInSequareFract = step(squareInset, fract(xv));

    float3 bgCol = float3(0.10, 0.12, 0.13);
    col.xyz = bgCol + yvFract * yvInSquareFract * xvInSequareFract;

    col.xyz *= mix(float3(0.24, 0.52, 0.9), float3(0.9, 0.2, 0.2), isTopSquare);

    return col;
}

float3 historicalCol(float2 uv, float barsCount, float buffersCount, float maxAmplitude, constant float *frequenciesBuffer) {
    // TASK: make this look like a historical frequency graph
    float3 col = 0;

    float bufferRow = floor((1 - uv.y) * buffersCount);
    float2 st = uv;

    int frequencyIndex = lerp(st.x, 0, 1, 0, barsCount);
    frequencyIndex = bufferRow * barsCount + frequencyIndex;

    st.y = fract(uv.y * buffersCount);
    st.x = fract(uv.x * barsCount);

    float frequency = frequenciesBuffer[frequencyIndex];
    float normFrequency = lerp(frequency, 0, maxAmplitude, 0, 1);
    float t = step(st.y - normFrequency, 0.0);
//    float t = smoothstep(st.y, st.y+0.01,  normFrequency);

//    t = smoothstep(0.0, 0.4, normFrequency);

    col = t;

    col *= float3(0.85, 0.1, 0.1);

    return col;
}

fragment float4 bars_fragment(VertexOut interpolated [[stage_in]], constant FragmentUniforms &uniforms [[buffer(0)]], const constant float *loudnessBuffer [[buffer(1)]], const constant float *frequenciesBuffer [[buffer(2)]], constant VizUniforms &vizUniforms [[buffer(3)]] ) {

    float width_to_height = uniforms.screen_width / uniforms.screen_height;
    float2 uv = {interpolated.pos.x / uniforms.screen_width, 1 - interpolated.pos.y/uniforms.screen_height};

    float4 col = float4(0);

    float barsCount = vizUniforms.binsCount;
    float3 barsCol = barsViz(uv, width_to_height, barsCount, vizUniforms.buffersCount, vizUniforms.maxAmplitude, frequenciesBuffer);

    float3 historicalColor = historicalCol(uv, barsCount, vizUniforms.buffersCount, vizUniforms.maxAmplitude, frequenciesBuffer);

    col.xyz = barsCol;
//        col.xyz = historicalColor;

    // Testing only
    //    col.xyz = isTopSquare;
    // ^^^ Testing only
//    col.xyz = 1;

    return col;
    
}
