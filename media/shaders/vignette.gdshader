shader_type canvas_item;

// Corner-darkening overlay for CRT vignette effect.
// Applied on a full-screen ColorRect at a high CanvasLayer layer so it
// composites over all UI panels (not just the grid background).
//
// d is the squared distance from screen centre: 0.0 at centre, 1.0 at the
// mid-edges, ~1.72 in the corners (after the 0.85 aspect squeeze).
// The falloff maps [inner_edge, outer_edge] onto [0, max_opacity].
// outer_edge must stay beyond the corner distance (1.72) so the overlay
// never saturates to full opacity — UI near the screen border stays readable.

uniform float inner_edge : hint_range(0.0, 2.0) = 0.55;
uniform float outer_edge : hint_range(0.5, 4.0) = 2.2;
uniform float max_opacity : hint_range(0.0, 1.0) = 0.3;
uniform vec4 edge_color : source_color = vec4(0.0, 0.0, 0.04, 1.0);

void fragment() {
    // Remap UV from [0,1] to [-1,1]; centre is (0,0).
    vec2 uv = UV * 2.0 - 1.0;
    // Slightly taller ellipse so it matches a widescreen monitor.
    uv.y *= 0.85;
    float d = dot(uv, uv);
    float vignette = smoothstep(inner_edge, outer_edge, d) * max_opacity;
    // Alpha drives the blend: 0 at centre (transparent), rises at edges.
    COLOR = vec4(edge_color.rgb, vignette * edge_color.a);
}
