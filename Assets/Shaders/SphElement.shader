Shader "SampleSph/SphElement"
{
    Properties
    {
        // _Radius("Sphere Radius", Float) = 1
    }

    SubShader
    {
        Tags { "RenderType"="Opaque" }
        ZWrite On

        Pass
        {
            Name "SphDepth"
            Tags { "LightMode" = "SphDepth" }

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
                // half depth = UNITY_Z_0_FAR_FROM_CLIPSPACE(input.positionCS.z);
                half depth = input.positionCS.z;
                return depth;
            }
            ENDHLSL
        }

//        Pass
//        {
//            Name "ElementDepth"
//            // Tags { "LightMode" = "SphDepth" }
//            Tags { "LightMode" = "UniversalForward" }
//
//            HLSLPROGRAM
//
//            //--------------------------------------
//            // GPU Instancing
//            #pragma multi_compile_instancing
//
//            #pragma vertex SphDepthPassVertex
//            #pragma fragment SphDepthPassFragment
//
//            #include "Packages/com.unity.render-pipelines.universal/Shaders/LitInput.hlsl"
//            // #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"
//
//            uniform half _Radius;
//
//            struct Attributes
//            {
//                float4 positionOS : POSITION;
//                float2 uv : TEXCOORD0;
//                UNITY_VERTEX_INPUT_INSTANCE_ID
//            };
//
//            struct Varyings
//            {
//                float2 uv : TEXCOORD0;
//                float3 positionVS : TEXCOORD1;
//                float4 positionCS : SV_POSITION;
//                UNITY_VERTEX_INPUT_INSTANCE_ID
//                UNITY_VERTEX_OUTPUT_STEREO
//            };
//
//            Varyings SphDepthPassVertex(Attributes input)
//            {
//				Varyings output = (Varyings)0;
//
//                UNITY_SETUP_INSTANCE_ID(input);
//                UNITY_TRANSFER_INSTANCE_ID(input, output);
//                UNITY_INITIALIZE_VERTEX_OUTPUT_STEREO(output);
//
//				output.uv = input.uv;
//                output.positionVS = mul(UNITY_MATRIX_MV, float4(0, 0, 0, 1)) + float4(input.positionOS.x, input.positionOS.y, 0, 0); // 常にカメラを向く
//				// output.positionCS = mul(UNITY_MATRIX_P, output.positionVS);
//				output.positionCS = TransformObjectToHClip(input.positionOS);
//				return output;
//            }
//
//            half4 SphDepthPassFragment(Varyings input) : SV_Target
//            {
//                UNITY_SETUP_INSTANCE_ID(input)
//                UNITY_SETUP_STEREO_EYE_INDEX_POST_VERTEX(input)
//
//                half2 st = input.uv * 2 - 1;
//                half d = length(st);
//
//                // 球としての座標を計算
//                float3 positionOS = half3(d, d, 1 - d) * _Radius;
//                float4 positionCS = TransformObjectToHClip(positionOS);
//
//                half depth = Linear01Depth(positionCS.z / positionCS.w, _ZBufferParams);
//                return half4(positionOS, 1);
//            }
//            ENDHLSL
//        }
    }
}
