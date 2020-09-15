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
    readonly Vector3[] frustomCornersBuffer = new Vector3[4];
    readonly Vector4[] frustomCorners = new Vector4[4];

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
        var depthTargetDescriptor = new RenderTextureDescriptor(
            cameraTextureDescriptor.width,
            cameraTextureDescriptor.height,
            RenderTextureFormat.ARGB32,
            16);
        depthTargetDescriptor.msaaSamples = 1;

        cmd.GetTemporaryRT(sphDepthTargetHandle.id, depthTargetDescriptor, FilterMode.Point);
        cmd.SetRenderTarget(sphDepthTargetHandle.id);
        cmd.ClearRenderTarget(true, true, Color.black, 1f);
    }

    public override void Execute(ScriptableRenderContext context, ref RenderingData renderingData)
    {
        var cmd = CommandBufferPool.Get(profilingSampler.name);
        // targetDescriptor.depthBufferBits = 0;

        // cmd.GetTemporaryRT(metaballSourceHandle.id, targetDescriptor, FilterMode.Bilinear);
        // cmd.SetRenderTarget(metaballSourceHandle.id);
        // cmd.ClearRenderTarget(true, true, Color.black, 1f);

        // cmd.GetTemporaryRT(sphDepthTargetHandle.id);

        var camera = renderingData.cameraData.camera;
        camera.CalculateFrustumCorners(
            new Rect(0f, 0f, 1f, 1f),
            camera.farClipPlane,
            camera.stereoActiveEye,
            frustomCornersBuffer);

        // CalculateFrustumCorners orders them bottom-left, top-left, top-right, bottom-right.
        // However, the quad used to render the image effect has its corner vertices ordered bottom-left, bottom-right, top-left, top-right.
        // So let's reorder them to match the quad's vertices.
        frustomCorners[0] = frustomCornersBuffer[0];
        frustomCorners[1] = frustomCornersBuffer[3];
        frustomCorners[2] = frustomCornersBuffer[1];
        frustomCorners[3] = frustomCornersBuffer[2];

        cmd.SetGlobalVectorArray("_FrustumCorners", frustomCorners);

        // var sortFlags = renderingData.cameraData.defaultOpaqueSortFlags;
        // var drawSettings = CreateDrawingSettings(sphDepthShaderTagId, ref renderingData, sortFlags);
        // drawSettings.perObjectData = PerObjectData.None;
        // drawSettings.overrideMaterial = material;
        // drawSettings.overrideMaterialPassIndex = elementDepthPass;
        // context.DrawRenderers(renderingData.cullResults, ref drawSettings, ref filteringSettings);

        cmd.SetViewProjectionMatrices(Matrix4x4.identity, Matrix4x4.identity);
        cmd.DrawMesh(RenderingUtils.fullscreenMesh, Matrix4x4.identity, material, 0, applySphPass);
        cmd.SetViewProjectionMatrices(camera.worldToCameraMatrix, camera.projectionMatrix);

        // Blit(cmd, sphDepthTargetHandle.id, source, material, applySphPass);

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