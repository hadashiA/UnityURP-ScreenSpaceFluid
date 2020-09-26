Shader "SampleSph/SphElement"
{
    Properties
    {
        _Radius("Sphere Radius", Float) = 1
    }

    SubShader
    {
        Tags { "RenderType"="Opaque" }

        Pass
        {
            Name "SphVertexDepth"
            Tags { "LightMode" = "SphVertexDepth" }

            HLSLPROGRAM
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"

            #pragma vertex DepthOnlyVertex
            #pragma fragment DepthOnlyFragment
            #pragma multi_compile_instancing

            struct Attributes
            {
                float4 position     : POSITION;
                float2 texcoord     : TEXCOORD0;
                UNITY_VERTEX_INPUT_INSTANCE_ID
            };

            struct Varyings
            {
                float2 uv           : TEXCOORD0;
                float4 positionCS   : SV_POSITION;
                UNITY_VERTEX_INPUT_INSTANCE_ID
                UNITY_VERTEX_OUTPUT_STEREO
            };

            Varyings DepthOnlyVertex(Attributes input)
            {
                Varyings output = (Varyings)0;
                UNITY_SETUP_INSTANCE_ID(input);
                UNITY_INITIALIZE_VERTEX_OUTPUT_STEREO(output);

                output.uv = input.texcoord;
                output.positionCS = TransformObjectToHClip(input.position.xyz);
                return output;
            }

            half4 DepthOnlyFragment(Varyings input) : SV_TARGET
            {
                UNITY_SETUP_STEREO_EYE_INDEX_POST_VERTEX(input);
                half depth = input.positionCS.z;
                return depth;
            }
            ENDHLSL
        }

        Pass
        {
            Name "SphBillboardSphereDepth"
            // Tags { "LightMode" = "UniversalForward" }
            Tags { "LightMode" = "SphBillboardSphereDepth" }

//            ZWrite On
//            Cull Back
//            ZTest On

            HLSLPROGRAM

            //--------------------------------------
            // GPU Instancing
            #pragma multi_compile_instancing

            #pragma vertex PassVertex
            #pragma fragment PassFragment

            #include "Packages/com.unity.render-pipelines.universal/Shaders/LitInput.hlsl"
            // #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"

            uniform half _Radius;

            struct Attributes
            {
                float4 positionOS : POSITION;
                float2 uv : TEXCOORD0;
                UNITY_VERTEX_INPUT_INSTANCE_ID
            };

            struct Varyings
            {
                float2 uv : TEXCOORD0;
                float3 positionVS : TEXCOORD1;
                float4 positionCS : SV_POSITION;
                UNITY_VERTEX_INPUT_INSTANCE_ID
                UNITY_VERTEX_OUTPUT_STEREO
            };

            Varyings PassVertex(Attributes input)
            {
				Varyings output = (Varyings)0;

                UNITY_SETUP_INSTANCE_ID(input);
                UNITY_TRANSFER_INSTANCE_ID(input, output);
                UNITY_INITIALIZE_VERTEX_OUTPUT_STEREO(output);

                // 常にカメラを向く;
                output.positionVS = mul(UNITY_MATRIX_MV, float4(0, 0, 0, 1))
                    + float4(input.positionOS.x, input.positionOS.y, 0, 0)
                    * float4(_Radius * 2, _Radius * 2, 1, 1);

				output.positionCS = mul(UNITY_MATRIX_P, float4(output.positionVS.xyz, 1));
				output.uv = input.uv;
				return output;
            }

            float4 PassFragment(Varyings input) : SV_Target
            {
                UNITY_SETUP_INSTANCE_ID(input)
                UNITY_SETUP_STEREO_EYE_INDEX_POST_VERTEX(input)

                float2 st = input.uv * 2 - 1; // 0-1 → -1-1
                half d2 = dot(st, st); // squared distance

                // 半径を越える部分は描画しない
                // TODO: アルファチャンネルがないので clipを使ってる
                clip(d2 > 1 ? -1 : 1);

                float3 n = float3(st.xy, sqrt(1 - d2));

                // 球としての座標を計算
                float3 positionVS = float4(input.positionVS + n, 1);
                float4 positionCS = TransformWViewToHClip(positionVS);

                float depth = positionCS.z / positionCS.w;
                return depth;
            }
            ENDHLSL
        }
    }
}
