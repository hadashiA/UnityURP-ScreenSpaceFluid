using System;
using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;

public class SsfRendererFeature : ScriptableRendererFeature
{
    [Serializable]
    public sealed class SsfSettings
    {
        public Shader SsfShader;
        public RenderPassEvent Event = RenderPassEvent.BeforeRenderingTransparents;

        public LayerMask LayerMask;

        public Color Tint = Color.white;
        public Color AmbientColor = Color.white;
        public Color SpecularColor = Color.white;
        public float Glossiness = 2f;

        [Range(0f, 1f)]
        public float RimAmount = 0.7f;

        [Range(0f, 1f)]
        public float RimThreshold = 0.1f;

        [Range(0f, 1f)]
        public float DepthThreshold = 0.001f;

        [Range(0, 20)]
        public int DepthScaleFactor = 1;

        public float DistortionStrength = 1f;

        [Range(0, 16)]
        public int BlurryIterations = 1;

        public Color EdgeColor = Color.black;

        public int EdgeScaleFactor = 2;

        [Range(0f, 1f)]
        public float EdgeDepthThreshold = 0.2f;

        [Range(0f, 1f)]
        public float EdgeNormalThreshold = 0.2f;

        [Range(0, 5000)]
        public int RenderQueueLowerBound = 0;

        [Range(0, 5000)]
        public int RenderQueueUpperBound = 5000;
    }

    [SerializeField]
    SsfSettings settings = new SsfSettings();

    SsfPass pass;

    public override void Create()
    {
        var ssfShader = settings.SsfShader;
        if (ssfShader == null)
            ssfShader = Shader.Find("SampleSsf/Hidden/Ssf");

        var ssfMaterial = CoreUtils.CreateEngineMaterial(ssfShader);
        ssfMaterial.enableInstancing = true;
        ssfMaterial.SetColor("_Tint", settings.Tint);
        ssfMaterial.SetColor("_AmbientColor", settings.AmbientColor);
        ssfMaterial.SetColor("_SpecColor", settings.SpecularColor);
        ssfMaterial.SetFloat("_Gloss", settings.Glossiness);
        ssfMaterial.SetFloat("_RimAmount", settings.RimAmount);
        ssfMaterial.SetFloat("_RimThreshold", settings.RimThreshold);
        ssfMaterial.SetFloat("_DepthThreshold", settings.DepthThreshold);
        ssfMaterial.SetFloat("_DepthScaleFactor", settings.DepthScaleFactor);
        ssfMaterial.SetFloat("_DistortionStrength", settings.DistortionStrength);
        ssfMaterial.SetColor("_EdgeColor", settings.EdgeColor);
        ssfMaterial.SetInt("_EdgeScaleFactor", settings.EdgeScaleFactor);
        ssfMaterial.SetFloat("_EdgeDepthThreshold", settings.EdgeDepthThreshold);
        ssfMaterial.SetFloat("_EdgeNormalThreshold", settings.EdgeNormalThreshold);

        var renderQueueRange = new RenderQueueRange(
            settings.RenderQueueLowerBound,
            settings.RenderQueueUpperBound);

        pass = new SsfPass(
            settings.Event,
            ssfMaterial,
            settings.BlurryIterations,
            settings.LayerMask,
            renderQueueRange);
    }

    // Here you can inject one or multiple render passes in the renderer.
    // This method is called when setting up the renderer once per-camera.
    public override void AddRenderPasses(ScriptableRenderer renderer, ref RenderingData renderingData)
    {
        pass.SetUp(renderer.cameraColorTarget);
        renderer.EnqueuePass(pass);
    }
}