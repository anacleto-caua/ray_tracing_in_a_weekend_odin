package main

import "core:os"
import "core:fmt"
import "core:math/linalg"

// Types
Color :: struct {
    r: u8,
    g: u8,
    b: u8
}

Vec3 :: linalg.Vector3f64;
Pos3 :: linalg.Vector3f64;

Ray :: struct {
    pos : Pos3,
    dir : Vec3
}

// Defaults
FORWARD : Vec3 = { 0, 0, 1 };
RIGHT : Vec3 = { 1, 0, 0 };
UP : Vec3 =  { 0, 1, 0 };

ZERO : Vec3 =  { 0, 0, 0 };
ONE : Vec3 =  { 1, 1, 1 };

cast_ray :: proc (ray: Ray, t : f64) -> Pos3 {
    return ray.pos + ray.dir * t;
}

main :: proc() {

    // Config ppm
    filepath := "./out.ppm";
    COLS :: 640;
    ROWS :: 480;

    // Open file
    file, error := os.open(filepath, os.O_RDWR);
    if error != nil {
        fmt.eprintln("Error: {}", error);
        return;
    }
    defer(os.close(file));

    // Fill header information
    fmt.fprintf(file, "P3\n%d %d\n255\n", COLS, ROWS);

    // Write image data
    color_ : Color = {r = 0, g = 0, b = 0};
    for y in 0..<ROWS {
        color_.r = u8(f32(255) * f32(y)/f32(ROWS));
        for x in 0..<COLS {
            color_.g = u8(f32(255) * f32(x)/f32(COLS));
            color_.b = u8(f32(255) * f32(y*x)/f32(COLS * ROWS));
            print_color(file, color_);
        }
        fmt.fprintfln(file, "");
    }

    fmt.println("Finished!");
}

print_color :: proc(file : os.Handle, color : Color) {
    fmt.fprintf(file, "%d %d %d ", color.r, color.g, color.b);
}
