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

MaterialType :: enum {
    Lambertian,
    Metalic,
    //Dieletric
}

LambertianData :: struct {
    albedo : Vec3,
}

MetalicData :: struct {
    albedo : Vec3,
    fuzziness: f64
}

Material :: struct {
    type : MaterialType,
    data : rawptr
}

ScatterProc :: #type proc (ray : Ray, hit : HitRecord, data : rawptr) -> (bool, Ray, Color)
ScatterTable := [MaterialType]ScatterProc {
    .Lambertian = scatter_lambertian,
    .Metalic = scatter_metalic,
    //.Dielectric = scatter_dielectric,
}

HitRecord :: struct {
    hitted : Sphere,
    pos : Pos3,
    normal : Vec3,
    root : f64,
    does_hit : bool,
}

Sphere :: struct {
    pos : Pos3,
    radius : f64,
    material : Material
}

// Defaults
FORWARD : Vec3 = { 0, 0, 1 }
RIGHT : Vec3 = { 1, 0, 0 }
UP : Vec3 =  { 0, 1, 0 }

ZERO : Vec3 =  { 0, 0, 0 }
ONE : Vec3 =  { 1, 1, 1 }

CAMERA_POS := ZERO

default_lambertian_data_test_ : LambertianData = {
    albedo = { 1, 0, 1 }
}

default_metal_data_test_ : MetalicData = {
    albedo = { 1, 0, 1 },
    fuzziness = .1
}

default_lambertian_material_test_ : Material = {
    type = .Lambertian,
    data = &default_lambertian_data_test_
}

default_metalic_material_test_ : Material = {
    type = .Metalic,
    data = &default_metal_data_test_
}

default_material_test_ := default_metalic_material_test_

// Spheres - I don't wanna sort from backwards so keep it sorted - closer to furter in reference to the camera
spheres : []Sphere = {
    {
        pos = (FORWARD * 4),
        radius = 2,
        material = default_material_test_,
    },
    {
        pos = (FORWARD * 5) + (UP * -23),
        radius = 20,
        material = default_material_test_,
    },
    {
        pos = (FORWARD * 8) + (RIGHT * 10) + (UP * -4),
        radius = 2.6,
        material = default_material_test_,
    },
    {
        pos = (FORWARD * 10) + (RIGHT * 10) + (UP * 4),
        radius = 1.6,
        material = default_material_test_
    },
    {
        pos = (FORWARD * 14) + (RIGHT * -7) + (UP * -4),
        radius = 3.4,
        material = default_material_test_,
    },
}

// Background
color_blue : Color = { 0, 0, 1 }
color_white : Color = { 1, 1, 1 }
color_magenta : Color = { 1, 0, 1 }

color_top : Color = { 1, 1, 1 }
color_bottom : Color = { 0, 0, 1 }
SURFACE_REFLECTION : f64 = .4

// Antialliasing
samples_count := 100

// T Cap
T_MIN :: 0.001
T_MAX :: math.F64_MAX

// Raycast cap
MAX_DEPTH_RAYCASTING :: 50

// Material procedures
scatter_lambertian :: proc(ray : Ray, hit : HitRecord, data : rawptr) -> (bool, Ray, Color) {
    material := (^LambertianData)(data)
    target : Vec3 = hit.pos + hit.normal + rand_point_in_sphere_any()
    scattered : Ray = { hit.pos, target - hit.pos }
    attenuation : Pos3 = material.albedo
    return true, scattered, attenuation
}

scatter_metalic :: proc(ray : Ray, hit : HitRecord, data : rawptr) -> (bool, Ray, Color) {
    material := (^MetalicData)(data)

    normalized_dir := linalg.normalize(ray.dir)
    reflect_dir : Vec3 = normalized_dir - 2 * linalg.dot(normalized_dir, hit.normal) * hit.normal

    scattered : Ray = { hit.pos, reflect_dir + material.fuzziness * rand_point_in_sphere_any() }
    attenuation : Pos3 = material.albedo
    did_hit : bool = (linalg.dot(scattered.dir, hit.normal) > 0)
    return did_hit, scattered, attenuation
}

// Procedures
ray_point_at :: proc(ray : Ray, t : f64) -> Pos3 {
    return ray.pos + ray.dir * t
}

