using System.Collections.Generic;
using UnityEngine;

public class SphSpawner : MonoBehaviour
{
    [SerializeField]
    Rigidbody elementPrefab;

    [SerializeField]
    float lifetime = 1f;

    [SerializeField]
    float spawnDuration = 0.1f;

    readonly IList<(Rigidbody, float)> elements = new List<(Rigidbody, float)>();
    float elapsed;
    float duration;

    void Update()
    {
        for (var i = elements.Count - 1; i >= 0; i--)
        {
            var (rigidbody, deadline) = elements[i];
            if (elapsed > deadline || rigidbody.transform.position.y < -5f)
            {
                elements.RemoveAt(i);
                Destroy(rigidbody.gameObject);
            }
        }

        duration += Time.deltaTime;
        if (duration > spawnDuration)
        {
            Spawn();
            duration = 0f;
        }

        elapsed += Time.deltaTime;
    }

    void Spawn()
    {
        var element = Instantiate(elementPrefab);
        elements.Add((element, elapsed + lifetime));

        element.transform.SetParent(transform, false);
        element.transform.localPosition = new Vector3(
                UnityEngine.Random.Range(-0.25f, 0.25f),
                UnityEngine.Random.Range(-0.25f, 0.25f),
                UnityEngine.Random.Range(-0.25f, 0.25f));

        var force = new Vector3(
            UnityEngine.Random.Range(-10f, 10f),
            0f,
            UnityEngine.Random.Range(-10f, 10f));
        element.AddForce(force);
    }
}
