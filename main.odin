package main

import "core:os"
import "core:fmt"
import "core:math"
import "core:image"
import "core:thread"
import "core:strings"
import "core:math/rand"
import "core:math/linalg"
import "core:image/netpbm"
import stb_image "vendor:stb/image"

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
    Dielectric
}

LambertianData :: struct {
    albedo : Vec3,
}

MetalicData :: struct {
    albedo : Vec3,
    fuzziness: f64
}

DieletricData :: struct {
    reflectiviness: f64
}

Material :: struct {
    type : MaterialType,
    data : rawptr
}

ScatterProc :: #type proc (ray : Ray, hit : HitRecord, data : rawptr) -> (bool, Ray, Color)
ScatterTable := [MaterialType]ScatterProc {
    .Lambertian = scatter_lambertian,
    .Metalic = scatter_metalic,
    .Dielectric = scatter_dielectric,
}

GenRandomMaterial :: #type proc () -> (rawptr)
GenRandomMaterialTable := [MaterialType]GenRandomMaterial {
    .Lambertian = random_lambertian,
    .Metalic = random_metalic,
    .Dielectric = random_dielectric,
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

ThreadData :: struct {
    begin_idx : u64,
    end_idx : u64,
    data : []Color
}

// Defaults
FORWARD : Vec3 = { 0, 0, 1 }
RIGHT : Vec3 = { 1, 0, 0 }
UP : Vec3 =  { 0, 1, 0 }

ZERO : Vec3 =  { 0, 0, 0 }
ONE : Vec3 =  { 1, 1, 1 }

// Background
color_blue : Color = { 0, 0, 1 }
color_white : Color = { 1, 1, 1 }
color_magenta : Color = { 1, 0, 1 }

// T Cap
T_MIN :: 0.001
T_MAX :: math.F64_MAX

// Image quality
WIDTH :: 2560
HEIGHT :: 1440
//WIDTH :: 400
//HEIGHT :: 200

SAMPLES_COUNT := 100
MAX_DEPTH_RAYCASTING :: 50
RANDOM_SPHERES_COUNT :: 100

// Camera
CameraInfo :: struct {
    aspect_ratio : f64,
    viewport_height : f64,
    viewport_width : f64,
    origin : Pos3,
    horizontal : Vec3,
    vertical : Vec3,
    top_left_corner : Vec3
}

camera : CameraInfo

// Random generation of spheres
spheres :[dynamic]Sphere;

PIXEL_COUNT :: WIDTH * HEIGHT
FILE_BUFFER : [PIXEL_COUNT]Color

MIN_DIST : f64 = -2
MAX_DIST : f64 = 2

MIN_RADIUS : f64 = .1
MAX_RADIUS : f64 = .2

// Config ppm
FILEPATH := "./out.ppm"

// Random generation
rng_0_1 :: proc() -> f64 {
    return rand.float64_range(0,1)
}

rng_pos1_neg1 :: proc() -> i32 {
    if rand.int31() % 2 == 0 {
        return 1
    }
    return -1
}

random_color :: proc() -> Color {
    return { rng_0_1(), rng_0_1(), rng_0_1() }
}

random_material :: proc() -> Material {
	material_type := rand.choice_enum(MaterialType)
    mat_ptr := GenRandomMaterialTable[material_type]();
    return {
        type = material_type,
        data = mat_ptr
    }
}

random_lambertian :: proc() -> rawptr {
    lamb := new(LambertianData)
    lamb.albedo = random_color()
    return rawptr(lamb)
}

random_metalic :: proc() -> rawptr {
    met := new(MetalicData)
    met.albedo = random_color()
    met.fuzziness = rand.float64()
    return rawptr(met)
}

random_dielectric :: proc() -> rawptr {
    diel := new(DieletricData)
    diel.reflectiviness = rand.float64_range(1, 3)
    return rawptr(diel)
}

random_sphere :: proc() -> Sphere {
    return {
        pos = ZERO + rand_point_in_sphere_any() * rand.float64_range(MIN_DIST, MAX_DIST),
        radius = rand.float64_range(MIN_RADIUS, MAX_RADIUS),
        material = random_material()
    }
}

// Material procedures
schlick_aprox :: proc(cos, ref : f64) -> f64 {
    r0 := (1-ref)/(1+ref)
    r0 = r0*r0
    return r0 + (1-r0)* math.pow(1-cos, 5)
}

reflect :: proc(ray_dir, normal : Vec3) -> Vec3 {
    n_ray_dir := linalg.normalize(ray_dir)
    return n_ray_dir - 2 * linalg.dot(n_ray_dir, normal) * normal
}

refract :: proc(ray_dir, normal : Vec3, ni_over_nt : f64) -> (bool, Vec3) {
    uv := linalg.normalize(ray_dir)
    dt : f64 = linalg.dot(uv, normal)
    discriminant := 1.0 - ni_over_nt*ni_over_nt *(1-dt*dt)
    if discriminant > 0 {
        refracted := ni_over_nt * (uv - normal * dt) - normal * math.sqrt(discriminant)
        return true, refracted
    }
    return false, ZERO
}

scatter_lambertian :: proc(ray : Ray, hit : HitRecord, data : rawptr) -> (bool, Ray, Color) {
    material := (^LambertianData)(data)
    target : Vec3 = hit.pos + hit.normal + rand_point_in_sphere_any()
    scattered : Ray = { hit.pos, target - hit.pos }
    attenuation : Vec3 = material.albedo
    return true, scattered, attenuation
}

scatter_metalic :: proc(ray : Ray, hit : HitRecord, data : rawptr) -> (bool, Ray, Color) {
    material := (^MetalicData)(data)

    reflect_dir : Vec3 = reflect(ray.dir, hit.normal)

    scattered : Ray = { hit.pos, reflect_dir + material.fuzziness * rand_point_in_sphere_any() }
    attenuation : Pos3 = material.albedo
    did_hit : bool = (linalg.dot(scattered.dir, hit.normal) > 0)
    return did_hit, scattered, attenuation
}

scatter_dielectric :: proc(ray : Ray, hit : HitRecord, data : rawptr) -> (bool, Ray, Color) {
    material := (^DieletricData)(data)

    outward_normal : Vec3
    ni_over_nt : f64
    attenuation : Vec3 = ONE
    scattered : Ray
    reflected : Vec3 = reflect(ray.dir, hit.normal)

    cos, reflect_prob : f64

    if linalg.dot(ray.dir, hit.normal) > 0 {
        outward_normal = - hit.normal
        ni_over_nt = material.reflectiviness
        cos = material.reflectiviness * linalg.dot(ray.dir, hit.normal) / linalg.length(ray.dir)
    } else {
        outward_normal = hit.normal
        ni_over_nt = 1.0 / material.reflectiviness
        cos = - linalg.dot(ray.dir, hit.normal) / linalg.length(ray.dir)
    }

    did_refract, refracted := refract(ray.dir, outward_normal, ni_over_nt)
    if did_refract {
        reflect_prob = schlick_aprox(cos, material.reflectiviness)
    } else {
        scattered = { hit.pos, reflected }
        reflect_prob = 1.0
    }

    if rand.float64_range(0, 1) < reflect_prob {
        scattered = { hit.pos, reflected }
    } else {
        scattered = { hit.pos, refracted }
    }
    return true, scattered, attenuation
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
    closest_hit := math.F64_MAX
    for sphere in spheres {
        does_hit, hit_t := ray_hit_sphere(ray, sphere)
        if does_hit && hit_t < closest_hit {
            closest_hit = hit_t
            record = {
                hitted = sphere,
                pos = ray_point_at(ray, hit_t),
                root = hit_t,
                does_hit = true
            }
            record.normal = linalg.normalize(record.pos - sphere.pos)
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
            return attenuation*color(scattered, depth + 1)
        } else {
            return ZERO
        }
    }
    return lerp_2_color_ray_on_y(color_blue, color_white, ray)
}

cast_rays_per_thread :: proc(t: ^thread.Thread) {
    thread_data := (^ThreadData)(t.data)

    for local_y in thread_data.begin_idx..<thread_data.end_idx {
        for x in 0..<WIDTH {
            // Aa sampling
            final_color := ZERO;
            for s in 0..<SAMPLES_COUNT {
                // Ray
                u : f64 = ((f64(x) + rand.float64()) /f64(WIDTH - 1))
                v : f64 = 1 - ((f64(local_y) + rand.float64()) /f64(HEIGHT - 1))

                target_pixel := camera.top_left_corner + u*camera.horizontal + v*camera.vertical
                eye_ray : Ray = { camera.origin, linalg.normalize(target_pixel - camera.origin) }
                sample_color := color(eye_ray, 0)

                final_color += sample_color
            }
            final_color /= f64(SAMPLES_COUNT)

            pixel_index := ((local_y - thread_data.begin_idx) * WIDTH) + u64(x)

            thread_data.data[pixel_index] = final_color
        }
    }
}

ppm_to_png :: proc(ppm_filepath, png_filepath : string) {
    // Load the PPM file
    ppm_img, error := netpbm.load_from_file(ppm_filepath)
    if error != nil {
        fmt.eprintln("Error loading PPM:", error)
        return
    }
    defer image.destroy(ppm_img)

    c_str := strings.clone_to_cstring(png_filepath, context.temp_allocator)

    // Save as png
    success := stb_image.write_png(
        c_str,
        i32(ppm_img.width),
        i32(ppm_img.height),
        i32(ppm_img.channels),
        raw_data(ppm_img.pixels.buf),
        i32(ppm_img.width * ppm_img.channels),
    )

    if success == 0 {
        fmt.eprintln("Failed to save PNG")
    } else {
        fmt.println("Successfully converted PPM to PNG!")
    }
}

write_camera_data :: proc(look_from, look_at : Pos3, vertical_fov_deg : f64) {
    camera.origin = look_from
    camera.aspect_ratio = f64(WIDTH)/f64(HEIGHT)

    theta := vertical_fov_deg*math.PI/180
    half_height := math.tan(theta/2)
    half_width := camera.aspect_ratio * half_height

    w := linalg.normalize(look_from - look_at)
    u := linalg.normalize(linalg.cross(UP, w))
    v := linalg.cross(w, u)

    camera.top_left_corner = camera.origin - (half_width*u) + (half_height*v) - w
    camera.horizontal = 2 * half_width * u
    camera.vertical = -2 * half_height * v
}

// Entry point
main :: proc() {
    fmt.printfln(" --- Begining process!")
    fmt.printfln("Quality params:")
    fmt.printfln("Image - [ Width: {} - Height: {} ]", WIDTH, HEIGHT)
    fmt.printfln("Ray - [ Ray max depth: {} ]", MAX_DEPTH_RAYCASTING)
    fmt.printfln("Multsampling - [ Sample count(per pixel): {} ]", SAMPLES_COUNT)

    write_camera_data((ZERO) + (FORWARD * -2) + (UP * -2), FORWARD, 90)

    fmt.println(" --- Generating random spheres.")
    // Prepare for random generation
    spheres = make([dynamic]Sphere)
    defer {
        for sphere in spheres {
            free(sphere.material.data)
        }
        delete(spheres)
    }

    // Create a sphere to provide the image base
    BASE_SIZE : f64 = 1000
    base_data := new(LambertianData)
    base_data.albedo = { .3, 0, .3 }
    base_sphere : Sphere = {
        pos = { 0, -BASE_SIZE, 0 },
        radius = BASE_SIZE,
        material = {
            type = MaterialType.Lambertian,
            data = rawptr(base_data)
        }
    }
    append(&spheres, base_sphere)

    // Fill in the other spheres
    FILL_SPHERE_ROOT := ZERO + (FORWARD * -1)
    idx := 1
    sqrt_spheres_count := math.sqrt(f64(RANDOM_SPHERES_COUNT))
    spheres_count_rest := RANDOM_SPHERES_COUNT - sqrt_spheres_count
    for i in 0..<sqrt_spheres_count {
        for j in 0..<spheres_count_rest {
            append(&spheres, random_sphere())
            rng_1 := rng_0_1()
            rng_2 := 1.0 - rng_1
            radius := spheres[idx].radius
            rng_pos : Pos3 = FILL_SPHERE_ROOT +
                (UP * radius) + (RIGHT * (j * rng_1 * f64(rng_pos1_neg1()))) + (FORWARD * (i * rng_2 * f64(rng_pos1_neg1())))
                //(FORWARD * spheres[i].radius * rng_1 * f64(i) * f64(rng_pos1_neg1())) +
                //(RIGHT * spheres[i].radius * rng_2 * f64(i) * f64(rng_pos1_neg1()))
            spheres[idx].pos = rng_pos
            idx+=1
        }
    }

    fmt.println(" --- Create threads.")
    THREAD_COUNT :: 12
    threads_data : [THREAD_COUNT]ThreadData
    // Break down tasks
    task_size : u64 = HEIGHT / THREAD_COUNT
    for t in 0..<THREAD_COUNT {
        start_y := u64(t) * task_size
        end_y   := start_y + task_size

        // Handle the remainder rows for the last thread
        if t == THREAD_COUNT - 1 {
            end_y = HEIGHT
        }

        // Calculate the slice range
        start_index := start_y * WIDTH
        end_index := end_y * WIDTH

        threads_data[t] = {
            begin_idx = start_y,
            end_idx = end_y,
            data = FILE_BUFFER[start_index:end_index]
        }
    }

    // Create threads
    threads : [THREAD_COUNT]^thread.Thread

    fmt.println(" --- Dispatching threads.")
    // Dispatch threads
    for i in 0..<THREAD_COUNT {
        threads[i] = thread.create(cast_rays_per_thread)
        threads[i].data = &threads_data[i]
        thread.start(threads[i])
    }

    // Wait for all threads
    for t in threads {
        thread.join(t)
        thread.destroy(t)
    }

    fmt.println(" --- Writing to file.")
    // Open file
    file, error := os.open(FILEPATH, os.O_WRONLY | os.O_CREATE)
    if error != nil {
        fmt.eprintln("Error: ", error)
        return;
    }
    defer(os.close(file))

    // Fill header information
    fmt.fprintf(file, "P3\n%d %d\n255\n", WIDTH, HEIGHT)

    // Write image data
    for y in 0..<HEIGHT {
        for x in 0..<WIDTH {
            idx := y*WIDTH + x
            print_color(file, FILE_BUFFER[idx])
        }
        fmt.fprintfln(file, "")
    }

    fmt.println("Finished!")
}
