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

            uniform half _DepthThreshold;
            uniform half _DepthScaleFactor;

            float3 ReconstructPosition(float2 uv, float depth)
            {
                depth = depth > _DepthThreshold ? depth : 0;
                float x = uv.x * 2.0f - 1.0f;
                float y = (1.0 - uv.y) * 2.0f - 1.0f;
                float4 positionCS = float4(x, y, depth, 1.0f) * LinearEyeDepth(depth, _ZBufferParams);
                return mul(UNITY_MATRIX_I_VP, positionCS);
            }

            float3 ReconstructPosition(float2 uv)
            {
                float depth = SAMPLE_DEPTH_TEXTURE(_MainTex, sampler_MainTex, uv);
                return ReconstructPosition(uv, depth);
            }

            half4 DepthNormalPassFragment(Varyings input) : SV_Target
            {
                float depth = SAMPLE_DEPTH_TEXTURE(_MainTex, sampler_MainTex, input.uv);
                half enabled = depth > _DepthThreshold ? 1 : 0;
                float3 pos = ReconstructPosition(input.uv, depth);

                half2 offsetU = half2(_MainTex_TexelSize.x * _DepthScaleFactor, 0);
                half2 offsetV = half2(0, _MainTex_TexelSize.y * _DepthScaleFactor);

                float3 ddx = ReconstructPosition(input.uv + offsetU) - pos;
                float3 ddx2 = pos - ReconstructPosition(input.uv - offsetU);
                ddx = abs(ddx.z) > abs(ddx2.z) ? ddx2 : ddx;

                float3 ddy = ReconstructPosition(input.uv + offsetV) - pos;
                float3 ddy2 = pos - ReconstructPosition(input.uv - offsetV);
                ddy = abs(ddy.z) > abs(ddy2.z) ? ddy2 : ddy;

                float3 n = normalize(cross(ddy, ddx));
                // float3 n = normalize(cross(ddy(pos.xyz), ddx(pos.xyz)));
                // #if defined(UNITY_REVERSED_Z)
                //     n.z = -n.z;
                // #endif
                n *= enabled;
                // return half4(n * 0.5 + 0.5, depth);
                return float4(n, depth);
            }
            ENDHLSL
        }

        Pass
        {
            Name "SphLit"

            HLSLPROGRAM
            #pragma vertex SphLitPassVertex
            #pragma fragment SphLitPassFragment

            uniform half _DistortionStrength;
            uniform half4 _Tint;
            uniform half4 _AmbientColor;
            uniform half4 _SpecColor;
            uniform half _DepthThreshold;
            uniform half _RimAmount;
            uniform half _RimThreshold;
            uniform half _Gloss;
            uniform half4 _EdgeColor;
            uniform half _EdgeScaleFactor;
            uniform half _EdgeDepthThreshold;
            uniform half _EdgeNormalThreshold;

            uniform TEXTURE2D(_SphDepthTexture);
            uniform SAMPLER(sampler_SphDepthTexture);
            uniform float4 _SphDepthTexture_TexelSize;

            uniform TEXTURE2D(_SphNormalTexture);
            uniform SAMPLER(sampler_SphNormalTexture);

            uniform float4x4 _MatrixClipToView;

            struct SphLitVaryings
            {
                float2 uv[5] : TEXCOORD0;
                float4 positionCS : SV_POSITION;
                float3 viewDirWS : TEXCOORD5;
            };

            half EdgeDetection(float2 uv[5], half enabled)
            {
                float3 normal1 = SAMPLE_TEXTURE2D(_SphNormalTexture, sampler_SphNormalTexture, uv[1]).rgb * enabled;
                float3 normal2 = SAMPLE_TEXTURE2D(_SphNormalTexture, sampler_SphNormalTexture, uv[2]).rgb * enabled;
                float3 normal3 = SAMPLE_TEXTURE2D(_SphNormalTexture, sampler_SphNormalTexture, uv[3]).rgb * enabled;
                float3 normal4 = SAMPLE_TEXTURE2D(_SphNormalTexture, sampler_SphNormalTexture, uv[4]).rgb * enabled;

                float3 normalDifference1 = normal2 - normal1;
                float3 normalDifference2 = normal4 - normal3;
                float edgeNormal = sqrt(dot(normalDifference1, normalDifference1) + dot(normalDifference2, normalDifference2)) * enabled;
                edgeNormal = edgeNormal > _EdgeNormalThreshold ? 1 : 0;

                float depth1 = SAMPLE_DEPTH_TEXTURE(_SphDepthTexture, sampler_SphDepthTexture, uv[1]) * enabled;
                float depth2 = SAMPLE_DEPTH_TEXTURE(_SphDepthTexture, sampler_SphDepthTexture, uv[2]) * enabled;
                float depth3 = SAMPLE_DEPTH_TEXTURE(_SphDepthTexture, sampler_SphDepthTexture, uv[3]) * enabled;
                float depth4 = SAMPLE_DEPTH_TEXTURE(_SphDepthTexture, sampler_SphDepthTexture, uv[4]) * enabled;

                float depthDifference1 = depth2 - depth1;
                float depthDifference2 = depth4 - depth3;
                float edgeDepth = sqrt(dot(depthDifference1, depthDifference1) + dot(depthDifference2, depthDifference2)) * 100 * enabled;
                edgeDepth = edgeDepth > _EdgeDepthThreshold ? 1 : 0;

                return edgeNormal * edgeDepth;
            }

            SphLitVaryings SphLitPassVertex(Attributes input)
            {
                SphLitVaryings output = (SphLitVaryings)0;

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

            half4 SphLitPassFragment(SphLitVaryings input) : SV_Target
            {
                // Calculate Normal
                // half destDepth = SAMPLE_DEPTH_TEXTURE(_CameraDepthTexture, sampler_CameraDepthTexture, input.uv);
                float2 uv = input.uv[0];
                float depth = SAMPLE_DEPTH_TEXTURE(_SphDepthTexture, sampler_SphDepthTexture, uv);
                float3 n = SAMPLE_TEXTURE2D(_SphNormalTexture, sampler_SphNormalTexture, uv).rgb;
                n = n * 2 - 1; // decode

                // half enabled = depth > _DepthThreshold && depth < destDepth ? 1 : 0;
                half enabled = depth > _DepthThreshold ? 1 : 0;

                // Calculate Lighting

                // Diffuse
                half nDotL = dot(_MainLightPosition.xyz, n);
                float lightIntensity = smoothstep(0, 0.01, nDotL);
                float4 light = lightIntensity * _MainLightColor;

                // Specular
                float3 viewDir = normalize(input.viewDirWS);
                float3 halfVector = normalize(_MainLightPosition.xyz + viewDir);
                float nDotH = dot(halfVector, n);
                float specularIntensity = pow(nDotH * lightIntensity, _Gloss * _Gloss);
                float specularIntensitySmooth = smoothstep(0.005, 0.01, specularIntensity);
                float4 specular = specularIntensitySmooth * _SpecColor;

                // Rim
                float rimDot = 1 - dot(viewDir, n);
				float rimIntensity = rimDot * pow(nDotL, _RimThreshold);
				rimIntensity = smoothstep(_RimAmount - 0.01, _RimAmount + 0.01, rimIntensity);
				float4 rim = rimIntensity * _SpecColor;

                // Screen Distortion
                float2 uvScreenOffset = n.xy * _DistortionStrength;
                float2 uvScreenDistort = uv + uvScreenOffset;
                half4 screen = SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, uvScreenDistort);

                // Edge Detection
                half edge = EdgeDetection(input.uv, enabled);

                // Merge
                half3 color = _Tint.rgb * (_AmbientColor + light + specular.rgb + rim);
                color = lerp(screen.rgb, color, enabled * _Tint.a);
                color = lerp(color, _EdgeColor.rgb, edge);
                return half4(n * 0.5 + 0.5, 1);
            }
            ENDHLSL
        }
    }
}
