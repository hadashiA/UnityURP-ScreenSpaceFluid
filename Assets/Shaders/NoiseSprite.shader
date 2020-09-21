Shader "SampleSph/NoiseSprite"
{
    Properties
    {
        _MainTex("Diffuse", 2D) = "white" {}
        _NoiseTex("Noise Texture", 2D) = "black" {}
	    _NoiseCoefficient("Noise Coefficient", Float) = 0.005
	    _NoiseSteps("Noise Steps", Range(0, 1)) = 0.33
	    _NoiseSpeed("Noise Speed", Float) = 10.0


        // Legacy properties. They're here so that materials using this shader can gracefully fallback to the legacy sprite shader.
        [HideInInspector] _Color("Tint", Color) = (1,1,1,1)
        [HideInInspector] _RendererColor("RendererColor", Color) = (1,1,1,1)
        [HideInInspector] _Flip("Flip", Vector) = (1,1,1,1)
        [HideInInspector] _AlphaTex("External Alpha", 2D) = "white" {}
        [HideInInspector] _EnableExternalAlpha("Enable External Alpha", Float) = 0
    }

    HLSLINCLUDE
    #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
    ENDHLSL

    SubShader
    {
        Tags {"Queue" = "Transparent" "RenderType" = "Transparent" "RenderPipeline" = "UniversalPipeline" }

        Blend SrcAlpha OneMinusSrcAlpha
        Cull Off
        ZWrite Off

        Pass
        {
            Tags { "LightMode" = "UniversalForward" "Queue"="Transparent" "RenderType"="Transparent"}

            HLSLPROGRAM
            #pragma prefer_hlslcc gles
            #pragma vertex UnlitVertex
            #pragma fragment UnlitFragment

            uniform TEXTURE2D(_NoiseTex);
			uniform SAMPLER(sampler_NoiseTex);
			uniform half _NoiseCoefficient;
    		uniform half _NoiseSteps;
    		uniform half _NoiseSpeed;

            struct Attributes
            {
                float3 positionOS   : POSITION;
                float4 color		: COLOR;
                float2 uv			: TEXCOORD0;
            };

            struct Varyings
            {
                float4  positionCS		: SV_POSITION;
                float4  color			: COLOR;
                float2	uv				: TEXCOORD0;
            };

            TEXTURE2D(_MainTex);
            SAMPLER(sampler_MainTex);
            float4 _MainTex_ST;

            Varyings UnlitVertex(Attributes attributes)
            {
                Varyings o = (Varyings)0;

                o.positionCS = TransformObjectToHClip(attributes.positionOS);
                o.uv = TRANSFORM_TEX(attributes.uv, _MainTex);
                o.uv = attributes.uv;
                o.color = attributes.color;
                return o;
            }

            float4 UnlitFragment(Varyings i) : SV_Target
            {
                float2 uv = i.uv;
                half t = floor(_Time.y * _NoiseSpeed) * _NoiseSteps;
                half4 n = SAMPLE_TEXTURE2D(_NoiseTex, sampler_NoiseTex  , uv + t);
                uv += n.xy * _NoiseCoefficient;

                float4 mainTex = i.color * SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, uv);
                return mainTex;
            }
            ENDHLSL
        }
    }

    Fallback "Sprites/Default"
}
