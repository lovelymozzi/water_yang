// Shared live geometry and source velocity. Foam positions are integrated in
// world space by LobbyWakeField; no perimeter phase or scrolling texture.
uniform vec2 body_points[21];
uniform float body_radii[21];
uniform float body_scale = 9.0;
uniform float body_width = 2.26;
uniform float body_length = 6.0;
uniform float flow_distance = 0.0;
uniform vec2 flow_velocity = vec2(0.0);
