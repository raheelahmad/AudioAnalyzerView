//
//  File.metal
//
//
//  Created by Raheel Ahmad on 6/18/24.
//

#include <metal_stdlib>
using namespace metal;

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

vertex VertexOut kishimisu_vertex(const device VertexIn *vertices [[buffer(0)]], unsigned int vid [[vertex_id]]) {
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

fragment float4 kishimisu_fragment( VertexOut interpolated [[stage_in]], constant FragmentUniforms &uniforms [[buffer(0)]], const constant float *loudnessBuffer [[buffer(1)]], const constant float *frequenciesBuffer [[buffer(2)]], constant VizUniforms &vizUniforms [[buffer(3)]] ) {


    float loudness = loudnessBuffer[0];
    loudness = sin(loudness);

    float2 uv = {interpolated.pos.x / uniforms.screen_width, 1 - interpolated.pos.y/uniforms.screen_height};
    uv = 2 * (uv - 0.5);
    if (uniforms.screen_width > uniforms.screen_height) {
        uv.x *= uniforms.screen_width/uniforms.screen_height;
    } else {
        uv.y *= uniforms.screen_height/uniforms.screen_width;
    }
    
    float d = length(uv);

    float3 col = d / loudness;

    return float4(col, 1);
}


