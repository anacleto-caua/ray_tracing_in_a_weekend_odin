package main

import "core:os"
import "core:fmt"
import "core:math"
import "core:math/rand"
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

rand_point_in_sphere :: proc (sphere : Sphere) -> Pos3 {
    rng_y := rand.float64_range(-1, 1)
    r := linalg.sqrt(1 - linalg.pow(rng_y, 2))
    long := rand.float64_range(-linalg.PI , linalg.PI)
    point_on_sphere : Pos3 = { r * linalg.sin(long), rng_y, r * linalg.cos(long) }
    point_in_sphere : Pos3 = sphere.pos + sphere.radius * point_on_sphere * linalg.pow(rand.float64_range(0, 1), 1/3)
    return point_in_sphere
}

// Entry point
main :: proc() {
    // Hacky way of scripting tests without leaving the folder
    // main_test()

    // Config ppm
    filepath := "./out.ppm"
    WIDTH :: 200
    HEIGHT :: 100

    // Open file
    file, error := os.open(filepath, os.O_RDWR)
    if error != nil {
        fmt.eprintln("Error: {}", error)
        return;
    }
    defer(os.close(file))

    // Fill header information
    fmt.fprintf(file, "P3\n%d %d\n255\n", WIDTH, HEIGHT)

    // Spheres - I don't wanna sort from backwards so keep it sorted - closer to furter in reference to the camera
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

    // Camera
    aspect_ratio := f64(WIDTH)/f64(HEIGHT)
    viewport_height := 2.0
    viewport_width := viewport_height * aspect_ratio

    origin := ZERO
    horizontal : Vec3 = RIGHT * viewport_width
    vertical : Vec3 = UP * viewport_height
    lower_left_corner : Vec3 = origin - (horizontal/2) - (vertical/2) + FORWARD

    // Background
    color_blue : Color = { 0, 0, 1 }
    color_white : Color = { 1, 1, 1 }
    color_magenta : Color = { 1, 0, 1 }

    // Antialliasing
    samples_count := 100

    // Write image data
    for y in 0..<HEIGHT {
        for x in 0..<WIDTH {
            // Aa sampling
            final_color := ZERO;
            for s in 0..<samples_count {
                // Ray
                u : f64 = ((f64(x) + rand.float64()) /f64(WIDTH - 1))
                v : f64 = 1 - ((f64(y) + rand.float64()) /f64(HEIGHT - 1))
                eye_ray : Ray = { origin, linalg.normalize(lower_left_corner + u*horizontal + v*vertical) }

                sample_color := lerp_2_color_ray_on_y(color_blue, color_white, eye_ray)
                for sphere in spheres {
                    does_hit, hit_t := ray_hit_sphere(eye_ray, sphere)
                    if does_hit {
                        hit_point := ray_point_at(eye_ray, hit_t)
                        normal :=  (.5 * (linalg.normalize(hit_point - sphere.pos) + ONE))
                        sample_color = normal
                        break
                    }
                }
                final_color += sample_color
            }
            final_color /= f64(samples_count)
            print_color(file, final_color)
        }
        fmt.fprintfln(file, "")
    }

    fmt.println("Finished!")
}
