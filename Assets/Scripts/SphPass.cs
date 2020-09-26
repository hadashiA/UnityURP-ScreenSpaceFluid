using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;

public class SphPass : ScriptableRenderPass
{
    int BlurringIterations => blurringTargetHandles.Length;

    readonly ProfilingSampler profilingSampler = new ProfilingSampler("Sph");
    readonly ShaderTagId sphDepthShaderTagId = new ShaderTagId("SphBillboardSphereDepth");

    readonly Material material;
    readonly RenderTargetHandle depthTargetHandle;
    readonly RenderTargetHandle normalTargetHandle;
    readonly RenderTargetHandle[] blurringTargetHandles;

    readonly int downSamplingPass;
    readonly int upSamplingPass;
    readonly int depthNormalPass;
    readonly int litPass;

    RenderTargetIdentifier source;
    FilteringSettings filteringSettings;

    public SphPass(
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

        depthTargetHandle.Init("_SphDepthTexture");
        normalTargetHandle.Init("_SphNormalTexture");

        downSamplingPass = material.FindPass("DownSampling");
        upSamplingPass = material.FindPass("UpSampling");
        depthNormalPass = material.FindPass("DepthNormal");
        litPass = material.FindPass("SphLit");
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

        cmd.GetTemporaryRT(normalTargetHandle.id, normalTargetDescriptor, FilterMode.Point);

        ConfigureTarget(depthTargetHandle.id);
        ConfigureClear(ClearFlag.All, Color.black);
    }

    public override void Execute(ScriptableRenderContext context, ref RenderingData renderingData)
    {
        var cmd = CommandBufferPool.Get(profilingSampler.name);

        // cmd.SetRenderTarget(depthTargetHandle.id);
        // cmd.ClearRenderTarget(true, true, Color.red, 1f);

        // Draw depth
        var sortFlags = renderingData.cameraData.defaultOpaqueSortFlags;
        var drawSettings = CreateDrawingSettings(sphDepthShaderTagId, ref renderingData, sortFlags);
        drawSettings.perObjectData = PerObjectData.None;
        // drawSettings.overrideMaterial = material;
        // drawSettings.overrideMaterialPassIndex = elementDepthPass;
        context.DrawRenderers(renderingData.cullResults, ref drawSettings, ref filteringSettings);

        // Blurring

        // Down sampling
        if (BlurringIterations > 0)
        {
            var currentSource = default(RenderTargetHandle);
            var currentDestination = depthTargetHandle;

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

            // TODO: これいらない
            cmd.Blit(currentDestination.id, depthTargetHandle.id, material, upSamplingPass);
        }

        // Draw Normal

        var camera = renderingData.cameraData.camera;
        var matrixCameraToWorld = camera.cameraToWorldMatrix;
        var matrixProjectionInverse = GL.GetGPUProjectionMatrix(camera.projectionMatrix, false).inverse;
        var matrixHClipToWorld = matrixCameraToWorld * matrixProjectionInverse;
        cmd.SetGlobalMatrix("_MatrixHClipToWorld", matrixHClipToWorld);
        cmd.SetGlobalTexture("_SphDepthTexture", depthTargetHandle.id);
        cmd.Blit(depthTargetHandle.id, normalTargetHandle.id, material, depthNormalPass);

        // Lighting

        var clipToView = GL.GetGPUProjectionMatrix(renderingData.cameraData.camera.projectionMatrix, true).inverse;
        cmd.SetGlobalMatrix("_MatrixClipToView", clipToView);
        cmd.SetGlobalTexture("_SphNormalTexture", normalTargetHandle.id);
        cmd.Blit(source, source, material, litPass);

        context.ExecuteCommandBuffer(cmd);
        CommandBufferPool.Release(cmd);
    }

    public override void FrameCleanup(CommandBuffer cmd)
    {
        cmd.ReleaseTemporaryRT(depthTargetHandle.id);
        foreach (var targetHandle in blurringTargetHandles)
        {
            cmd.ReleaseTemporaryRT(targetHandle.id);
        }
    }
}
