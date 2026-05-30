#version 330

// Text-console grid shader

const vec3 BLACK = vec3(0);

in vec2 fragTexCoord;
out vec4 finalColor;


uniform sampler2D font;     // the bitmap font image (e.g. cp437)

uniform vec2 console_size = vec2(80, 50);  // the console size in cells
uniform vec2 font_sizet = vec2(16, 16);    // the font image size in tiles
uniform vec2 cell_size = vec2(20, 20);

// size of textures in px == console size in cells (e.g. 80 x 50)
uniform sampler2D bg_tex;   // background grid colors
uniform sampler2D fg_tex;   // foreground grid colors
uniform sampler2D chr_tex;  // glyph values in red and green channels

uniform bool testing = false;

void main() {
	// get font and console-canvas sizes in pixels
	vec2 ft_img_size = font_sizet * cell_size;
	vec2 canvas_size = console_size * cell_size;

	// get the glyph value (stored in the red and green channels), and scale it to 0-255
	vec4 glyph_col = texture(chr_tex, fragTexCoord);
	float glyph = floor((glyph_col.r + glyph_col.g) * 255);
	// if (testing) { glyph = 0; }
	// get the respective glyph coords on the font, in pixels, normalized
	vec2 guv = vec2(
		(floor(mod(glyph, font_sizet.x))) * cell_size.x,
		(floor(glyph / font_sizet.x)    ) * cell_size.y
	);

	/* get the pixel we're currently at in the current tile, as an offset */
	/* to add to the 'guv' */
	vec2 ofs = mod(fragTexCoord * canvas_size, cell_size);

	// vec2 pixuv = guv+ofs;
	vec2 pixuv = (guv+ofs) / ft_img_size;

	/* Get the pixel color at the tile coords IN THE FONT IMAGE, offset to */
	/* the current pixel in the tile */
	vec4 px_col = texture(font, pixuv);

	if (testing) {
		if (glyph == 121) {
			px_col = vec4(fragTexCoord, 1, 1);
		} else {
			px_col = texture(font, fragTexCoord);
		}
	}

	vec4 bg_col = texture(bg_tex, fragTexCoord);
	vec4 fg_col = texture(fg_tex, fragTexCoord);

	// If 'px_col' is black (excluding alpha), that means this pixel belongs
	// to the space around the glyph, otherwise this pixel is from the glyph
	// itself.
	if (px_col.rgb == BLACK) {
		finalColor = bg_col;
	} else {
		finalColor = vec4(fg_col.rgb * px_col.rgb, fg_col.a);
	}
}

