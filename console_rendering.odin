package ork

import "core:math"
import rl "vendor:raylib"

FRAG_SHADER_PATH := #load("res/console_shader.fs")

_shader_loc :: proc(shader:rl.Shader, property:cstring) -> rl.ShaderLocationIndex {
	return rl.ShaderLocationIndex(rl.GetShaderLocation(shader, property))
}

_console_destroy_shader_rendering :: proc(c: ^Console, rend: ^RenderingData) {
	rl.UnloadShader(rend.shader)
	rl.UnloadTexture(rend.shader_tex)
	rl.UnloadTexture(rend.fg_tex)
	rl.UnloadTexture(rend.char_tex)
	rl.UnloadImage(rend.fg_img)
	rl.UnloadImage(rend.char_img)
}

_console_init_shader_rendering :: proc(c: ^Console, rend: ^RenderingData, is_reset: bool) {
	cw, ch := get_cell_size(c)

	rend.shader = rl.LoadShaderFromMemory(nil, cstring(raw_data(FRAG_SHADER_PATH)))

	img := rl.GenImageColor(i32(c.w*cw), i32(c.h*ch), rl.LIME)  // color is arbitray
	rend.shader_tex = rl.LoadTextureFromImage(img)
	rl.UnloadImage(img)

	c._bg_img  = rl.GenImageColor(i32(c.w), i32(c.h), rl.RED)   // color is arbitray
	rend.fg_img  = rl.GenImageColor(i32(c.w), i32(c.h), rl.GREEN) // color is arbitray
	rend.char_img = rl.GenImageColor(i32(c.w), i32(c.h), rl.BLUE)  // color is arbitray
	c._bg_tex  = rl.LoadTextureFromImage(c._bg_img)
	rend.fg_tex  = rl.LoadTextureFromImage(rend.fg_img)
	rend.char_tex = rl.LoadTextureFromImage(rend.char_img)

	grid_size := Vec2f{ f32(c.w), f32(c.h) }
	font_size := Vec2f{ f32(c._font.cols), f32(c._font.rows) }
	cell_size := Vec2f{f32(cw), f32(ch)}

	rl.SetShaderValueV(rend.shader, _shader_loc(rend.shader, "console_size"), &grid_size, .VEC2, 1)
	rl.SetShaderValueV(rend.shader, _shader_loc(rend.shader, "font_sizet"), &font_size, .VEC2, 1)
	rl.SetShaderValueV(rend.shader, _shader_loc(rend.shader, "cell_size"), &cell_size, .VEC2, 1)

	rl.SetShaderValueTexture(rend.shader, _shader_loc(rend.shader, "font"),    c._font.texture)
	rl.SetShaderValueTexture(rend.shader, _shader_loc(rend.shader, "bg_tex"),  c._bg_tex)
	rl.SetShaderValueTexture(rend.shader, _shader_loc(rend.shader, "fg_tex"),  rend.fg_tex)
	rl.SetShaderValueTexture(rend.shader, _shader_loc(rend.shader, "chr_tex"), rend.char_tex)
}


_console_update_shader_rendering :: proc(c:^Console, rend: ^RenderingData) {
	for j in 0..<i32(c.h) {
		for i in 0..<i32(c.w) {
			idx := int(i)+int(j)*c.w
			ng, nfg, nbg := c._new_cells.glyphs[idx], c._new_cells.fgs[idx], c._new_cells.bgs[idx]
			og, ofg, obg := c._cells.glyphs[idx], c._cells.fgs[idx], c._cells.bgs[idx]

			if nbg != obg {
				rl.ImageDrawPixel(&c._bg_img,  i, j, nbg)
				c._cells.bgs[idx] = nbg
			}

			if nfg != ofg {
				rl.ImageDrawPixel(&rend.fg_img,  i, j, nfg)
				c._cells.fgs[idx] = nfg
			}

			if ng != og {
				// glyph value encoded in two color channels
				// TODO: might be worth considering other color formats for this?
				r := u8(math.min(255, ng))
				g := u8(math.max(0, (int(ng)-255))) // convert 'ng' to int or else it will wrap around, because it's unsigned
				rl.ImageDrawPixel(&rend.char_img, i, j, {r, g, 0, 255})
				c._cells.glyphs[idx] = ng
			}
		}
	}

	rl.UpdateTexture(c._bg_tex, c._bg_img.data)
	rl.UpdateTexture(rend.fg_tex, rend.fg_img.data)
	rl.UpdateTexture(rend.char_tex, rend.char_img.data)
}

_console_render_shader :: proc(c:^Console, rend: ^RenderingData) {
	rl.BeginShaderMode(rend.shader)
	{
		rl.SetShaderValueTexture(rend.shader, _shader_loc(rend.shader, "font"),    c._font.texture)
		rl.SetShaderValueTexture(rend.shader, _shader_loc(rend.shader, "bg_tex"),  c._bg_tex)
		rl.SetShaderValueTexture(rend.shader, _shader_loc(rend.shader, "fg_tex"),  rend.fg_tex)
		rl.SetShaderValueTexture(rend.shader, _shader_loc(rend.shader, "chr_tex"), rend.char_tex)

		rl.DrawTexture(rend.shader_tex, i32(c.x), i32(c.y), rl.WHITE)
	}
	rl.EndShaderMode()

}
