using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;

public class SphPass : ScriptableRenderPass
{
    readonly ProfilingSampler profilingSampler = new ProfilingSampler("Sph");
    readonly ShaderTagId sphDepthShaderTagId = new ShaderTagId("BillboardSphereDepth");

    readonly Material material;
    readonly RenderTargetHandle sphDepthTargetHandle;
    readonly RenderTargetHandle[] blurringTargetHandles;
    readonly Vector3[] frustomCornersBuffer = new Vector3[4];

    readonly int elementDepthPass;
    readonly int downSamplingPass;
    readonly int upSamplingPass;
    readonly int applySphPass;

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

        sphDepthTargetHandle.Init("_SphDepthTexture");

        elementDepthPass = material.FindPass("ElementDepth");
        downSamplingPass = material.FindPass("DownSampling");
        upSamplingPass = material.FindPass("UpSampling");
        applySphPass = material.FindPass("ApplySph");
    }

    public void SetUp(RenderTargetIdentifier source)
    {
        this.source = source;
    }

    public override void Configure(CommandBuffer cmd, RenderTextureDescriptor cameraTextureDescriptor)
    {
        var depthTargetDescriptor = cameraTextureDescriptor;
        depthTargetDescriptor.colorFormat = RenderTextureFormat.RHalf;
        depthTargetDescriptor.depthBufferBits = 1;
        depthTargetDescriptor.msaaSamples = 1;

        cmd.GetTemporaryRT(sphDepthTargetHandle.id, depthTargetDescriptor, FilterMode.Point);
        ConfigureTarget(sphDepthTargetHandle.id);
        ConfigureClear(ClearFlag.All, Color.black);
    }

    public override void Execute(ScriptableRenderContext context, ref RenderingData renderingData)
    {
        var cmd = CommandBufferPool.Get(profilingSampler.name);

        // var depthTargetDescriptor = renderingData.cameraData.cameraTargetDescriptor;
        // depthTargetDescriptor.colorFormat =
        // depthTargetDescriptor.depthBufferBits = 1;
        // depthTargetDescriptor.msaaSamples = 1;
        //
        // cmd.GetTemporaryRT(sphDepthTargetHandle.id, depthTargetDescriptor, FilterMode.Point);
        // cmd.SetRenderTarget(sphDepthTargetHandle.id);
        // cmd.ClearRenderTarget(true, true, Color.red, 1f);

        // Draw depth
        var sortFlags = renderingData.cameraData.defaultOpaqueSortFlags;
        var drawSettings = CreateDrawingSettings(sphDepthShaderTagId, ref renderingData, sortFlags);
        drawSettings.perObjectData = PerObjectData.None;
        // drawSettings.overrideMaterial = material;
        // drawSettings.overrideMaterialPassIndex = elementDepthPass;
        context.DrawRenderers(renderingData.cullResults, ref drawSettings, ref filteringSettings);


        // Draw normal
        //
        // CalculateFrustumCorners returns bottom-left, top-left, top-right, bottom-right.
        var camera = renderingData.cameraData.camera;
        camera.CalculateFrustumCorners(
            new Rect(0f, 0f, 1f, 1f),
            camera.farClipPlane,
            camera.stereoActiveEye,
            frustomCornersBuffer);

        var frustumRect = new Vector4(
            frustomCornersBuffer[0].x, // left
            frustomCornersBuffer[2].x, // right
            frustomCornersBuffer[0].y, // bottom
            frustomCornersBuffer[1].y // top
            );
        cmd.SetGlobalVector("_FrustumRect", frustumRect);
        cmd.Blit(sphDepthTargetHandle.id, source, material, applySphPass);
        // cmd.Blit(sphDepthTargetHandle.id, source);

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