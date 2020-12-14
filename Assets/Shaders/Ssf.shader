Shader "SampleSsf/Hidden/Ssf"
{
    Properties
    {
        _MainTex ("Main Tex", 2D) = "white" {}
    }

    SubShader
    {
        // No culling or depth
        Cull Off
        ZWrite Off
        ZTest Always

        HLSLINCLUDE
        // Required to compile gles 2.0 with standard srp library
        #pragma prefer_hlslcc gles
        #pragma exclude_renderers d3d11_9x

        #include "Packages/com.unity.render-pipelines.universal/Shaders/UnlitInput.hlsl"

        uniform TEXTURE2D(_MainTex);
        uniform TEXTURE2D(_MetaballSource);
        uniform SAMPLER(sampler_MainTex);
        uniform float4 _MainTex_TexelSize;

        struct Attributes
        {
            float4 positionOS : POSITION;
            float2 uv : TEXCOORD0;
        };

        struct Varyings
        {
            float2 uv : TEXCOORD0;
            float4 positionCS : SV_POSITION;
        };

        // Encoding/decoding [0..1) floats into 8 bit/channel RG. Note that 1.0 will not be encoded properly.
        inline float2 EncodeFloatRG(float v)
        {
            float2 kEncodeMul = float2(1.0, 255.0);
            float kEncodeBit = 1.0/255.0;
            float2 enc = kEncodeMul * v;
            enc = frac (enc);
            enc.x -= enc.y * kEncodeBit;
            return enc;
        }

        float DecodeFloatRG(float2 enc)
        {
            float2 kDecodeDot = float2(1.0, 1/255.0);
            return dot(enc, kDecodeDot);
        }

        // Encoding/decoding view space normals into 2D 0..1 vector
        float2 EncodeViewNormalStereo(float3 n)
        {
            float kScale = 1.7777;
            float2 enc;
            enc = n.xy / (n.z+1);
            enc /= kScale;
            enc = enc*0.5+0.5;
            return enc;
        }

        float3 DecodeViewNormalStereo(float4 enc4)
        {
            float kScale = 1.7777;
            float3 nn = enc4.xyz*float3(2*kScale,2*kScale,0) + float3(-kScale,-kScale,1);
            float g = 2.0 / dot(nn.xyz,nn.xyz);
            float3 n;
            n.xy = g*nn.xy;
            n.z = g-1;
            return n;
        }

        float4 EncodeDepthNormal(float depth, float3 normal)
        {
            float4 enc;
            enc.xy = EncodeViewNormalStereo(normal);
            enc.zw = EncodeFloatRG(depth);
            return enc;
        }

        void DecodeDepthNormal(float4 enc, out float depth, out float3 normal)
        {
            depth = DecodeFloatRG (enc.zw);
            normal = DecodeViewNormalStereo(enc);
        }

        half3 Sample(float2 uv)
        {
            return SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, uv);
        }

        half3 SampleBox(float2 uv, float delta)
        {
            float4 offset = _MainTex_TexelSize.xyxy * float2(-delta, delta).xxyy;
            half3 s =
                Sample(uv + offset.xy) + Sample(uv + offset.zy) +
                Sample(uv + offset.xw) + Sample(uv + offset.zw);
            return s * 0.25f;
        }

        Varyings BlitPassVertex(Attributes input)
        {
            Varyings output = (Varyings)0;

            VertexPositionInputs vertexInput = GetVertexPositionInputs(input.positionOS.xyz);
            output.positionCS = vertexInput.positionCS;
            output.uv = input.uv;
            return output;
        }
        ENDHLSL

        Pass
        {
            Name "DownSampling"

            HLSLPROGRAM
            #pragma vertex BlitPassVertex
            #pragma fragment DownSamplingPassFragment

            half4 DownSamplingPassFragment(Varyings input) : SV_Target
            {
                return half4(SampleBox(input.uv, 1), 1);
            }
            ENDHLSL
        }

        Pass
        {
            Name "UpSampling"

            HLSLPROGRAM
            #pragma vertex BlitPassVertex
            #pragma fragment UpSamplingPassFragment

            half4 UpSamplingPassFragment(Varyings input) : SV_Target
            {
                return half4(SampleBox(input.uv, 0.5), 1);
            }
            ENDHLSL
        }

        Pass
        {
            Name "DepthNormal"

            HLSLPROGRAM
            #pragma vertex BlitPassVertex
            #pragma fragment DepthNormalPassFragment

            uniform float4x4 _MatrixClipToView;
            uniform half _DepthThreshold;

            float3 ReconstructPosition(float2 uv, float depth)
            {
                float2 positionNDC = uv;
                return ComputeViewSpacePosition(positionNDC, depth, _MatrixClipToView);
            }

            float4 DepthNormalPassFragment(Varyings input) : SV_Target
            {
                float depth = SAMPLE_DEPTH_TEXTURE(_MainTex, sampler_MainTex, input.uv);
                float depth01 = Linear01Depth(depth, _ZBufferParams);
                half enabled = 1 - depth01 > _DepthThreshold ? 1 : 0;

                float3 pos = ReconstructPosition(input.uv, depth);
                float3 n = normalize(cross(ddy(pos.xyz), ddx(pos.xyz)));
                n *= enabled;
                depth *= enabled;
                return EncodeDepthNormal(depth, n);
            }
            ENDHLSL
        }

        Pass
        {
            Name "SsfLit"

            HLSLPROGRAM
            #pragma vertex SsfLitPassVertex
            #pragma fragment SsfLitPassFragment

            uniform half _DistortionStrength;
            uniform half4 _Tint;
            uniform half4 _AmbientColor;
            uniform half4 _SpecColor;
            uniform half _RimAmount;
            uniform half _RimThreshold;
            uniform half _Gloss;

            // Edge
            uniform half4 _EdgeColor;
            uniform half _EdgeScaleFactor;
            uniform half _EdgeDepthThreshold;
            uniform half _EdgeNormalThreshold;

            uniform TEXTURE2D(_SsfDepthNormalTexture);
            uniform SAMPLER(sampler_SsfDepthNormalTexture);

            struct SsfLitVaryings
            {
                float2 uv[5] : TEXCOORD0;
                float4 positionCS : SV_POSITION;
                float3 viewDirWS : TEXCOORD5;
            };

            half EdgeDetection(float2 uv[5], float3 viewDirWS)
            {
                float3 normal1, normal2, normal3, normal4;
                float depth1, depth2, depth3, depth4;

                float4 depthNormal1 = SAMPLE_TEXTURE2D(_SsfDepthNormalTexture, sampler_SsfDepthNormalTexture, uv[1]);
                float4 depthNormal2 = SAMPLE_TEXTURE2D(_SsfDepthNormalTexture, sampler_SsfDepthNormalTexture, uv[2]);
                float4 depthNormal3 = SAMPLE_TEXTURE2D(_SsfDepthNormalTexture, sampler_SsfDepthNormalTexture, uv[3]);
                float4 depthNormal4 = SAMPLE_TEXTURE2D(_SsfDepthNormalTexture, sampler_SsfDepthNormalTexture, uv[4]);

                DecodeDepthNormal(depthNormal1, depth1, normal1);
                DecodeDepthNormal(depthNormal2, depth2, normal2);
                DecodeDepthNormal(depthNormal3, depth3, normal3);
                DecodeDepthNormal(depthNormal4, depth4, normal4);

                float nDotV = dot(normal1, viewDirWS);

                float depthDifference1 = depth2 - depth1;
                float depthDifference2 = depth4 - depth3;
                float edgeDepth = sqrt(dot(depthDifference1, depthDifference1) + dot(depthDifference2, depthDifference2)) * 100;
                edgeDepth = edgeDepth > _EdgeDepthThreshold ? 1 : 0;

                float3 normalDifference1 = normal2 - normal1;
                float3 normalDifference2 = normal4 - normal3;
                float edgeNormal = sqrt(dot(normalDifference1, normalDifference1) + dot(normalDifference2, normalDifference2));
                edgeNormal = edgeNormal > _EdgeNormalThreshold ? 1 : 0;

                return edgeNormal * edgeDepth * (nDotV > 0.4 ? 1 : 0);
            }

            SsfLitVaryings SsfLitPassVertex(Attributes input)
            {
                SsfLitVaryings output = (SsfLitVaryings)0;

                VertexPositionInputs vertexInput = GetVertexPositionInputs(input.positionOS.xyz);
                output.positionCS = vertexInput.positionCS;
                output.viewDirWS = GetCameraPositionWS() - vertexInput.positionWS;

                output.uv[0] = input.uv;
                output.uv[1] = input.uv + _MainTex_TexelSize.xy * half2( 1, 1) * _EdgeScaleFactor;
                output.uv[2] = input.uv + _MainTex_TexelSize.xy * half2(-1,-1) * _EdgeScaleFactor;
                output.uv[3] = input.uv + _MainTex_TexelSize.xy * half2(-1, 1) * _EdgeScaleFactor;
                output.uv[4] = input.uv + _MainTex_TexelSize.xy * half2( 1,-1) * _EdgeScaleFactor;

                return output;
            }

            half4 SsfLitPassFragment(SsfLitVaryings input) : SV_Target
            {
                float2 uv = input.uv[0];
                float4 depthNormal = SAMPLE_TEXTURE2D(_SsfDepthNormalTexture, sampler_SsfDepthNormalTexture, uv);
                float depth;
                float3 n;
                DecodeDepthNormal(depthNormal, depth, n);
                // n = mul(transpose(UNITY_MATRIX_V), float4(n, 0)).rgb;

                half enabled = depth > 0 ? 1 : 0;

                // Diffuse
                half nDotL = dot(_MainLightPosition.xyz, n);
                float lightIntensity = smoothstep(0, 0.01, nDotL);
                float4 light = lightIntensity * _MainLightColor;

                // Specular
                float3 viewDir = normalize(input.viewDirWS);
                float3 halfVector = normalize(_MainLightPosition.xyz + viewDir);
                float nDotH = dot(halfVector, n);
                float specularIntensity = pow(nDotH * lightIntensity, _Gloss * _Gloss);
                specularIntensity = smoothstep(0.005, 0.01, specularIntensity);

                // Edge Detection
                half edge = EdgeDetection(input.uv, input.viewDirWS);

                // Screen Distortion
                float2 uvScreenOffset = n.xy * _DistortionStrength * enabled;
                float2 uvScreenDistort = uv + uvScreenOffset;
                half4 screen = SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, uvScreenDistort);

                // Merge
                half4 color = lerp(_Tint * (_AmbientColor + light), _SpecColor, specularIntensity);
                color = lerp(screen, color, color.a * enabled);
                color = lerp(color, _EdgeColor, edge);
                return color;
            }
            ENDHLSL
        }
    }
}
