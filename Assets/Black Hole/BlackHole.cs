using System.Collections;
using System.Collections.Generic;
using UnityEngine;
using UnityEngine.Experimental.Rendering;

/// <summary>
/// Special type of stellar phenomena:
/// 
/// Star which has collapsed into a singularity.
/// </summary>
public class BlackHole : MonoBehaviour
{
	[Header("Properties")]

	[SerializeField] private bool _RenderBlackHole = true;
    [SerializeField] private bool _HasAccretionDisk = false;
    [SerializeField] private float _AccretionDiskSpeed = 1.0f;
	[SerializeField] private float _EventHorizon = 1f;
    [SerializeField] private float _AccretionDiskDetail = 100.0f;
	[SerializeField] private float _AccretionDiskSize = 5f;
	[SerializeField] private float _AccretionDiskGap = 2f;
	[SerializeField] private Color _AccretionDiskColor = Color.red;
	[SerializeField] private bool _EnableDopplerEffect = true;
	[SerializeField, Range(0, 2)] private float _AccretionDiskPower = 1;
	[SerializeField] private float _Gravity = 1e10f;
	[SerializeField] private float _MaxRotation = 10;

	[Header("Performance")]
	[SerializeField] private int _MarchingSteps = 20;
	[SerializeField] private int _LensingResolution = 1024;

	[Header("References")]
    [SerializeField] private Shader _BlackHoleShader;
	[SerializeField] private Mesh _Icosphere;
	[SerializeField] private Texture2D _AccretionDiskNoise;

	// Internal
	private Material _BlackHoleMaterial;
	private MeshFilter _BlackHoleMeshFilter;
	private MeshRenderer _BlackHoleRenderer;
	private Cubemap _BackgroundView;

	/// <summary>
	/// The size of this black hole.
	/// </summary>
	public float Radius => (_EventHorizon + _AccretionDiskSize) * 10;

	// Creates a temporary camera gameobject.
	//
	static Camera CreateTemporaryCamera(float fov, float near = .03f, float far = 1000)
	{
		GameObject cameraObject = new GameObject("__TempCamera");
		Camera camera = cameraObject.AddComponent<Camera>();
		camera.fieldOfView = fov;
		camera.nearClipPlane = near;
		camera.farClipPlane = far;

		return camera;
	}

	// Initializes black hole shader.
	//
	private void Awake()
	{
		_BackgroundView = new Cubemap(_LensingResolution, DefaultFormat.HDR, TextureCreationFlags.None);

		var tempCamera = CreateTemporaryCamera(90, 100, 1000000);
		tempCamera.transform.position = transform.position;
		tempCamera.transform.rotation = transform.rotation;

		// Render skybox cubemap
		tempCamera.RenderToCubemap(_BackgroundView);

		_BlackHoleMeshFilter = gameObject.AddComponent<MeshFilter>();
		_BlackHoleRenderer = gameObject.AddComponent<MeshRenderer>();

		_BlackHoleMaterial = new Material(_BlackHoleShader);
		_BlackHoleMaterial.SetInt("_RenderBlackHole", _RenderBlackHole ? 1 : 0);
		_BlackHoleMaterial.SetInt("_HasAccretionDisk", _HasAccretionDisk ? 1 : 0);
		_BlackHoleMaterial.SetInt("_AccretionDiskDoppler", _EnableDopplerEffect ? 1 : 0);
		_BlackHoleMaterial.SetFloat("_AccretionDiskSpeed", _AccretionDiskSpeed);
		_BlackHoleMaterial.SetFloat("_AccretionDiskSize", _AccretionDiskSize);
		_BlackHoleMaterial.SetFloat("_AccretionDiskGap", _AccretionDiskGap);
		_BlackHoleMaterial.SetFloat("_AccretionDiskDetail", _AccretionDiskDetail);
		_BlackHoleMaterial.SetFloat("_AccretionDiskPower", _AccretionDiskPower);
		_BlackHoleMaterial.SetColor("_AccretionDiskColor", _AccretionDiskColor);
		_BlackHoleMaterial.SetFloat("_Gravity", _Gravity);
		_BlackHoleMaterial.SetFloat("_BlackHoleBounds", Radius);
		_BlackHoleMaterial.SetInt("_MarchingSteps", _MarchingSteps);
		_BlackHoleMaterial.SetTexture("_Skybox", _BackgroundView);
		_BlackHoleMaterial.SetTexture("_Noise", _AccretionDiskNoise);

		_BlackHoleMeshFilter.sharedMesh = _Icosphere;
		_BlackHoleRenderer.sharedMaterial = _BlackHoleMaterial;

		float randomAngleX = Random.Range(-_MaxRotation, _MaxRotation);
		float randomAngleY = Random.Range(-_MaxRotation, _MaxRotation);

		transform.localScale = Vector3.one * Radius * 100;
		transform.localEulerAngles = new Vector3(randomAngleX, 0, randomAngleY);

		Destroy(tempCamera.gameObject);
	}

	// Updates position for shader.
	//
	protected void Update()
	{
		_BlackHoleMaterial.SetVector("_BlackHolePosition", transform.position);
	}
}
