using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;

public class SphPass : ScriptableRenderPass
{
    int BlurringIterations => blurringTargetHandles.Length;

    readonly ProfilingSampler profilingSampler = new ProfilingSampler("Sph");
    readonly ShaderTagId sphDepthShaderTagId = new ShaderTagId("BillboardSphereDepth");

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
        depthTargetHandle.Init("_SphNormalTexture");

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
        var depthTargetDescriptor = cameraTextureDescriptor;
        depthTargetDescriptor.colorFormat = RenderTextureFormat.RHalf;
        depthTargetDescriptor.depthBufferBits = 0;
        depthTargetDescriptor.msaaSamples = 1;

        cmd.GetTemporaryRT(depthTargetHandle.id, depthTargetDescriptor, FilterMode.Point);
        ConfigureTarget(depthTargetHandle.id);
        ConfigureClear(ClearFlag.All, Color.black);

        var normalTargetDescriptor = cameraTextureDescriptor;
        normalTargetDescriptor.colorFormat = RenderTextureFormat.ARGB32;
        normalTargetDescriptor.depthBufferBits = 0;
        normalTargetDescriptor.msaaSamples = 1;
        cmd.GetTemporaryRT(normalTargetHandle.id, normalTargetDescriptor, FilterMode.Point);
    }

    public override void Execute(ScriptableRenderContext context, ref RenderingData renderingData)
    {
        var cmd = CommandBufferPool.Get(profilingSampler.name);

        cmd.SetRenderTarget(depthTargetHandle.id);
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
        var blurringTargetDescriptor = renderingData.cameraData.cameraTargetDescriptor;
        blurringTargetDescriptor.depthBufferBits = 0;
        blurringTargetDescriptor.msaaSamples = 1;

        var currentSource = depthTargetHandle;
        var currentDestination = blurringTargetHandles[0];

        blurringTargetDescriptor.width /= 2;
        blurringTargetDescriptor.height /= 2;
        cmd.GetTemporaryRT(currentDestination.id, blurringTargetDescriptor, FilterMode.Bilinear);
        cmd.Blit(currentSource.id, currentDestination.id, material, downSamplingPass);
        cmd.ReleaseTemporaryRT(currentSource.id);

        for (var i = 1; i < BlurringIterations; i++)
        {
            currentSource = currentDestination;
            currentDestination = blurringTargetHandles[i];

            blurringTargetDescriptor.width /= 2;
            blurringTargetDescriptor.height /= 2;
            cmd.GetTemporaryRT(currentDestination.id, blurringTargetDescriptor, FilterMode.Bilinear);
            cmd.Blit(currentSource.id, currentDestination.id, material, downSamplingPass);
        }

        // Up sampling
        for (var i = BlurringIterations - 2; i >= 0; i--)
        {
            currentSource = currentDestination;
            currentDestination = blurringTargetHandles[i];

            cmd.Blit(currentSource.id, currentDestination.id, material, upSamplingPass);
            cmd.ReleaseTemporaryRT(currentSource.id);
        }

        // Draw Normal
        cmd.SetGlobalTexture("_SphDepthTexture", currentDestination.id);
        cmd.Blit(currentDestination.id, normalTargetHandle.id, material, depthNormalPass);

        // Lighting

        var clipToView = GL.GetGPUProjectionMatrix(renderingData.cameraData.camera.projectionMatrix, true).inverse;
        cmd.SetGlobalMatrix("_ClipToView", clipToView);
        cmd.SetGlobalTexture("_SphNormalTexture", normalTargetHandle.id);
        cmd.Blit(source, source, material, litPass);

        // cmd.SetRenderTarget(source);
        // cmd.SetViewProjectionMatrices(Matrix4x4.identity, Matrix4x4.identity);
        // cmd.DrawMesh(RenderingUtils.fullscreenMesh, Matrix4x4.identity, material, 0, applySphPass);
        // cmd.SetViewProjectionMatrices(camera.worldToCameraMatrix, camera.projectionMatrix);

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