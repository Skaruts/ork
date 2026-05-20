package ork

import "core:math"
import "core:math/noise"

NoiseMap2D :: []f32

new_noise_map_2d :: proc(w, h: int, scale: f32, octaves: int = 1,
                         persistence: f32 = 0.5, lacunarity :f32 = 2
                        ) -> ^NoiseMap2D {

	noise_map := new(NoiseMap2D)
	noise_map^ = make(NoiseMap2D, w*h)

	max_height : f32 = -math.INF_F32
	min_height : f32 =  math.INF_F32

	for j in 0 ..< h {
		for i in 0 ..< w {
			idx := i+j*w

			amplitude    := f32(1.0)
			frequency    := f32(1.0)
			noise_height := f32(0.0)

			for o in 0 ..< octaves {
				x := f32(i) / scale * frequency
				y := f32(j) / scale * frequency

				val := noise.noise_2d(i64(internal.rng_seed), {f64(x), f64(y)})
				noise_height += val * amplitude

				amplitude *= persistence
				frequency *= lacunarity
			}
			noise_map[idx] = noise_height

			if noise_height > max_height do max_height = noise_height
			if noise_height < min_height do min_height = noise_height
		}
	}

	for i in 0 ..< w*h {
		noise_map[i] = math.unlerp(min_height, max_height, noise_map[i])
	}

	append(&internal.noise_map_2ds, noise_map)
	return noise_map
}


delete_noise_map_2d :: proc(noise_map: ^NoiseMap2D, loc:=#caller_location) {
	if noise_map == nil do return
	idx, ok := _get_item_index(internal.noise_map_2ds[:], noise_map)
	if ok do unordered_remove(&internal.noise_map_2ds, idx)
	delete(noise_map^)
	free(noise_map)
}

// @private
// _destroy_all_noise_maps :: proc() {
// 	for len(internal.noise_map_2ds) > 0 {
// 		nm := internal.noise_map_2ds[0]
// 		delete_noise_map_2d(&nm)
// 	}
// 	delete(internal.noise_map_2ds)
// }
