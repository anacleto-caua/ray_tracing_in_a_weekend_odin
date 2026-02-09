package main

import "core:fmt"
import "vendor:raylib"
import "core:math/rand"
import "core:math/linalg"

mock_lambertian_data_ : LambertianData = {
    albedo = { 1, 1, 1 }
}

mock_material_ : Material = {
    type = .Lambertian,
    data = &mock_lambertian_data_
}

draw_sphere_on_raylib :: proc (sphere : Sphere, wiremode : bool = false) {
    color_cast := linalg.array_cast((sphere.color * 255.99), u8)
    ray_color_cast: raylib.Color = {color_cast.x, color_cast.y, color_cast.z , 255 }
    pos_cast := linalg.array_cast(sphere.pos, f32)
    radius_cast := f32(sphere.radius)

    if wiremode {
        raylib.DrawSphereWires(pos_cast, radius_cast, 10, 10, ray_color_cast)
    } else {
        raylib.DrawSphere(pos_cast, radius_cast, ray_color_cast)
    }
}

draw_point :: proc(pos : Pos3) {
    mock_sphere : Sphere = {
            pos, .07, {1, 0, 1}, mock_material_
    }

    draw_sphere_on_raylib(mock_sphere)
}

minus1_plus1 :: proc() -> f64 {
    return rand.float64_range(-1,1)
}

main_test :: proc() {
    raylib.InitWindow(1200, 800, "Test")

    spheres : []Sphere = {
        {
            pos = (FORWARD * 4),
            radius = 2,
            color = { 1, 0, 0 }
        },
        {
            pos = (FORWARD * 8) + (RIGHT * 10) + (UP * -4),
            radius = 2.6,
            color = { 1, 0, 0 }
        },
        {
            pos = (FORWARD * 10) + (RIGHT * 10) + (UP * 4),
            radius = 1.6,
            color = { 1, 0, 0 }
        },
        {
            pos = (FORWARD * 14) + (RIGHT * -7) + (UP * -4),
            radius = 3.4,
            color = { 1, 0, 0 }
        },
    }

    camera : raylib.Camera3D = {
        {0, 3, -5},
        linalg.array_cast(spheres[0].pos, f32),
        {0, 1, 0},
        90,
        .PERSPECTIVE
    }

    POINT_COUNT :: 4 * 1000
    rng_points : [POINT_COUNT]Pos3

    true_index := 0
    for sphere in spheres {
        for i in 0..<POINT_COUNT/len(spheres) {
            rng_y := rand.float64_range(-1, 1)
            r := linalg.sqrt(1 - linalg.pow(rng_y, 2))
            long := rand.float64_range(-linalg.PI , linalg.PI)
            point_on_sphere : Pos3 = { r * linalg.sin(long), rng_y, r * linalg.cos(long) }
            point_in_sphere : Pos3 = sphere.pos + sphere.radius * point_on_sphere * linalg.pow(rand.float64_range(0, 1), 1/3)
            rng_points[true_index] = point_in_sphere
            true_index+=1
        }
    }


    for {
        raylib.PollInputEvents()
        raylib.ClearBackground(raylib.RAYWHITE)
        raylib.BeginDrawing()
        raylib.BeginMode3D(camera)

        for sphere in spheres {
            draw_sphere_on_raylib(sphere, true)
        }

        for point in rng_points {
            draw_point(point)
        }

        raylib.DrawGrid(100, 1)
        raylib.EndMode3D()
        raylib.EndDrawing()
        if raylib.WindowShouldClose() { break }
    }

    raylib.CloseWindow()
    fmt.printfln("Test script is running nothing will happen at main program!!!")
    return
}
