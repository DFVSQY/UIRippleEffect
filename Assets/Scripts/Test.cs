using UnityEngine;
using UnityEngine.EventSystems;
using UnityEngine.UI;

public class Test : MonoBehaviour, IPointerClickHandler
{
	private RawImage rawImage;
	private Material runtimeMaterial;

	private Vector4[] rippleCenters = new Vector4[4]{
		Vector4.one * 0.5f,
		Vector4.one * 0.5f,
		Vector4.one * 0.5f,
		Vector4.one * 0.5f,
	};

	private float[] rippleStartTimes = new float[4] { -1000f, -1000f, -1000f, -1000f, };        // 初始化设定一个无效时间

	private int rippleIdx = 0;

	void Awake()
	{
		rawImage = GetComponent<RawImage>();
		runtimeMaterial = Instantiate(rawImage.material);
		runtimeMaterial.SetVectorArray("_RippleCenters", rippleCenters);
		runtimeMaterial.SetFloatArray("_RippleStartTimes", rippleStartTimes);
		rawImage.material = runtimeMaterial;
	}

	public void OnPointerClick(PointerEventData eventData)
	{
		RectTransformUtility.ScreenPointToLocalPointInRectangle(
			rawImage.rectTransform,
			eventData.position,
			eventData.pressEventCamera,
			out Vector2 localPos
		);

		Rect rect = rawImage.rectTransform.rect;
		float width = rect.width;
		float height = rect.height;
		float uv_x = (localPos.x - rect.x) / width;
		float uv_y = (localPos.y - rect.y) / height;
		float aspect_ratio = width / height;

		rippleCenters[rippleIdx] = new Vector4(uv_x, uv_y, 0, 0);
		rippleStartTimes[rippleIdx] = Time.time;

		// 最多支持同时出现4个涟漪，循环设置
		rippleIdx = (rippleIdx + 1) % 4;

		// 传递点击UV坐标
		runtimeMaterial.SetVectorArray("_RippleCenters", rippleCenters);

		// 使用全局时间作为起始时间
		runtimeMaterial.SetFloatArray("_RippleStartTimes", rippleStartTimes);

		// RawImage的宽高比
		runtimeMaterial.SetFloat("_AspectRatio", aspect_ratio);
	}
}
