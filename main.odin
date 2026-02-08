package main

import "core:os"
import "core:fmt"
import "core:math"
import "core:math/linalg"

// Types
Vec3 :: linalg.Vector3f64
Pos3 :: Vec3
Color :: Vec3

Ray :: struct {
    pos : Pos3,
    dir : Vec3
}

Sphere :: struct {
    pos : Pos3,
    radius : f64,
    color : Color
}

// Defaults
FORWARD : Vec3 = { 0, 0, 1 }
RIGHT : Vec3 = { 1, 0, 0 }
UP : Vec3 =  { 0, 1, 0 }

ZERO : Vec3 =  { 0, 0, 0 }
ONE : Vec3 =  { 1, 1, 1 }

// Procedures
ray_point_at :: proc(ray : Ray, t : f64) -> Pos3 {
    return ray.pos + ray.dir * t
}

ray_hit_sphere :: proc(ray : Ray, sphere : Sphere) -> (bool, f64) {
    dif := ray.pos - sphere.pos;
    a := linalg.dot(ray.dir, ray.dir)
    b := 2 * linalg.dot(dif, ray.dir)
    c := linalg.dot(dif, dif) - sphere.radius * sphere.radius
    delta := b * b - 4 * a * c
    if delta < 0 {
        return false, -1
    } else {
        return true, ((-b - math.sqrt(delta)) / (2 * a))
    }
}

lerp_2_color_ray_on_y :: proc(color1, color2 : Color, ray : Ray) -> Color {
    unit_vector := linalg.normalize(ray.dir)
    t := 0.5 * (unit_vector.y + 1.0)
    return ((1.0-t) * color1 + (t * color2))
}

print_color :: proc(file : os.Handle, color : Color) {
    norm_scaled_color := color * f64(255.99)
    fmt.fprintf(file, "%d %d %d ", u8(norm_scaled_color.x), u8(norm_scaled_color.y), u8(norm_scaled_color.z))
}

// Entry point
main :: proc() {
    // Config ppm
    filepath := "./out.ppm"
    COLS :: 200     // width
    ROWS :: 100     // height

    // Open file
    file, error := os.open(filepath, os.O_RDWR)
    if error != nil {
        fmt.eprintln("Error: {}", error)
        return;
    }
    defer(os.close(file))

    // Fill header information
    fmt.fprintf(file, "P3\n%d %d\n255\n", COLS, ROWS)

    // Spheres - I don't wanna sort from backwards so keep it orded
    spheres : []Sphere ={
        {
            pos = (FORWARD * 7) + (RIGHT * -7) + (UP * -2),
            radius = 1.7,
            color = { 1, 0, 0 }
        },
        {
            pos = (FORWARD * 5) + (RIGHT * 5) + (UP * 2),
            radius = .8,
            color = { 1, 0, 0 }
        },
        {
            pos = (FORWARD * 4) + (RIGHT * 5) + (UP * -2),
            radius = 1.3,
            color = { 1, 0, 0 }
        },
        {
            pos = (FORWARD * 2),
            radius = 1,
            color = { 1, 0, 0 }
        },

    }

    // Other vars
    lower_left_corner : Vec3 = { -2, -1, 1 }
    color_blue : Color = { 0, 0, 1 }
    color_white : Color = { 1, 1, 1 }

    // Write image data
    for y in 0..<ROWS {
        v : f64 = 1 - (f64(y)/f64(ROWS - 1))
        for x in 0..<COLS {
            u : f64 = 1 - (f64(x)/f64(COLS - 1))
            eye_ray : Ray = {ZERO, linalg.normalize(lower_left_corner + u*RIGHT*4 + v*UP*2)}

            final_color := lerp_2_color_ray_on_y(color_blue, color_white, eye_ray)
            for sphere in spheres {
                does_hit, hit_t := ray_hit_sphere(eye_ray, sphere)
                if does_hit {
                    hit_point := ray_point_at(eye_ray, hit_t)
                    normal :=  (.5 * (linalg.normalize(hit_point - sphere.pos) + ONE))
                    final_color = normal
                }
            }
            print_color(file, final_color)
        }
        fmt.fprintfln(file, "")
    }

    fmt.println("Finished!")
}
