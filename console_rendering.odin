package ork


import "core:math"
import k2 "libs/karl2d"



@private _set_pixel :: proc(pixels: []u8, idx: int, color: Color) {
	idx := idx*CHANNELS
	pixels[idx+0] = color.r
	pixels[idx+1] = color.g
	pixels[idx+2] = color.b
	pixels[idx+3] = color.a
}


/*******************************************************************************

		Shader Rendering (super fast)

*******************************************************************************/
@private _destroy_shader_rendering :: proc(c: ^Console, rend: ^Shader_Rendering) {
	free_all(c._rend_allocator)
	if rend.shader.handle.idx != 0 {
		k2.destroy_shader(rend.shader)
	}
	k2.destroy_texture(rend.shader_tex)
	k2.destroy_texture(rend.fg_tex)
	k2.destroy_texture(rend.char_tex)
}


@private _init_shader_rendering :: proc(c: ^Console, rend: ^Shader_Rendering, is_reset: bool) {
	state := internal.k2_state

	rend.shader = k2.load_shader_from_bytes(
		state.render_backend.default_shader_vertex_source(),
		#load("res/console_shader.glsl"),
	)

	shader := &rend.shader
	cw, ch := get_cell_size(c)

	rend.fg_pixels   = make([]u8, c.w*c.h*CHANNELS, c._rend_allocator)
	rend.char_pixels = make([]u8, c.w*c.h*CHANNELS, c._rend_allocator)
	rend.fg_tex     = k2.create_texture(c.w, c.h, .RGBA_8_Norm)
	rend.char_tex   = k2.create_texture(c.w, c.h, .RGBA_8_Norm)
	rend.shader_tex = k2.create_texture(c.w*cw, c.h*ch, .RGBA_8_Norm)

	console_size_loc  := shader.constant_lookup["console_size"]
	font_sizet_loc    := shader.constant_lookup["font_sizet"]
	cell_size_loc     := shader.constant_lookup["cell_size"]

	k2.set_shader_constant(shader^, console_size_loc,  Vec2f{f32(c.w), f32(c.h)})
	k2.set_shader_constant(shader^, font_sizet_loc, Vec2f{f32(c._font.cols), f32(c._font.rows)})
	k2.set_shader_constant(shader^, cell_size_loc,     Vec2f{f32(cw), f32(ch)})
	shader.texture_bindpoints[shader.texture_lookup["font"]] = c._font.texture.handle
	shader.texture_bindpoints[shader.texture_lookup["bg_tex"]] = c._bg_tex.handle
	shader.texture_bindpoints[shader.texture_lookup["fg_tex"]] = rend.fg_tex.handle
	shader.texture_bindpoints[shader.texture_lookup["chr_tex"]] = rend.char_tex.handle
}


@private _update_shader_rendering :: proc(c: ^Console, rend: ^Shader_Rendering) {
	updated_bgs := 0
	updated_fgs := 0
	updated_glyphs := 0

	for j in 0 ..< c.h {
		for i in 0 ..< c.w {
			idx := i+j*c.w
			ng, nfg, nbg := c._new_cells.glyphs[idx], c._new_cells.fgs[idx], c._new_cells.bgs[idx]
			og, ofg, obg := c._cells.glyphs[idx], c._cells.fgs[idx], c._cells.bgs[idx]

			if nbg != obg {
				c._cells.bgs[idx] = nbg
				updated_bgs += 1
				_set_pixel(c._bg_pixels, idx, nbg)
			}

			if nfg != ofg {
				c._cells.fgs[idx] = nfg
				updated_fgs += 1
				_set_pixel(rend.fg_pixels, idx, nfg)
			}

			if ng != og {
				c._cells.glyphs[idx] = ng
				updated_glyphs += 1
				// glyph value encoded into two color channels
				// TODO: might be worth considering other color formats for this?
				r := u8(math.min(255, ng))
				g := u8(math.max(0, (int(ng)-255))) // convert 'ng' to int or else it will wrap around, because it's unsigned
				_set_pixel(rend.char_pixels, idx, {r, g, 0, 255})
			}
		}
	}

	rect := k2.get_texture_rect(c._bg_tex)
	if updated_bgs > 0 {
		k2.update_texture(c._bg_tex, c._bg_pixels, rect)
	}

	if updated_fgs > 0 {
		k2.update_texture(rend.fg_tex, rend.fg_pixels, rect)
	}

	if updated_glyphs > 0 {
		k2.update_texture(rend.char_tex, rend.char_pixels, rect)
	}
}


@private _render_shader_rendering :: proc(c:^Console, rend: ^Shader_Rendering) {
	cw, ch := get_cell_size(c)

	k2.set_shader(rend.shader)
	{
		k2.draw_texture(rend.shader_tex, {})
	}
	k2.set_shader(nil)
}




