Shader "SampleSph/Hidden/Sph"
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

        Varyings PassVertex(Attributes input)
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
            #pragma vertex PassVertex
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
            #pragma vertex PassVertex
            #pragma fragment UpSamplingPassFragment

            half4 UpSamplingPassFragment(Varyings input) : SV_Target
            {
                return half4(SampleBox(input.uv, 0.5), 1);
            }
            ENDHLSL
        }

        Pass
        {
            Name "ApplySph"

            HLSLPROGRAM
            #pragma vertex PassVertex
            #pragma fragment ApplySphPassFragment

            uniform half4 _Tint;
            uniform half _DepthThreshold;
            uniform half _DistortionStrength;
            uniform float4 _FrustumRect;

            uniform TEXTURE2D(_SphDepthTexture);
            uniform SAMPLER(sampler_SphDepthTexture);
            uniform float4 _SphDepthTexture_TexelSize;

            float3 CalculatePositionVS(float2 uv)
            {
                half depth = SAMPLE_DEPTH_TEXTURE(_SphDepthTexture, sampler_SphDepthTexture, uv);
                depth = LinearEyeDepth(depth, _ZBufferParams);

                float3 ray = float3(
                    lerp(_FrustumRect[0], _FrustumRect[1], uv.x),
                    lerp(_FrustumRect[2], _FrustumRect[3], uv.y),
                    _ProjectionParams.z);

                return ray * depth;
            }

            half4 ApplySphPassFragment(Varyings input) : SV_Target
            {
                // Calculate Normal

                half depth = SAMPLE_DEPTH_TEXTURE(_SphDepthTexture, sampler_SphDepthTexture, input.uv);
                half enabled = depth > _DepthThreshold ? 1 : 0;

                float2 deltaU = float2(_SphDepthTexture_TexelSize.x, 0);
                float2 deltaV = float2(0, _SphDepthTexture_TexelSize.y);

                float3 ddx = CalculatePositionVS(input.uv + deltaU) - CalculatePositionVS(input.uv - deltaU);
                float3 ddy = CalculatePositionVS(input.uv + deltaV) - CalculatePositionVS(input.uv - deltaV);
                half3 n = cross(ddy, ddx);
                #if defined(UNITY_REVERSED_Z)
                    n.z *= -1;
                #endif

                n = normalize(n) * enabled;
                // Rendering

                half3 normalVS = normalize(mul((float3x3)UNITY_MATRIX_IT_MV, n));
                half2 uvScreenOffset = (normalVS.xy * _DistortionStrength * _MainTex_TexelSize.xy) / _MainTex_TexelSize.xy;
                // half2 uvScreenDistort = (uvScreenOffset * input.uv.z + input.uv.xy) / input.uv.w;
                half2 uvScreenDistort = (uvScreenOffset + input.uv.xy);
                half4 screen = SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, input.uv);

                // return half4(n * 0.5 + 0.5, 1);
                return lerp(screen, _Tint, enabled);
            }
            ENDHLSL

        }
    }
}
