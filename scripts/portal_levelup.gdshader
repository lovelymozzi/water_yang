shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never, fog_disabled;

// Unity's bundled Sprite-Unlit-Default uses SrcAlpha / OneMinusSrcAlpha.
#include "res://scripts/portal_levelup_sprite.gdshaderinc"
