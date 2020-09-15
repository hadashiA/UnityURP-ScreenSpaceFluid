using UnityEditor;
using UnityEngine;

public static class QuadMeshGenerator
{
    [MenuItem("SampleSph/Generate Billboard Mesh")]
    static void OpenStartupMenu()
    {
        var mesh = new Mesh();
        mesh.vertices = new[]
        {
            new Vector3 (1.0f, 1.0f, 0.0f),
            new Vector3 (-1.0f, 1.0f, 0.0f),
            new Vector3 (-1.0f, -1.0f, 0.0f),
            new Vector3 (1.0f, -1.0f, 0.0f),
        };

        mesh.triangles = new[] { 0, 1, 2, 2, 3, 0 };
        mesh.uv = new[]
        {
            new Vector2(1f, 0),
            new Vector2(0, 0),
            new Vector2(0, 1f),
            new Vector2(1f, 1f),
        };

        mesh.RecalculateBounds();
        MeshUtility.Optimize(mesh);

        AssetDatabase.CreateAsset(mesh, "Assets/Billboard.asset");
    }
}
