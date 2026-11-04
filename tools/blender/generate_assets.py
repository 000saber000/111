"""生成小农场 M2 的 8 个低模资产（.glb）。

用法：
    "D:\\Blender\\blender.exe" --background --factory-startup --python tools/blender/generate_assets.py

约定：Blender 里 Z 轴朝上；导出时 export_yup=True 会转成 glTF 的 Y-up，
所以游戏里 y 是高度、x/z 是地面平面。

产物写到 assets/models/：低多边形、纯色材质、无贴图、无骨骼动画。
"""

import math
import os

import bpy

OUT_DIR = os.path.join(
    os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))),
    "assets",
    "models",
)

PLOT_SIZE = 1.7
PLOT_HEIGHT = 0.28


def reset_scene():
    bpy.ops.wm.read_factory_settings(use_empty=True)


def srgb_to_linear(c):
    """glTF 的 baseColorFactor 是线性值；这里把 sRGB 目标色换算过去，
    否则导进引擎会整体发白（颜色被当成线性值抬亮）。"""
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


def make_material(name, rgb, roughness=0.85):
    mat = bpy.data.materials.new(name=name)
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes.get("Principled BSDF")
    linear = tuple(srgb_to_linear(c) for c in rgb)
    bsdf.inputs["Base Color"].default_value = (*linear, 1.0)
    bsdf.inputs["Roughness"].default_value = roughness
    return mat


def add_cube(name, size, location, material, rotation=(0, 0, 0)):
    bpy.ops.mesh.primitive_cube_add(size=1, location=location, rotation=rotation)
    obj = bpy.context.active_object
    obj.name = name
    # primitive_cube_add(size=1) 的边长是 1，所以 scale 直接等于目标边长
    obj.scale = tuple(size)
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    obj.data.materials.append(material)
    return obj


def add_uv_sphere(name, radius, location, material, scale=(1, 1, 1), segments=16, rings=8):
    bpy.ops.mesh.primitive_uv_sphere_add(
        segments=segments, ring_count=rings, radius=radius, location=location
    )
    obj = bpy.context.active_object
    obj.name = name
    obj.scale = scale
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    obj.data.materials.append(material)
    return obj


def add_cylinder(name, radius, depth, location, material, rotation=(0, 0, 0), vertices=12):
    bpy.ops.mesh.primitive_cylinder_add(
        vertices=vertices, radius=radius, depth=depth, location=location, rotation=rotation
    )
    obj = bpy.context.active_object
    obj.name = name
    obj.data.materials.append(material)
    return obj


def add_cone(name, radius1, radius2, depth, location, material, vertices=12):
    bpy.ops.mesh.primitive_cone_add(
        vertices=vertices, radius1=radius1, radius2=radius2, depth=depth, location=location
    )
    obj = bpy.context.active_object
    obj.name = name
    obj.data.materials.append(material)
    return obj


def shade_smooth(obj):
    for poly in obj.data.polygons:
        poly.use_smooth = True


def export(name):
    path = os.path.join(OUT_DIR, name + ".glb")
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.export_scene.gltf(
        filepath=path,
        export_format="GLB",
        use_selection=True,
        export_apply=True,
        export_yup=True,
    )
    print("EXPORTED", path)


def build_plot_block():
    reset_scene()
    soil = make_material("soil", (0.45, 0.31, 0.21))
    # 地块：1.7 × 1.7 见方，0.28 高，底面贴地
    add_cube("PlotBlock", (PLOT_SIZE, PLOT_SIZE, PLOT_HEIGHT), (0, 0, PLOT_HEIGHT / 2), soil)
    export("plot_block")


def build_crop(stage):
    reset_scene()
    soil_dark = make_material("soil_dark", (0.32, 0.22, 0.15))
    leaf = make_material("leaf", (0.25, 0.62, 0.24))
    stem = make_material("stem", (0.22, 0.48, 0.18))
    fruit = make_material("fruit", (0.86, 0.25, 0.18))

    if stage == "seed":
        # 刚种下：一小堆翻过土的痕迹
        add_uv_sphere("SeedMound", 0.18, (0, 0, 0.08), soil_dark, scale=(1, 1, 0.55))
    elif stage == "sprout":
        stem_obj = add_cylinder("Stem", 0.03, 0.34, (0, 0, 0.17), stem, vertices=8)
        shade_smooth(stem_obj)
        for sign in (-1, 1):
            add_uv_sphere("Leaf", 0.13, (0.13 * sign, 0, 0.34), leaf, scale=(1.4, 0.5, 1.0))
    else:  # mature
        stem_obj = add_cylinder("Stem", 0.04, 0.52, (0, 0, 0.26), stem, vertices=8)
        shade_smooth(stem_obj)
        for sign in (-1, 1):
            add_uv_sphere("Leaf", 0.16, (0.18 * sign, 0, 0.36), leaf, scale=(1.3, 0.5, 1.0))
        add_uv_sphere("Fruit", 0.17, (0, 0, 0.58), fruit)
    export("crop_" + stage)


def build_coin():
    reset_scene()
    gold = make_material("gold", (0.95, 0.75, 0.15), roughness=0.35)
    # 立起来的硬币：圆柱轴沿 Y，正面朝 +Y（游戏里让它转向相机）
    add_cylinder("Coin", 0.16, 0.05, (0, 0, 0), gold, rotation=(math.radians(90), 0, 0), vertices=20)
    export("coin")


def build_ground():
    reset_scene()
    grass = make_material("grass", (0.36, 0.55, 0.28))
    add_cube("Ground", (9.4, 6.6, 0.2), (0, 0, -0.1), grass)
    export("ground")


def build_fence():
    reset_scene()
    wood = make_material("wood", (0.52, 0.36, 0.20))
    hx, hz = 4.7, 3.3
    for x in (-hx, hx):
        for y in (-hz, hz):
            add_cube("Post", (0.14, 0.14, 0.7), (x, y, 0.35), wood)
    for y in (-hz, hz):
        for z in (0.55, 0.3):
            add_cube("RailX", (2 * hx, 0.08, 0.08), (0, y, z), wood)
    for x in (-hx, hx):
        for z in (0.55, 0.3):
            add_cube("RailY", (0.08, 2 * hz, 0.08), (x, 0, z), wood)
    export("fence")


def build_windmill():
    reset_scene()
    body = make_material("windmill_body", (0.85, 0.83, 0.78))
    roof = make_material("windmill_roof", (0.72, 0.25, 0.22))
    blade = make_material("blade", (0.92, 0.90, 0.84))
    add_cone("Tower", 0.55, 0.32, 2.2, (0, 0, 1.1), body, vertices=10)
    add_cone("Roof", 0.38, 0.0, 0.5, (0, 0, 2.45), roof, vertices=10)
    add_cylinder("Hub", 0.09, 0.12, (0, 0.36, 2.1), blade, rotation=(math.radians(90), 0, 0), vertices=10)
    for i in range(4):
        angle = math.radians(90 * i)
        obj = add_cube(
            "Blade",
            (0.1, 0.05, 0.9),
            (math.sin(angle) * 0.45, 0.36, 2.1 + math.cos(angle) * 0.45),
            blade,
            rotation=(0, angle, 0),
        )
    export("windmill")


def main():
    os.makedirs(OUT_DIR, exist_ok=True)
    build_plot_block()
    build_crop("seed")
    build_crop("sprout")
    build_crop("mature")
    build_coin()
    build_ground()
    build_fence()
    build_windmill()
    print("ALL ASSETS DONE ->", OUT_DIR)


if __name__ == "__main__":
    main()
