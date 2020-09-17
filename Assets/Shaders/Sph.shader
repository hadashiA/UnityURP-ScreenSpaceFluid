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

            uniform float4 _FrustumRect;
            uniform TEXTURE2D(_SphDepthTexture);
            uniform SAMPLER(sampler_SphDepthTexture);
            uniform float4 _SphDepthTexture_TexelSize;

            float3 CalculatePositionVS(float2 uv)
            {
                half depth = SAMPLE_DEPTH_TEXTURE(_SphDepthTexture, sampler_SphDepthTexture, uv);

                float3 ray = float3(
                    lerp(_FrustumRect[0], _FrustumRect[1], uv.x),
                    lerp(_FrustumRect[2], _FrustumRect[3], uv.y),
                    _ProjectionParams.z);

                return ray * depth;
            }

            half4 ApplySphPassFragment(Varyings input) : SV_Target
            {
                float3 pos = CalculatePositionVS(input.uv);


                float2 deltaU = float2(_SphDepthTexture_TexelSize.x, 0);
                float2 deltaV = float2(0, _SphDepthTexture_TexelSize.y);

                // half depthX1 = SAMPLE_DEPTH_TEXTURE(_SphDepthTexture, sampler_SphDepthTexture, input.uv - deltaU);
                // half depthX2 = SAMPLE_DEPTH_TEXTURE(_SphDepthTexture, sampler_SphDepthTexture, input.uv + deltaU);
                // float3 tx = float3(1, depthX2 - depthX1, 0);
                //
                // half depthY1 = SAMPLE_DEPTH_TEXTURE(_SphDepthTexture, sampler_SphDepthTexture, input.uv - deltaV);
                // half depthY2 = SAMPLE_DEPTH_TEXTURE(_SphDepthTexture, sampler_SphDepthTexture, input.uv + deltaV);
                // float3 ty = float3(1, depthY2 - depthY1, 0);
                //
                // half3 n = cross(ty, tx);

                float3 ddx = CalculatePositionVS(input.uv + deltaU) - CalculatePositionVS(input.uv - deltaU);
                float3 ddy = CalculatePositionVS(input.uv + deltaV) - CalculatePositionVS(input.uv - deltaV);
                half3 n = cross(ddy, ddx);
                #if defined(UNITY_REVERSED_Z)
                    n.z *= -1;
                #endif

                // half3 ddx = CalculatePositionVS(input.uv + deltaU) - pos;
                // half3 ddx2 = pos - CalculatePositionVS(input.uv - deltaU);
                // ddx = abs(ddx.z) > abs(ddx2.z) ? ddx2 : ddx;
                //
                // half3 ddy = CalculatePositionVS(input.uv + deltaV) - pos;
                // half3 ddy2 = pos - CalculatePositionVS(input.uv - deltaV);
                // ddy = abs(ddy.z) > abs(ddy2.z) ? ddy2 : ddy;
                //
                // half3 n = cross(ddy, ddx);
                n = normalize(n);
                // n = TransformObjectToWorldNormal(n);

                // return half4(n * 0.5 + 0.5, 1);
                return half4(n * 0.5 + 0.5, 1);
            }
            ENDHLSL

        }
    }
}
