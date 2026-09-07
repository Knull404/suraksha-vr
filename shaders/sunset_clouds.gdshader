shader_type sky;

uniform vec3 zenith_color : source_color = vec3(0.018, 0.035, 0.11);
uniform vec3 upper_color : source_color = vec3(0.10, 0.095, 0.20);
uniform vec3 mid_color : source_color = vec3(0.48, 0.20, 0.25);
uniform vec3 horizon_color : source_color = vec3(1.0, 0.30, 0.075);
uniform vec3 cloud_light : source_color = vec3(1.0, 0.66, 0.43);
uniform vec3 cloud_shadow : source_color = vec3(0.18, 0.10, 0.16);
uniform vec3 sun_color : source_color = vec3(1.0, 0.72, 0.28);

float hash21(vec2 p) {
    p = fract(p * vec2(123.34, 456.21));
    p += dot(p, p + 45.32);
    return fract(p.x * p.y);
}

float noise(vec2 p) {
    vec2 i = floor(p);
    vec2 f = fract(p);
    f = f*f*(3.0-2.0*f);
    float a=hash21(i), b=hash21(i+vec2(1,0));
    float c=hash21(i+vec2(0,1)), d=hash21(i+vec2(1,1));
    return mix(mix(a,b,f.x),mix(c,d,f.x),f.y);
}

float fbm(vec2 p) {
    float v=0.0;
    float a=0.55;
    for(int i=0;i<5;i++){
        v += noise(p)*a;
        p = p*2.03 + vec2(13.7,7.9);
        a*=0.5;
    }
    return v;
}

void sky() {
    vec3 d = normalize(EYEDIR);
    float h = clamp(d.y, -1.0, 1.0);

    // Cinematic sunset gradient.
    float up = smoothstep(0.0, 0.92, h);
    vec3 col = mix(horizon_color, mid_color, up);
    col = mix(col, upper_color, smoothstep(0.28, 0.72, h));
    col = mix(col, zenith_color, smoothstep(0.62, 1.0, h));

    // Layered clouds concentrated around the sunset band.
    float horizon_band = exp(-pow((h - 0.20) / 0.22, 2.0));
    vec2 uv = d.xz / max(h + 0.18, 0.18);
    uv = uv * 0.42 + vec2(TIME * 0.004, TIME * 0.0012);

    float c1 = fbm(uv * 1.7);
    float c2 = fbm(uv * 3.5 + 21.0);
    float cloud_shape = smoothstep(0.48, 0.68, c1);
    cloud_shape *= smoothstep(0.30, 0.72, c2 + 0.18);
    cloud_shape *= horizon_band;

    vec3 clouds = mix(cloud_shadow, cloud_light, smoothstep(0.38, 0.72, h));
    col = mix(col, clouds, cloud_shape * 0.72);

    // Bright sunset glow.
    vec3 sun_dir = normalize(vec3(-0.52, 0.22, -0.82));
    float sun_dot = max(dot(d, sun_dir), 0.0);
    float glow = pow(sun_dot, 18.0);
    float disc = pow(sun_dot, 900.0);
    col += vec3(1.0, 0.24, 0.035) * glow * 0.24;
    col += sun_color * disc * 1.8;

    // Slight horizon haze.
    float haze = pow(max(1.0 - abs(h), 0.0), 5.0);
    col = mix(col, vec3(0.72,0.30,0.18), haze * 0.10);

    COLOR = col;
}
