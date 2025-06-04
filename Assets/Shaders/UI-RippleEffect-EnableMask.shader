Shader "UI/RippleEffect-EnableMask"
{
    Properties
    {
        _MainTex("Texture", 2D) = "white" {}

        // 将波纹参数暴露成可调节的浮点变量
        _RippleSpeed ("Ripple Speed", Float) = 0.2                          // 波纹扩散速度
        _RippleInterval ("Ripple Interval", Float) = 0.35                   // 相邻波纹圈之间的时间间隔
        _RippleWidth ("Ripple Width", Float) = 0.02                         // 波纹的宽度（厚度）
        _RippleMaxRadius ("Ripple Max Radius", Float) = 0.25                // 波纹最大扩散半径
        _RippleIntensity ("Ripple Intensity", Float) = 0.15                 // 波纹对颜色的加强强度
        _DistortionStrength ("Distortion Strength", Float) = 0.04           // 波纹对UV扰动的强度

        [HideInInspector]
        _AspectRatio ("Aspect Ratio", Float) = 1.0                          // RawImage 的宽高比
    }

    SubShader
    {
        // 透明渲染，保证混合和绘制顺序
        Tags { "RenderType"="Transparent" "Queue"="Transparent" }

        LOD 100

        Pass
        {
            Blend SrcAlpha OneMinusSrcAlpha
            Cull Off
            ZWrite Off

            // 添加Stencil块以支持Mask
            Stencil
            {
                Ref 1
                Comp Equal
                Pass Keep
            }

            CGPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #include "UnityCG.cginc"

            sampler2D _MainTex;
            float4 _MainTex_ST;

            // 固定大小数组，存储4个波纹的中心点（UV坐标系）
            // 在C#端通过Material.SetVectorArray接口赋值
            float4 _RippleCenters[4];

            // 对应4个波纹的起始时间，单位为秒
            // 在C#端通过Material.SetFloatArray接口赋值
            float _RippleStartTimes[4];

            float _RippleSpeed;
            float _RippleInterval;
            float _RippleWidth;
            float _RippleMaxRadius;
            float _RippleIntensity;
            float _DistortionStrength;

            float _AspectRatio; // RawImage 的宽高比，由C#传入

            struct appdata_t
            {
                float4 vertex : POSITION;
                float2 uv : TEXCOORD0;
            };

            struct v2f
            {
                float2 uv : TEXCOORD0;
                float4 vertex : SV_POSITION;
            };

            // 顶点着色器：将顶点坐标变换到裁剪空间，并传递UV
            v2f vert (appdata_t v)
            {
                v2f o;
                o.vertex = UnityObjectToClipPos(v.vertex);
                o.uv = TRANSFORM_TEX(v.uv, _MainTex);
                return o;
            }

            // 片元着色器：实现多波纹扰动效果
            fixed4 frag (v2f i) : SV_Target
            {
                float2 uv = i.uv;
                float time = _Time.y;     // 当前时间（秒）

                // 波纹参数定义
                float rippleSpeed           = _RippleSpeed;
                float rippleInterval        = _RippleInterval;
                float rippleWidth           = _RippleWidth;
                float rippleMaxRadius       = _RippleMaxRadius;
                float rippleIntensity       = _RippleIntensity;
                float distortionStrength    = _DistortionStrength;

                float totalDistortion = 0.0;            // 叠加所有波纹的扰动强度
                float2 totalOffset = float2(0,0);       // 叠加所有波纹的扰动偏移方向
                float totalWeight = 0.0;                // 叠加权重，用于扰动方向归一化

                // 遍历所有4个波纹
                for (int idx = 0; idx < 4; idx++)
                {
                    float elapsed = time - _RippleStartTimes[idx]; // 当前波纹经过时间
                    if (elapsed < 0) continue; // 尚未开始的波纹跳过

                    float rippleDistortion = 0.0; // 当前波纹扰动贡献

                    float2 dir = uv - _RippleCenters[idx].xy; // 片元到波纹中心的方向向量
                    dir.x *= _AspectRatio; // 补偿非正方形拉伸

                    // 每个波纹内部包含最多3个同心波纹圈，间隔rippleInterval
                    for (int j = 0; j < 3; j++)
                    {
                        float t = elapsed - j * rippleInterval;
                        if (t < 0) continue; // 还未到第j圈

                        float radius = t * rippleSpeed; // 当前圈半径
                        if (radius > rippleMaxRadius) continue; // 超出最大范围，忽略

                        float dist = length(dir);               // 距离

                        if (dist > rippleMaxRadius) continue;  // 超出最大影响范围，忽略

                        // 计算环状波纹的强度，使用两次smoothstep形成一个带宽为rippleWidth的环
                        float ring = smoothstep(radius + rippleWidth, radius, dist) *
                                     smoothstep(radius - rippleWidth, radius, dist);

                        // 衰减系数，随着时间推移波纹逐渐减弱
                        float fade = 1.0 - (t / (rippleInterval * 3.0));

                        rippleDistortion += ring * fade;
                    }

                    if (rippleDistortion > 0)
                    {
                        // 累加波纹强度
                        totalDistortion += rippleDistortion;

                        // 计算扰动方向，指向片元与波纹中心的连线方向的单位向量
                        float2 dirNorm = normalize(dir);

                        // 叠加扰动方向与强度的乘积
                        totalOffset += dirNorm * rippleDistortion;

                        // 叠加权重用于后续归一化方向
                        totalWeight += rippleDistortion;
                    }
                }

                // 如果没有任何波纹激活，直接返回原纹理颜色
                if (totalDistortion <= 0)
                {
                    return tex2D(_MainTex, uv);
                }

                // 计算距离所有波纹中心的最小距离，用于波纹强度的衰减
                float minDist = 10000.0;
                for (int idx1 = 0; idx1 < 4; idx1++)
                {
                    float dist = length(uv - _RippleCenters[idx1].xy);
                    if (dist < minDist)
                        minDist = dist;
                }

                // 使用smoothstep进行边缘平滑衰减，防止波纹硬边界
                float attenuation = smoothstep(rippleMaxRadius, rippleMaxRadius * 0.8, minDist);
                totalDistortion *= attenuation;

                // 将扰动方向归一化
                totalOffset /= (totalWeight + 1e-5); // 防止除零

                // 最终扰动偏移值，乘以总扰动强度和扰动强度系数
                totalOffset *= totalDistortion * distortionStrength;

                // UV坐标加上扰动偏移，达到水波扭曲效果
                float2 distortedUV = uv + totalOffset;

                // 采样扭曲后的纹理颜色
                fixed4 col = tex2D(_MainTex, distortedUV);

                // 增加波纹强度对颜色的叠加，增强视觉效果
                col.rgb += totalDistortion * rippleIntensity;

                return col;
            }

            ENDCG
        }
    }
}
