package main

import "core:os"
import "core:fmt"
import "core:math/linalg"

// Types
Vec3 :: linalg.Vector3f64
Pos3 :: Vec3
Color :: Vec3

Ray :: struct {
    pos : Pos3,
    dir : Vec3
}

// Defaults
FORWARD : Vec3 = { 0, 0, 1 }
RIGHT : Vec3 = { 1, 0, 0 }
UP : Vec3 =  { 0, 1, 0 }

ZERO : Vec3 =  { 0, 0, 0 }
ONE : Vec3 =  { 1, 1, 1 }

// Procedures
cast_ray :: proc(ray: Ray, t : f64) -> Pos3 {
    return ray.pos + ray.dir * t
}

lerp_2_color_ray_on_y :: proc(color1, color2 : Color, ray : Ray) -> Color {
    unit_vector := linalg.normalize(ray.dir)
    t := 0.5 * (unit_vector.y + 1.0)
    return ((1.0-t) * color1 + (t * color2))
}

// Entry point
main :: proc() {
    // Config ppm
    filepath := "./out.ppm"
    COLS :: 200
    ROWS :: 100

    // Open file
    file, error := os.open(filepath, os.O_RDWR)
    if error != nil {
        fmt.eprintln("Error: {}", error)
        return;
    }
    defer(os.close(file))

    // Fill header information
    fmt.fprintf(file, "P3\n%d %d\n255\n", COLS, ROWS)

    // Other vars
    lower_left_corner : Vec3 = { -2, -1, -1 }
    color_blue : Color = { 0, 0, 1 }
    color__white : Color = { 1, 1, 1 }

    // Write image data
    for y in 0..<ROWS {
        v : f64 = f64(y)/f64(ROWS)
        for x in 0..<COLS {
            u : f64 = f64(x)/f64(COLS)
            ray : Ray = {ZERO, linalg.normalize(lower_left_corner + u*RIGHT + v*UP)}
            print_color(file, lerp_2_color_ray_on_y(color_blue, color__white, ray))
        }
        fmt.fprintfln(file, "")
    }

    fmt.println("Finished!")
}

// Utils
print_color :: proc(file : os.Handle, color : Color) {
    norm_scaled_color := color * f64(255.99)
    fmt.fprintf(file, "%d %d %d ", u8(norm_scaled_color.x), u8(norm_scaled_color.y), u8(norm_scaled_color.z))
}
