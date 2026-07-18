shader_type spatial;
// Molten lava pool — TIME-scrolled noise mixing hot orange/yellow emission over dark crust.
// Compatibility/WebGL2-safe: no screen reads, opaque.
uniform sampler2D noise_tex;

void fragment() {
	vec2 uv = UV * 2.0 + vec2(TIME * 0.025, TIME * 0.014);
	float n = texture(noise_tex, uv).r;
	float n2 = texture(noise_tex, uv * 2.3 + vec2(0.37, -TIME * 0.02)).r;
	float heat = smoothstep(0.35, 0.75, n * 0.65 + n2 * 0.45);
	vec3 crust = vec3(0.08, 0.03, 0.02);
	vec3 hot = mix(vec3(0.85, 0.2, 0.02), vec3(1.0, 0.85, 0.3), smoothstep(0.5, 0.9, n2));
	ALBEDO = mix(crust, hot * 0.35, heat);
	EMISSION = hot * heat * 2.4;
	ROUGHNESS = 0.9;
}