/*******************************************************************************

		Batch Rendering (very slow)

*******************************************************************************/
@private _destroy_batch_rendering :: proc(c: ^Console, rend: ^Batch_Rendering) {
	free_all(c._rend_allocator)
}

@private _init_batch_rendering :: proc(c: ^Console, rend: ^Batch_Rendering, is_reset: bool) {	cw, ch := get_cell_size(c)
	cols := c._font.cols
	rows := c._font.rows

	rend.verts  = make([]Vec2f, c.w * c.h * 6, c._rend_allocator)
	rend.uvs    = make([]Vec2f, c.w * c.h * 6, c._rend_allocator)
	rend.colors = make([]Color, c.w * c.h,     c._rend_allocator)

	rend.font_uvs = make([]Vec2f, int(cols * rows * 6), c._rend_allocator)

	for j in 0 ..< c.h {
		for i in 0 ..< c.w {
			idx := i+j*c.w
			x := i*cw
			y := j*ch

			//   A ------ B
			//   |  \     |    ABC ACD
			//   |     \  |
			//   D ------ C

			v_a := Vec2f{ f32(x),    f32(y)    }
			v_b := Vec2f{ f32(x+cw), f32(y)    }
			v_c := Vec2f{ f32(x+cw), f32(y+ch) }
			v_d := Vec2f{ f32(x),    f32(y+ch) }

			v_idx := idx*6
			rend.verts[v_idx+0] = v_a
			rend.verts[v_idx+1] = v_b
			rend.verts[v_idx+2] = v_c
			rend.verts[v_idx+3] = v_a
			rend.verts[v_idx+4] = v_c
			rend.verts[v_idx+5] = v_d
		}
	}

	/*    Precompute UVs    */
	uvw: f32 = 1.0/f32(cols)  // uv size (cell size normalized) -  1 / columns
	uvh: f32 = 1.0/f32(rows)  // uv size (cell size normalized) -  1 / rows

	for j in 0 ..< rows {
		for i in 0 ..< cols {
			glyph := i+j*cols
			idx := glyph * 6

			u := f32(i) / f32(cols)
			v := f32(j) / f32(rows)

			uv_a := Vec2f{ u,       v       }
			uv_b := Vec2f{ u + uvw, v       }
			uv_c := Vec2f{ u + uvw, v + uvh }
			uv_d := Vec2f{ u,       v + uvh }

			rend.font_uvs[idx+0] = uv_a
			rend.font_uvs[idx+1] = uv_b
			rend.font_uvs[idx+2] = uv_c
			rend.font_uvs[idx+3] = uv_a
			rend.font_uvs[idx+4] = uv_c
			rend.font_uvs[idx+5] = uv_d
		}
	}
}


@private _set_cell_fg :: proc(c: ^Console, rend: ^Batch_Rendering, idx: int, glyph: Index, color: Color) {
	rend.colors[idx] = color

	b_idx := idx*6
	g_idx := glyph*6

	rend.uvs[b_idx + 0] = rend.font_uvs[g_idx + 0]
	rend.uvs[b_idx + 1] = rend.font_uvs[g_idx + 1]
	rend.uvs[b_idx + 2] = rend.font_uvs[g_idx + 2]
	rend.uvs[b_idx + 3] = rend.font_uvs[g_idx + 3]
	rend.uvs[b_idx + 4] = rend.font_uvs[g_idx + 4]
	rend.uvs[b_idx + 5] = rend.font_uvs[g_idx + 5]
}

@private _update_batch_rendering :: proc(c: ^Console, rend: ^Batch_Rendering) {
	cw, ch := get_cell_size(c)
	updated_bgs := 0
	updated_fgs := 0

	for j in 0 ..< c.h {
		for i in 0 ..< c.w {
			idx := i+j*c.w
			ng, nfg, nbg := c._new_cells.glyphs[idx], c._new_cells.fgs[idx], c._new_cells.bgs[idx]
			og, ofg, obg := c._cells.glyphs[idx], c._cells.fgs[idx], c._cells.bgs[idx]

			if nbg != obg {
				c._cells.bgs[idx] = nbg
				_set_pixel(c._bg_pixels, idx, nbg)
				updated_bgs += 1
			}

			if nfg != ofg || ng != og {
				c._cells.fgs[idx] = nfg
				c._cells.glyphs[idx] = ng
				_set_cell_fg(c, rend, idx, ng, nfg)
				updated_fgs += 1
			}
		}
	}

	if updated_bgs > 0 {
		rect := k2.get_texture_rect(c._bg_tex)
		k2.update_texture(c._bg_tex, c._bg_pixels, rect)
	}
}


