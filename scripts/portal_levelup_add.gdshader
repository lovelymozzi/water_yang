shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, fog_disabled;

// Only the two source cylinder sprites use the additive glow_01 material.
#include "res://scripts/portal_levelup_sprite.gdshaderinc"
