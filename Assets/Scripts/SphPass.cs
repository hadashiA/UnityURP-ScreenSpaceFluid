﻿using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;

public class SphPass : ScriptableRenderPass
{
    int BlurringIterations => blurringTargetHandles.Length;

    readonly ProfilingSampler profilingSampler = new ProfilingSampler("Sph");
    readonly ShaderTagId sphDepthShaderTagId = new ShaderTagId("BillboardSphereDepth");

    readonly Material material;
    readonly RenderTargetHandle sphDepthTargetHandle;
    readonly RenderTargetHandle[] blurringTargetHandles;
    readonly Vector3[] frustomCornersBuffer = new Vector3[4];

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
        depthTargetDescriptor.colorFormat = RenderTextureFormat.RFloat;
        depthTargetDescriptor.depthBufferBits = 24;
        depthTargetDescriptor.msaaSamples = 1;

        cmd.GetTemporaryRT(sphDepthTargetHandle.id, depthTargetDescriptor, FilterMode.Point);
        ConfigureTarget(sphDepthTargetHandle.id);
        ConfigureClear(ClearFlag.All, Color.black);
    }

    public override void Execute(ScriptableRenderContext context, ref RenderingData renderingData)
    {
        var cmd = CommandBufferPool.Get(profilingSampler.name);

        cmd.SetRenderTarget(sphDepthTargetHandle.id);
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
        blurringTargetDescriptor.depthBufferBits = 24;
        blurringTargetDescriptor.msaaSamples = 1;

        var currentSource = sphDepthTargetHandle;
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


        // Draw normal

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
            frustomCornersBuffer[1].y); // top

        cmd.SetGlobalTexture("_SphDepthTexture", currentDestination.id);
        cmd.SetGlobalVector("_FrustumRect", frustumRect);
        cmd.Blit(source, source, material, applySphPass);
        // cmd.Blit(currentDestination.id, source);

        // cmd.SetRenderTarget(source);
        // cmd.SetViewProjectionMatrices(Matrix4x4.identity, Matrix4x4.identity);
        // cmd.DrawMesh(RenderingUtils.fullscreenMesh, Matrix4x4.identity, material, 0, applySphPass);
        // cmd.SetViewProjectionMatrices(camera.worldToCameraMatrix, camera.projectionMatrix);

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