@private _render_batch_rendering :: proc(c: ^Console, rend: ^Batch_Rendering) {
	verts  := rend.verts
	uvs    := rend.uvs
	colors := rend.colors

	state := internal.k2_state

	src := k2.get_texture_rect(c._bg_tex)
	dst := k2.get_texture_rect(c._main_rtex.texture)
	k2.draw_texture_fit(c._bg_tex, src, dst)

	num_cells := c.w*c.h

	if state.vertex_buffer_cpu_used + state.batch_shader.vertex_size * num_cells*6 > len(state.vertex_buffer_cpu) {
	    k2.draw_current_batch()
	}

	if state.batch_texture != c._font.texture.handle {
	    k2.draw_current_batch()
	}

	state.batch_texture = c._font.texture.handle

	for i in 0 ..< num_cells {
		// TODO: figure out a fast way to do this (the one below this one is very slow)
		// if i % 2000 == 0 do k2.draw_current_batch()
		// if state.vertex_buffer_cpu_used + state.batch_shader.vertex_size * (num_cells-i)*6 > len(state.vertex_buffer_cpu) {
		//     k2.draw_current_batch()
		// }
		v_idx := i*6
		k2.batch_vertex(verts[v_idx+0], uvs[v_idx+0], colors[i])
		k2.batch_vertex(verts[v_idx+1], uvs[v_idx+1], colors[i])
		k2.batch_vertex(verts[v_idx+2], uvs[v_idx+2], colors[i])
		k2.batch_vertex(verts[v_idx+3], uvs[v_idx+3], colors[i])
		k2.batch_vertex(verts[v_idx+4], uvs[v_idx+4], colors[i])
		k2.batch_vertex(verts[v_idx+5], uvs[v_idx+5], colors[i])
	}
}



/*******************************************************************************

		Render_Texture Rendering (very slow)

*******************************************************************************/

@private _destroy_rtex_rendering :: proc(c: ^Console, rend: ^Texture_Rendering) {
	k2.destroy_render_texture(rend.rtex)
}


@private _init_rtex_rendering :: proc(c: ^Console, rend: ^Texture_Rendering, is_reset: bool) {
	free_all(c._rend_allocator)
	cw, ch := get_cell_size(c)

	// this texture should be the size of the console
	// multiplied by the cell size
	rend.rtex   = k2.create_render_texture(c.w*cw, c.h*ch)
}


@private _update_rtex_rendering :: proc(c: ^Console, rend: ^Texture_Rendering) {
	cw, ch := get_cell_size(c)
	updated_bgs := 0
	updated_fgs := 0

	for j in 0 ..< c.h {
		for i in 0 ..< c.w {
			idx := i+j*c.w
			ng, nfg, nbg := c._new_cells.glyphs[idx], c._new_cells.fgs[idx], c._new_cells.bgs[idx]
			og, ofg, obg := c._cells.glyphs[idx], c._cells.fgs[idx], c._cells.bgs[idx]

			dr := Rectf { f32(i*cw), f32(j*ch), f32(cw), f32(ch) }

			if nbg != obg {
				c._cells.bgs[idx] = nbg
				_set_pixel(c._bg_pixels, idx, nbg)
				updated_bgs += 1
			}

			if nfg != ofg || ng != og {
				c._cells.fgs[idx] = nfg
				c._cells.glyphs[idx] = ng
				updated_fgs += 1
			}
		}
	}

	if updated_bgs > 0 {
		rect := k2.get_texture_rect(c._bg_tex)
		k2.update_texture(c._bg_tex, c._bg_pixels, rect)
	}

	cols := c._font.cols
	rows := c._font.rows

	if updated_fgs > 0 {
		k2.set_render_texture(rend.rtex)
		{
			k2.clear({})
			for j in 0 ..< c.h {
				for i in 0 ..< c.w {
					idx := i+j*c.w
					ng, nfg := int(c._new_cells.glyphs[idx]), c._new_cells.fgs[idx]

					tx := (ng % cols) * cw
					ty := int(ng / cols) * ch

					sr := Rectf { f32(tx), f32(ty), f32(cw), f32(ch) }
					p  := Vec2f { f32(i*cw), f32(j*ch) }

					k2.draw_texture_rect(c._font.texture, sr, p, {}, 0, nfg)
				}
			}
		}
		k2.set_render_texture(nil)
	}
}

@private _render_rtex_rendering :: proc(c: ^Console, rend: ^Texture_Rendering) {
	cw, ch := get_cell_size(c)

	dst := k2.get_texture_rect(c._main_rtex.texture)
	src := k2.get_texture_rect(c._bg_tex)

	k2.draw_texture_fit( c._bg_tex, src, dst )
	k2.draw_texture(rend.rtex.texture, {})
}


