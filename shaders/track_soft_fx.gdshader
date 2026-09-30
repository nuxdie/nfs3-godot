shader_type spatial;
// High Stakes' effect textures (sun shafts, the Dolphin Cove lighthouse beam): near-white
// light shaped by its alpha, meant to be seen through, so drawn at its own brightness and
// softened (see SOFT_VOLUMES in the include). A shader of its own: reading the scene's depth
// costs a copy of it, which NFS3's glows and fire don't need.
#define SOFT_VOLUMES
#include "res://shaders/track_additive.gdshaderinc"
