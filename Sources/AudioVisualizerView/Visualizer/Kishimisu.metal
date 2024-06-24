//
//  File.metal
//
//
//  Created by Raheel Ahmad on 6/18/24.
//

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
    float buffersCount;
    float maxAmplitude;
};

float sdHexagram( float2 p, float r, float t)
{
    float4 k = float4(-0.5,0.8660254038 ,0.5773502692,1.7320508076);
    p = abs(p);
    p -= 2.0*min(dot(k.xy,p),0.0)*k.xy;
    p -= 2.0 * min(dot(k.yx,p),0.0)*k.yx;
    p -= float2(clamp(p.x,r*k.z,r*k.w),r);

    return length(p)*sign(p.y);
}

float sdBlobbyCross( float2 pos, float he )
{
    pos = abs(pos);
    pos = float2(abs(pos.x-pos.y),1.0-pos.x-pos.y)/sqrt(2.0);

    float p = (he-pos.y-0.25/he)/(6.0*he);
    float q = pos.x/(he*he*16.0);
    float h = q*q - p*p*p;

    float x;
    if( h>0.0 ) { float r = sqrt(h); x = pow(q+r,1.0/3.0)-pow(abs(q-r),1.0/3.0)*sign(r-q); }
    else        { float r = sqrt(p); x = 2.0*r*cos(acos(q/(p*r))/3.0); }
    x = min(x,sqrt(2.0)/2.0);

    float2 z = float2(x,he*(1.0-2.0*x*x)) - pos;
    return length(z) * sign(z.y);
}

float3 shadertoySin(float2 uv, float freq, float WAVES, float time) {
    float3 color = float3(0.0);

    for (float i=0.0; i<WAVES + 1.0; i++) {
//        float freq = 0.3;
//        texture(iChannel0, float2(i / WAVES, 0.0)).x * 7.0;

        float2 p = float2(uv);

        p.x += i * 0.04 + freq * 0.03;
        p.y += sin(p.x * 10.0 + time) * cos(p.x * 2.0) * freq * 0.2 * ((i + 1.0) / WAVES);
        float intensity = abs(0.01 / p.y) * clamp(freq, 0.35, 2.0);
        color += float3(1.0 * intensity * (i / 5.0), 0.5 * intensity, 1.75 * intensity) * (3.0 / WAVES);
    }

    return color;
}

fragment float4 kishimisu_fragment( VertexOut interpolated [[stage_in]], constant FragmentUniforms &uniforms [[buffer(0)]], const constant float *loudnessBuffer [[buffer(1)]], const constant float *frequenciesBuffer [[buffer(2)]], constant VizUniforms &vizUniforms [[buffer(3)]] ) {

    float time = uniforms.time * 2.0;
    float waves = 20.0;

    float loudness = loudnessBuffer[0];
    loudness = cos(loudness);

    float2 uv = (interpolated.pos.xy * 2.0 - float2(uniforms.screen_width, uniforms.screen_height))/uniforms.screen_height;
//    uv.x *= uniforms.screen_height / uniforms.screen_width;

//    float repetitions = 2;
//    uv = fract(uv * repetitions);
//    uv = uv - 0.5;

    float buffersCount = vizUniforms.buffersCount;
    float barsCount = vizUniforms.binsCount;
    float maxAmplitude = vizUniforms.maxAmplitude;
    float freq = 0;
    float buffersToUse = buffersCount - 1;
    for(float i=0; i < buffersToUse; i++) {
        float index = i / waves;
        index = lerp(index, 0, 1, 0, barsCount);
        int frequencyIndex = int(index);

        frequencyIndex = (buffersToUse - i) * barsCount + frequencyIndex;

        // The frequency of this bar
        freq += frequenciesBuffer[frequencyIndex] * 3;
    }

    freq = freq/buffersToUse; // average
    float freqNorm = lerp(freq, 0, maxAmplitude, 0, 1.0);

    // SDF for the shape:
    // Circle:

    float dc = length(uv) ;
    float ds = sdHexagram(uv + sin(freqNorm)*10, 0.8, freqNorm);
//    float ds = sdBlobbyCross(uv, 0.2);
    float d = ds * dc;

    d = cos(d * waves + loudness/2)/waves * 2;

    d = 0.005/d;
//    d = abs(d);

    float3 col = palette(length(uv)) * d;

    float3 color = 0;
    // sin curves: https://www.shadertoy.com/view/XsX3zS
    for (float i=0.0; i<waves + 1.0; i++) {
        float freq = 0;
        //        float freq = 0.3;
        //        texture(iChannel0, float2(i / WAVES, 0.0)).x * 7.0;
        for(float i=0; i < buffersToUse; i++) {
            float index = lerp(i, 0, 1, 0, barsCount);
            int frequencyIndex = int(index);

            frequencyIndex = (buffersToUse - i) * barsCount + frequencyIndex;

            // The frequency of this bar
            freq += frequenciesBuffer[frequencyIndex] * 1;
        }

        freq = abs(sin(freq));

        float freqNorm = lerp(freq, 0, maxAmplitude, 0, 1.0);

        float2 p = float2(uv);

        p.x += i * 0.04 + freqNorm * 0.03;
        p.y += sin(p.x * 1.0 + time) * cos(p.x * 2.0) * freq * 0.2 * ((i + 1.0) / waves);
        float intensity = abs(0.01 / p.y) * clamp(freqNorm, 0.35, 1.0);
        color += float3(1.0 * intensity * (i / 5.0), 0.5 * intensity, 1.75 * intensity) * (3.0 / waves);
    }
    col = color;

    // from https://www.shadertoy.com/view/XsX3zS
//    float3 col;

//
//    float3 color = float3(0.0);
//    float WAVES = waves;
//    for (float i=0.0; i<WAVES + 1.0; i++) {
//        float2 p = uv;
//
////        p.x += i * 0.04 + freq * 0.03;
////        p.y += sin(p.x * 13.0 * time) * cos(p.x * 1) * freqNorm * 0.31 * ((i + 1.0) / WAVES);
//        float intensity = abs(0.4 / p.y) * clamp(freqNorm, 0.00, 2.0);
//
//        // try this:
////        intensity = abs(0.04/p.y) * freqNorm;
//
//        color += float3(8.0 * intensity * (i / 1.0), 0.5 * intensity, 0.75 * intensity) * (3.0 / WAVES);
//    }
    
//    col = color;
//    col = step(-2, uv0.x);

    return float4(col, 1);
}


