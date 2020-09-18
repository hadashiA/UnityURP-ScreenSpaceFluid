using System;
using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;

public class SphRendererFeature : ScriptableRendererFeature
{
    [Serializable]
    public sealed class SphSettings
    {
        public Shader SphShader;
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

        [Range(0f, 0.1f)]
        public float DepthThreshold = 0.001f;

        public float DistortionStrength = 1f;

        [Range(1, 16)]
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
    SphSettings settings = new SphSettings();

    SphPass pass;

    public override void Create()
    {
        var sphShader = settings.SphShader;
        if (sphShader == null)
            sphShader = Shader.Find("SampleSph/Hidden/Sph");

        var sphMaterial = CoreUtils.CreateEngineMaterial(sphShader);
        sphMaterial.enableInstancing = true;
        sphMaterial.SetColor("_Tint", settings.Tint);
        sphMaterial.SetColor("_AmbientColor", settings.AmbientColor);
        sphMaterial.SetColor("_SpecColor", settings.SpecularColor);
        sphMaterial.SetFloat("_Gloss", settings.Glossiness);
        sphMaterial.SetFloat("_RimAmount", settings.RimAmount);
        sphMaterial.SetFloat("_RimThreshold", settings.RimThreshold);
        sphMaterial.SetFloat("_DepthThreshold", settings.DepthThreshold);
        sphMaterial.SetFloat("_DistortionStrength", settings.DistortionStrength);
        sphMaterial.SetColor("_EdgeColor", settings.EdgeColor);
        sphMaterial.SetInt("_EdgeScaleFactor", settings.EdgeScaleFactor);
        sphMaterial.SetFloat("_EdgeDepthThreshold", settings.EdgeDepthThreshold);
        sphMaterial.SetFloat("_EdgeNormalThreshold", settings.EdgeNormalThreshold);

        var renderQueueRange = new RenderQueueRange(
            settings.RenderQueueLowerBound,
            settings.RenderQueueUpperBound);

        pass = new SphPass(
            settings.Event,
            sphMaterial,
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