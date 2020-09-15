Shader "SampleSph/Hidden/Sph"
{
    Properties
    {
        _MainTex ("Main Tex", 2D) = "white" {}
    }

    SubShader
    {
        // No culling or depth
        // Cull Off ZWrite Off ZTest Always

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

            uniform float3 _FrustumCorners[4];
            uniform TEXTURE2D(_SphDepthTexture);
            uniform SAMPLER(sampler_SphDepthTexture);
            uniform float4 _SphDepthTexture_TexelSize;

            float3 CalculatePositionVS(float2 uv)
            {
                half depth = SAMPLE_DEPTH_TEXTURE(_SphDepthTexture, sampler_SphDepthTexture, uv);

                // We can simply use the UV coordinates to access the corner array.
                // The frustum coordinates are (0, 0), (1, 0), (0, 1), and (1, 1). So the index is u+2v.
                float3 ray = _FrustumCorners[uv.x + 2 * uv.y];
                return ray * depth;
            }

            half4 ApplySphPassFragment(Varyings input) : SV_Target
            {
                // float3 pos = CalculatePositionVS(input.uv);
                //
                // half2 deltaU = half2(_SphDepthTexture_TexelSize.x, 0);
                // half2 deltaV = half2(_SphDepthTexture_TexelSize.y, 0);
                //
                // half2 ddx = CalculatePositionVS(input.uv + deltaU) - pos;
                // half2 ddx2 = pos - CalculatePositionVS(input.uv - deltaU);

                half2 deltaU = half2(_SphDepthTexture_TexelSize.x * 0.5, 0);
                half2 deltaV = half2(_SphDepthTexture_TexelSize.y * 0.5, 0);

                float3 ddx = CalculatePositionVS(input.uv - deltaU) - CalculatePositionVS(input.uv + deltaU);
                float3 ddy = CalculatePositionVS(input.uv - deltaV) - CalculatePositionVS(input.uv + deltaV);

                half3 n = cross(ddx, ddy);
                n = normalize(n);
                return half4(1, 0, 0, 1);
            }
            ENDHLSL

        }
    }
}