ray_hit_sphere :: proc(ray : Ray, sphere : Sphere) -> (bool, f64) {
    oc := ray.pos - sphere.pos

    a := linalg.dot(ray.dir, ray.dir)
    half_b := linalg.dot(oc, ray.dir)
    c := linalg.dot(oc, oc) - sphere.radius * sphere.radius

    discriminant := half_b * half_b - a * c

    if discriminant < 0 {
        return false, -1
    }

    sqrtd := math.sqrt(discriminant)

    // Finds the nearest root that lies in the acceptable range.
    root := (-half_b - sqrtd) / a

    if root < 0.001 {
        root = (-half_b + sqrtd) / a
        if root < 0.001 {
            return false, -1 // Both intersections are behind the camera
        }
    }

    // Cap t
    if root < T_MIN || root > T_MAX {
        return false, -1
    }

    return true, root
}

ray_hit_world :: proc (ray : Ray) -> HitRecord {
    record : HitRecord = { does_hit = false }
    best_dist := math.F64_MAX
    for sphere in spheres {
        does_hit, hit_t := ray_hit_sphere(ray, sphere)
        if does_hit {
            dist := linalg.distance(CAMERA_POS, sphere.pos)
            if dist < best_dist {
                best_dist = dist
                record = {
                    hitted = sphere,
                    pos = ray_point_at(ray, hit_t),
                    root = hit_t,
                    does_hit = true
                }
                record.normal = linalg.normalize(record.pos - sphere.pos)
            }
        }
    }
    return record
}

lerp_2_color_ray_on_y :: proc(color1, color2 : Color, ray : Ray) -> Color {
    unit_vector := linalg.normalize(ray.dir)
    t := 0.5 * (unit_vector.y + 1.0)
    return ((1.0-t) * color1 + (t * color2))
}

print_color :: proc(file : os.Handle, color : Color) {
    norm_scaled_color := linalg.sqrt(color) * f64(255.99)
    fmt.fprintf(file, "%d %d %d ", u8(norm_scaled_color.x), u8(norm_scaled_color.y), u8(norm_scaled_color.z))
}

rand_point_in_sphere :: proc(sphere : Sphere) -> Pos3 {
    rng_y := rand.float64_range(-1, 1)
    r := math.sqrt(1 - linalg.pow(rng_y, 2))
    long := rand.float64_range(-linalg.PI , linalg.PI)
    point_on_sphere : Pos3 = { r * linalg.sin(long), rng_y, r * linalg.cos(long) }
    point_in_sphere : Pos3 = sphere.pos + sphere.radius * point_on_sphere * linalg.pow(rand.float64_range(0, 1), 1/3)
    return point_on_sphere
}

rand_point_in_sphere_any :: proc() -> Pos3 {
    rng_y := rand.float64_range(-1, 1)
    r := math.sqrt(1 - linalg.pow(rng_y, 2))
    long := rand.float64_range(-linalg.PI , linalg.PI)
    point_on_sphere : Pos3 = { r * linalg.sin(long), rng_y, r * linalg.cos(long) }
    point_in_sphere : Pos3 = point_on_sphere * linalg.pow(rand.float64_range(0, 1), 1/3)
    return linalg.normalize(point_in_sphere)
}

color :: proc(ray : Ray, depth : u32) -> Color {
    record : HitRecord = ray_hit_world(ray)
    if record.does_hit {
        should_scatter, scattered, attenuation := ScatterTable[record.hitted.material.type](ray, record, record.hitted.material.data)
        if should_scatter && depth < MAX_DEPTH_RAYCASTING {
            return attenuation*color(scattered, depth + 1)* .5
        } else {
            return { 0, 0, 0 }
        }
    }
    return lerp_2_color_ray_on_y(color_blue, color_white, ray)
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
    file, error := os.open(filepath, os.O_WRONLY | os.O_CREATE)
    if error != nil {
        fmt.eprintln("Error: ", error)
        return;
    }
    defer(os.close(file))

    // Fill header information
    fmt.fprintf(file, "P3\n%d %d\n255\n", WIDTH, HEIGHT)

    // Camera
    aspect_ratio := f64(WIDTH)/f64(HEIGHT)
    viewport_height := 2.0
    viewport_width := viewport_height * aspect_ratio

    origin := CAMERA_POS
    horizontal : Vec3 = RIGHT * viewport_width
    vertical : Vec3 = UP * viewport_height
    lower_left_corner : Vec3 = origin - (horizontal/2) - (vertical/2) + FORWARD

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
                sample_color := color(eye_ray, 0)

                final_color += sample_color
            }
            final_color /= f64(samples_count)
            print_color(file, final_color)
        }
        fmt.fprintfln(file, "")
    }

    fmt.println("Finished!")
}
