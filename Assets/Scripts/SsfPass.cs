using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;

public class SsfPass : ScriptableRenderPass
{
    int BlurringIterations => blurringTargetHandles.Length;

    readonly ProfilingSampler profilingSampler = new ProfilingSampler("Ssf");
    readonly ShaderTagId ssfDepthShaderTagId = new ShaderTagId("SsfBillboardSphereDepth");

    readonly Material material;
    readonly RenderTargetHandle depthTargetHandle;
    readonly RenderTargetHandle depthNormalTargetHandle;
    readonly RenderTargetHandle[] blurringTargetHandles;

    readonly int downSamplingPass;
    readonly int upSamplingPass;
    readonly int depthNormalPass;
    readonly int litPass;

    RenderTargetIdentifier source;
    FilteringSettings filteringSettings;

    public SsfPass(
        RenderPassEvent renderPassEvent,
        Material material,
        int blurryIterations,
        LayerMask layerMask,
        RenderQueueRange renderQueueRange)
    {
        this.renderPassEvent = renderPassEvent;
        this.material = material;
        filteringSettings = new FilteringSettings(renderQueueRange, layerMask);

        blurringTargetHandles = new RenderTargetHandle[blurryIterations];
        for (var i = 0; i < blurryIterations; i++)
        {
            blurringTargetHandles[i].Init($"_BlurTemp{i}");
        }

        depthTargetHandle.Init("_SsfDepthTexture");
        depthNormalTargetHandle.Init("_SsfNormalTexture");

        downSamplingPass = material.FindPass("DownSampling");
        upSamplingPass = material.FindPass("UpSampling");
        depthNormalPass = material.FindPass("DepthNormal");
        litPass = material.FindPass("SsfLit");
    }

    public void SetUp(RenderTargetIdentifier source)
    {
        this.source = source;
    }

    public override void Configure(CommandBuffer cmd, RenderTextureDescriptor cameraTextureDescriptor)
    {
        var w = cameraTextureDescriptor.width;
        var h = cameraTextureDescriptor.height;

        var depthTargetDescriptor = new RenderTextureDescriptor(w, h, RenderTextureFormat.RFloat, 0, 0)
        {
            msaaSamples = 1
        };

        cmd.GetTemporaryRT(depthTargetHandle.id, depthTargetDescriptor, FilterMode.Point);

        for (var i = 0; i < BlurringIterations; i++)
        {
            depthTargetDescriptor.width /= 2;
            depthTargetDescriptor.height /= 2;
            cmd.GetTemporaryRT(blurringTargetHandles[i].id, depthTargetDescriptor, FilterMode.Bilinear);
        }

        var normalTargetDescriptor = new RenderTextureDescriptor(w, h, RenderTextureFormat.ARGB32, 0, 0)
        {
            msaaSamples = 1
        };

        cmd.GetTemporaryRT(depthNormalTargetHandle.id, normalTargetDescriptor, FilterMode.Point);

        ConfigureTarget(depthTargetHandle.id);
        ConfigureClear(ClearFlag.All, Color.black);
    }

    public override void Execute(ScriptableRenderContext context, ref RenderingData renderingData)
    {
        var cmd = CommandBufferPool.Get(profilingSampler.name);

        // Draw depth

        var sortFlags = renderingData.cameraData.defaultOpaqueSortFlags;
        var drawSettings = CreateDrawingSettings(ssfDepthShaderTagId, ref renderingData, sortFlags);
        drawSettings.perObjectData = PerObjectData.None;
        context.DrawRenderers(renderingData.cullResults, ref drawSettings, ref filteringSettings);

        // Blurring

        var currentDestination = depthTargetHandle;

        // Down sampling
        if (BlurringIterations > 0)
        {
            RenderTargetHandle currentSource;
            for (var i = 0; i < BlurringIterations; i++)
            {
                currentSource = currentDestination;
                currentDestination = blurringTargetHandles[i];

                cmd.Blit(currentSource.id, currentDestination.id, material, downSamplingPass);
            }

            // Up sampling
            for (var i = BlurringIterations - 2; i >= 0; i--)
            {
                currentSource = currentDestination;
                currentDestination = blurringTargetHandles[i];

                cmd.Blit(currentSource.id, currentDestination.id, material, upSamplingPass);
            }
        }

        // Draw Normal

        var clipToView = GL.GetGPUProjectionMatrix(renderingData.cameraData.camera.projectionMatrix, true).inverse;
        cmd.SetGlobalMatrix("_MatrixClipToView", clipToView);
        cmd.Blit(currentDestination.id, depthNormalTargetHandle.id, material, depthNormalPass);

        // Lighting

        cmd.SetGlobalTexture("_SsfDepthNormalTexture", depthNormalTargetHandle.id);
        cmd.Blit(source, source, material, litPass);

        context.ExecuteCommandBuffer(cmd);
        CommandBufferPool.Release(cmd);
    }

    public override void FrameCleanup(CommandBuffer cmd)
    {
        cmd.ReleaseTemporaryRT(depthTargetHandle.id);
        cmd.ReleaseTemporaryRT(depthNormalTargetHandle.id);
        foreach (var targetHandle in blurringTargetHandles)
        {
            cmd.ReleaseTemporaryRT(targetHandle.id);
        }
    }
}
