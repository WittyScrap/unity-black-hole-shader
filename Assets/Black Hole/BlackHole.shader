Shader "Unlit/BlackHole"
{
    Properties
    {
                    _MainTex ("Texture", 2D) = "white" {}
                    _EventHorizon("Event Horizon Radius", Float) = .5
        [Toggle]    _HasAccretionDisk("Has Accretion Disk", Int) = 1
        [Toggle]    _AccretionDiskDoppler("Has Doppler Effect", Int) = 1
                    _AccretionDiskSpeed("Accretion Disk Speed", Float) = 1.0
                    _AccretionDiskDetail("Accretion Disk Detail", Float) = 100.0
                    _AccretionDiskSize("Accretion Disk Size", Float) = 10.0
                    _AccretionDiskGap("Accretion Disk Gap", Float) = 5.0
                    _AccretionDiskColor("Accretion Disk Color", Color) = (1, 0, 0, 0)
                    _AccretionDiskPower("Accretion Disk Power", Range(0, 2)) = 1
                    _MarchingSteps("Marching Steps", Int) = 512
                    _TracingLength("Tracing Length", Float) = 16
        [Toggle]    _RenderBlackHole("Render Black Hole", Int) = 1
                    _Gravity("Gravity Force", Float) = 1
                    _Skybox("Skybox", Cube) = "" {}
                    _Noise("Noise", 2D) = "white" {}
    }
    SubShader
    {
        Tags { "RenderType" = "Transparent" "Queue" = "Transparent" }
        Cull Front

        Pass
        {
            CGPROGRAM
            #pragma enable_d3d11_debug_symbols

            #pragma vertex vert
            #pragma fragment frag

            #include "UnityCG.cginc"
            #include "Math.cginc"
             
            struct appdata
            {
                float4 vertex : POSITION;
            };

            struct v2f
            {
                float4 vertex : SV_POSITION;
				float3 view_vector : TEXCOORD0;
                float4 screen_pos : TEXCOORD1;
                float4 grab_pos : TEXCOORD2;
                float3 world_pos : TEXCOORD3;
            };

            v2f vert (appdata v)
            {
                v2f o;
                o.vertex = UnityObjectToClipPos(v.vertex);
                o.screen_pos = ComputeScreenPos(o.vertex);
                o.grab_pos = ComputeGrabScreenPos(o.vertex);
                o.world_pos = mul(unity_ObjectToWorld, v.vertex);

				// Convert 2D pixel position to unprojected camera-space positition, then convert that to world position
				float3 viewVector = mul(unity_CameraInvProjection, float4(o.screen_pos.xy * 2 - 1, 0, -1)); // Z axis points inwards
				o.view_vector = mul(unity_CameraToWorld, float4(viewVector, 0));

                return o;
            }

            sampler2D _CameraDepthTexture;
            samplerCUBE _Skybox;
            
            int _HasAccretionDisk;
            int _AccretionDiskDoppler;
            float _AccretionDiskSpeed;
            float _AccretionDiskSize;
            float _AccretionDiskGap;
            float _AccretionDiskDetail;
            float4 _AccretionDiskColor;
            float _AccretionDiskPower;

            int _MarchingSteps;
            float _Gravity;

            int _RenderBlackHole;
            float3 _BlackHolePosition;
            float _BlackHoleBounds;

            Texture2D<float4> _Noise;
            SamplerState sampler_Noise;
            float4 _Noise_ST;


            float signed_dot(in float3 vecA, in float3 vecB, in float3 vecN)
            {
                float3 a = normalize(vecA);
                float3 b = normalize(vecB);

                float angle = acos(dot(a, b));
                float3 crossProduct = normalize(cross(a, b));
                float vecSign = sign(dot(crossProduct, vecN));

                return remap01(angle * vecSign, -PI, PI);
            }

            float2 sample_accretion_disk(in float dst, in float angle)
            {
                float outFade = 1 - smoothstep(_AccretionDiskGap, _AccretionDiskSize, dst);
                float inFade = 1 - pow(outFade, 100);
                float totalFade = inFade * outFade * 2;

                float2 uv;

                uv.y = saturate(1 - outFade);
                uv.x = angle;

                uv.y *= _AccretionDiskDetail;
                uv.x += _Time.y * _AccretionDiskSpeed;

                float noise = _Noise.SampleLevel(sampler_Noise, uv * _Noise_ST, 0) * totalFade;

                return float2(noise, totalFade);
            }

            float4 accretion_disk(float3 samplePoint)
            {
                const float3 localUp = mul(unity_ObjectToWorld, float3(0, 1, 0));
                const float3 localRight = mul(unity_ObjectToWorld, float3(1, 0, 0));

                float dst = length(samplePoint - _BlackHolePosition);
                float angle = signed_dot(samplePoint - _BlackHolePosition, localRight, localUp);

                float2 sampled = sample_accretion_disk(dst, angle);
                float  thickness = sampled.y;
                float  density = sampled.x * thickness;

                float3 ray = normalize(samplePoint - _WorldSpaceCameraPos);
                float3 toCenter = normalize(samplePoint - _BlackHolePosition);
                float3 swirl = normalize(cross(localUp, toCenter)) * -sign(_AccretionDiskSpeed);
                float doppler = max(((dot(ray, swirl) + 1) / 2), .25f) * 2 * abs(_AccretionDiskSpeed);
                doppler = saturate(doppler + !_AccretionDiskDoppler); // Turns off doppler effect if requested

                return float4(_AccretionDiskColor.xyz * density * (_AccretionDiskPower * doppler), thickness);
            }

            fixed4 frag (v2f i) : SV_Target
            {
                const float G = 6.67e-11f;
                const float c = 299792458.f;

				float3 rayOrigin = _WorldSpaceCameraPos;
				float3 rayDir = normalize(i.world_pos - rayOrigin);
                
                float3 origin = rayOrigin;
                float3 cameraDir = rayDir;

                float2 hitInfo = raySphere(_BlackHolePosition, _BlackHoleBounds, rayOrigin, rayDir);
                float distance = hitInfo.y;
                rayOrigin += rayDir * hitInfo.x;

                // Raymarching information
                float transmittance = 0.f;
                float stepSize = distance / float(_MarchingSteps);

                // Final color if the ray hit anything
                float3 sampled = 0;

                for (int step = 0; step < _MarchingSteps; step += 1)
                {
                    /* -- Accretion Disk Simulation -- */

                    // Has ray hit accretion disk?
                    float3 diskNormal = mul(unity_ObjectToWorld, float4(0, 1, 0, 0));
                    float intersection = intersectDisc(_BlackHolePosition, diskNormal, rayOrigin, rayDir);
                    bool cond = _HasAccretionDisk & (intersection < stepSize);

                    if (cond)
                    {
                        // Advance ray to accretion disk plane.
                        rayOrigin += rayDir * intersection;
                        float4 accretionValue = accretion_disk(rayOrigin); 

                        float3 srcColor = sampled;
                        float  srcAlpha = transmittance;

                        float3 dstColor = accretionValue.rgb;
                        float  dstAlpha = accretionValue.a;

                        sampled = saturate(srcColor + dstColor);
                        transmittance = saturate(transmittance + saturate(dstAlpha));
                    }


                    /* -- Black Hole Simulation -- */

                    intersection *= cond;

                    float advance = stepSize - intersection;
                    float3 rayEnd = rayOrigin + rayDir * advance;

                    // Has ray fallen inside black hole?
                    if (_RenderBlackHole & length(rayEnd - _BlackHolePosition) < stepSize)
                    {
                        sampled *= transmittance;
                        transmittance = _RenderBlackHole + (transmittance * !_RenderBlackHole);
                        break;
                    }

                    rayOrigin = rayEnd;
                    
                    // Bend light ray
                    float3 blackHoleDirection = _BlackHolePosition - rayOrigin;
                    float distanceToBlackHole = length(blackHoleDirection);
                    blackHoleDirection /= distanceToBlackHole;

                    float gravityForce = G / (distanceToBlackHole * distanceToBlackHole) * _Gravity;
                    float3 gravity = blackHoleDirection * gravityForce * stepSize;

                    rayDir = normalize(rayDir + gravity);
                }

                float3 skybox = texCUBElod(_Skybox, float4(rayDir, 0));
                float3 color = lerp(skybox, sampled * 2, transmittance);

                return float4(color, 1);
            }
            ENDCG
        }
    }
}
