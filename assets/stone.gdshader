shader_type spatial;
render_mode diffuse_burley;
uniform vec4 top_color : source_color = vec4(0.61,0.70,0.57,1.0);
uniform vec4 side_color : source_color = vec4(0.24,0.36,0.34,1.0);
uniform float tile_scale = 1.0;
uniform float grid_strength = 0.09;
varying vec3 world_pos;
varying vec3 world_normal;
void vertex() {
    world_pos = (MODEL_MATRIX * vec4(VERTEX,1.0)).xyz;
    world_normal = normalize((MODEL_MATRIX * vec4(NORMAL,0.0)).xyz);
}
void fragment() {
    float top = smoothstep(0.4,0.8,world_normal.y);
    vec2 uv = world_pos.xz / tile_scale;
    vec2 line = abs(fract(uv + 0.5) - 0.5);
    float seam = 1.0 - smoothstep(0.014,0.03,min(line.x,line.y));
    float grain = fract(sin(dot(floor(world_pos.xz*14.0),vec2(12.9898,78.233)))*43758.5453);
    vec3 color = mix(side_color.rgb,top_color.rgb,top);
    color *= 1.0 - seam * grid_strength * top;
    color += (grain-0.5)*0.023;
    ALBEDO = color;
    ROUGHNESS = 0.92;
}
