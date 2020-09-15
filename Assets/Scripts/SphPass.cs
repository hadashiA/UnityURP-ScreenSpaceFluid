using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;

public class SphPass : ScriptableRenderPass
{
    readonly ProfilingSampler profilingSampler = new ProfilingSampler("Sph");
    readonly ShaderTagId sphDepthShaderTagId = new ShaderTagId("SphDepth");

    readonly Material material;
    readonly RenderTargetHandle sphDepthTargetHandle;
    readonly RenderTargetHandle[] blurringTargetHandles;

    readonly int downSamplingPass;
    readonly int upSamplingPass;
    readonly int applySphPass;

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

        sphDepthTargetHandle.Init("_SphDepth");

        downSamplingPass = material.FindPass("DownSampling");
        upSamplingPass = material.FindPass("UpSampling");
        applySphPass = material.FindPass("ApplySph");
    }

    public override void Configure(CommandBuffer cmd, RenderTextureDescriptor cameraTextureDescriptor)
    {
    }

    public override void Execute(ScriptableRenderContext context, ref RenderingData renderingData)
    {
        var cmd = CommandBufferPool.Get(profilingSampler.name);
        using (new ProfilingScope(cmd, profilingSampler))
        {
            var cameraTargetDescriptor = renderingData.cameraData.cameraTargetDescriptor;
            // targetDescriptor.depthBufferBits = 0;

            // cmd.GetTemporaryRT(metaballSourceHandle.id, targetDescriptor, FilterMode.Bilinear);
            // cmd.SetRenderTarget(metaballSourceHandle.id);
            // cmd.ClearRenderTarget(true, true, Color.black, 1f);

            // cmd.GetTemporaryRT(sphDepthTargetHandle.id);
            var depthTargetDescriptor = new RenderTextureDescriptor(
                cameraTargetDescriptor.width,
                cameraTargetDescriptor.height,
                RenderTextureFormat.Depth,
                32);
            depthTargetDescriptor.msaaSamples = 1;

            cmd.GetTemporaryRT(sphDepthTargetHandle.id, depthTargetDescriptor, FilterMode.Point);
            cmd.SetRenderTarget(sphDepthTargetHandle.id);
            cmd.ClearRenderTarget(true, true, Color.white, 1f);

            var sortFlags = renderingData.cameraData.defaultOpaqueSortFlags;
            var drawSettings = CreateDrawingSettings(sphDepthShaderTagId, ref renderingData, sortFlags);
            drawSettings.perObjectData = PerObjectData.None;
            context.DrawRenderers(renderingData.cullResults, ref drawSettings, ref filteringSettings);

            // cmd.Blit(sphDepthTargetHandle.id, colorAttachment);

            // Blurring

            // // Down sampling
            // var currentSource = metaballSourceHandle;
            // var currentDestination = temporatyTargetHandles[0];
            //
            // targetDescriptor.width /= 2;
            // targetDescriptor.height /= 2;
            // cmd.GetTemporaryRT(currentDestination.id, targetDescriptor, FilterMode.Bilinear);
            // cmd.Blit(currentSource.id, currentDestination.id, metaballMaterial, downSamplingPass);
            // cmd.ReleaseTemporaryRT(currentSource.id);
            //
            // for (var i = 1; i < BlurryIterations; i++)
            // {
            //     currentSource = currentDestination;
            //     currentDestination = temporatyTargetHandles[i];
            //
            //     targetDescriptor.width /= 2;
            //     targetDescriptor.height /= 2;
            //     cmd.GetTemporaryRT(currentDestination.id, targetDescriptor, FilterMode.Bilinear);
            //     cmd.Blit(currentSource.id, currentDestination.id, metaballMaterial, downSamplingPass);
            // }
            //
            // // Up sampling
            // for (var i = BlurryIterations - 2; i >= 0; i--)
            // {
            //     currentSource = currentDestination;
            //     currentDestination = temporatyTargetHandles[i];
            //
            //     cmd.Blit(currentSource.id, currentDestination.id, metaballMaterial, upSamplingPass);
            //     cmd.ReleaseTemporaryRT(currentSource.id);
            // }
            //
            // // cmd.SetGlobalTexture("_MetaballSource", currentDestination.Identifier());
            // cmd.Blit(currentDestination.id, SourceIdentifier, metaballMaterial, applyMetaballPass);
        }

        context.ExecuteCommandBuffer(cmd);
        CommandBufferPool.Release(cmd);
    }

    public override void FrameCleanup(CommandBuffer cmd)
    {
        cmd.ReleaseTemporaryRT(sphDepthTargetHandle.id);
        foreach (var targetHandle in blurringTargetHandles)
        {
            cmd.ReleaseTemporaryRT(targetHandle.id);
        }
    }
}