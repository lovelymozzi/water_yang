import bpy
import os
import sys


TILE_SIDE = 1.88
TILE_HEIGHT = 0.55
BEVEL_WIDTH = 0.12
BEVEL_SEGMENTS = 6
MODEL_NAME = "ObstacleTile_1x1"
MATERIAL_NAME = "ObstacleTile_Brown"
BASE_COLOR = (0.60, 0.48, 0.33, 1.0)


def parse_args() -> tuple[str, str]:
    argv = sys.argv
    if "--" in argv:
        argv = argv[argv.index("--") + 1 :]
    else:
        argv = []

    script_dir = os.path.dirname(os.path.abspath(__file__))
    project_root = os.path.dirname(script_dir)
    default_fbx = os.path.join(project_root, "water_yang", "obstacle_tile_1x1.fbx")
    default_blend = os.path.join(project_root, "water_yang", "obstacle_tile_1x1.blend")

    output_fbx = argv[0] if len(argv) >= 1 else default_fbx
    output_blend = argv[1] if len(argv) >= 2 else default_blend
    return output_fbx, output_blend


def reset_scene() -> None:
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)
    for block in bpy.data.meshes:
        bpy.data.meshes.remove(block)
    for block in bpy.data.materials:
        bpy.data.materials.remove(block)


def build_material() -> bpy.types.Material:
    material = bpy.data.materials.new(name=MATERIAL_NAME)
    material.use_nodes = True
    bsdf = material.node_tree.nodes.get("Principled BSDF")
    if bsdf is not None:
        bsdf.inputs["Base Color"].default_value = BASE_COLOR
        bsdf.inputs["Roughness"].default_value = 0.92
        bsdf.inputs["Specular IOR Level"].default_value = 0.15
    return material


def build_obstacle(material: bpy.types.Material) -> bpy.types.Object:
    bpy.ops.mesh.primitive_cube_add(location=(0.0, 0.0, TILE_HEIGHT * 0.5))
    obj = bpy.context.active_object
    obj.name = MODEL_NAME
    obj.dimensions = (TILE_SIDE, TILE_SIDE, TILE_HEIGHT)
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)

    bevel = obj.modifiers.new(name="RoundedEdges", type="BEVEL")
    bevel.width = BEVEL_WIDTH
    bevel.segments = BEVEL_SEGMENTS
    bevel.profile = 0.7
    bevel.limit_method = "ANGLE"
    bevel.angle_limit = 0.523599

    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.modifier_apply(modifier=bevel.name)

    bpy.ops.object.shade_smooth()

    obj.data.materials.append(material)
    return obj


def export_assets(obj: bpy.types.Object, output_fbx: str, output_blend: str) -> None:
    os.makedirs(os.path.dirname(output_fbx), exist_ok=True)
    os.makedirs(os.path.dirname(output_blend), exist_ok=True)

    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj

    bpy.ops.wm.save_as_mainfile(filepath=output_blend)
    bpy.ops.export_scene.fbx(
        filepath=output_fbx,
        use_selection=True,
        object_types={"MESH"},
        apply_unit_scale=True,
        apply_scale_options="FBX_SCALE_UNITS",
        bake_space_transform=False,
        mesh_smooth_type="FACE",
        use_mesh_modifiers=True,
        add_leaf_bones=False,
        path_mode="AUTO",
        axis_forward="-Z",
        axis_up="Y",
    )


def main() -> None:
    output_fbx, output_blend = parse_args()
    reset_scene()
    material = build_material()
    obstacle = build_obstacle(material)
    export_assets(obstacle, output_fbx, output_blend)
    print(f"Exported FBX: {output_fbx}")
    print(f"Saved Blend: {output_blend}")


if __name__ == "__main__":
    main()
