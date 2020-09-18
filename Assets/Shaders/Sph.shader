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
            Name "ApplySph"

            HLSLPROGRAM
            #pragma vertex ApplySphPassVertex
            #pragma fragment ApplySphPassFragment

            uniform float4 _FrustumRect;
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
            uniform half _EdgeThreshold;

            uniform TEXTURE2D(_SphDepthTexture);
            uniform SAMPLER(sampler_SphDepthTexture);
            uniform float4 _SphDepthTexture_TexelSize;

            struct SphVaryings
            {
                float2 uv : TEXCOORD0;
                float4 positionCS : SV_POSITION;
                float3 viewDirWS : TEXCOORD1;
            };

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

            half4 EdgeDetection(float2 uv)
            {
                float halfScaleFloor = floor(_EdgeScaleFactor * 0.5);
                float halfScaleCeil = ceil(_EdgeScaleFactor * 0.5);

                float2 bottomLeftUV = uv - float2(_MainTex_TexelSize.x, _SphDepthTexture_TexelSize.y) * halfScaleFloor;
                float2 topRightUV = uv + float2(_MainTex_TexelSize.x, _SphDepthTexture_TexelSize.y) * halfScaleCeil;
                float2 bottomRightUV = uv + float2(_MainTex_TexelSize.x * halfScaleCeil, -_SphDepthTexture_TexelSize.y * halfScaleFloor);
                float2 topLeftUV = uv + float2(-_MainTex_TexelSize.x * halfScaleFloor, _SphDepthTexture_TexelSize.y * halfScaleCeil);

                half depth0 = SAMPLE_TEXTURE2D(_SphDepthTexture, sampler_SphDepthTexture, bottomLeftUV);
                half depth1 = SAMPLE_TEXTURE2D(_SphDepthTexture, sampler_SphDepthTexture, topRightUV);
                half depth2 = SAMPLE_TEXTURE2D(_SphDepthTexture, sampler_SphDepthTexture, bottomRightUV);
                half depth3 = SAMPLE_TEXTURE2D(_SphDepthTexture, sampler_SphDepthTexture, topLeftUV);

                half depthFiniteDifference0 = depth1 - depth0;
                half depthFiniteDifference1 = depth3 - depth2;
                half edgeDepth = sqrt(pow(depthFiniteDifference0, 2) + pow(depthFiniteDifference1, 2)) * 100;

                // edgeDepth = step(_DepthThreshold, edgeDepth);
                edgeDepth = edgeDepth > _EdgeThreshold ? 1 : 0;
                half4 edgeColor = half4(_EdgeColor.rgb, _EdgeColor.a * edgeDepth);
                return edgeDepth;
            }

            SphVaryings ApplySphPassVertex(Attributes input)
            {
                SphVaryings output = (SphVaryings)0;

                VertexPositionInputs vertexInput = GetVertexPositionInputs(input.positionOS.xyz);
                output.positionCS = vertexInput.positionCS;
                output.uv = input.uv;
                output.viewDirWS = GetCameraPositionWS() - vertexInput.positionWS;

                return output;
            }

            half4 ApplySphPassFragment(SphVaryings input) : SV_Target
            {
                // Calculate Normal
                // half destDepth = SAMPLE_DEPTH_TEXTURE(_CameraDepthTexture, sampler_CameraDepthTexture, input.uv);
                half depth = SAMPLE_DEPTH_TEXTURE(_SphDepthTexture, sampler_SphDepthTexture, input.uv);
                // half enabled = depth > _DepthThreshold && depth < destDepth ? 1 : 0;
                half enabled = depth > _DepthThreshold ? 1 : 0;

                float2 deltaU = float2(_SphDepthTexture_TexelSize.x, 0);
                float2 deltaV = float2(0, _SphDepthTexture_TexelSize.y);

                float3 ddx = (CalculatePositionVS(input.uv + deltaU) - CalculatePositionVS(input.uv - deltaU)) * 0.5;
                float3 ddy = (CalculatePositionVS(input.uv + deltaV) - CalculatePositionVS(input.uv - deltaV)) * 0.5;
                half3 n = cross(ddy, ddx);
                n = normalize(n) * enabled;

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
                float2 uvScreenDistort = input.uv + uvScreenOffset;
                half4 screen = SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, uvScreenDistort);

                // Edge Detection
                // half4 edgeColor = EdgeDetection(input.uv) * enabled;

                // Merge
                half3 color = _Tint.rgb * (_AmbientColor + light + specular.rgb + rim);
                // half3 color = _Tint.rgb * (_AmbientColor + light);
                color = lerp(screen.rgb, color, enabled * _Tint.a);
                // color = lerp(color, edgeColor.rgb, edgeColor.a);
                return half4(color, 1);
            }
            ENDHLSL

        }
    }
}
