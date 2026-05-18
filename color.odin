/*
    A default assortment of colors

    Most colors are borrowed from the default palette used in REXPaint.
    I made up the names as I did it, off the top of my head,
    so they're probably not correct. I'll be entirely revising this
    at some point.

    The 'D' and 'L' prefixes stand for darker and lighter versions
*/

package ork

import "base:intrinsics"
import "core:math"
import k2 "libs/karl2d"


Color :: k2.Color



color_darkened :: proc(c: Color, percent: $T) -> Color
                  where intrinsics.type_is_float(T) {
    return {
        u8(T(c.r) * (1-percent)),
        u8(T(c.g) * (1-percent)),
        u8(T(c.b) * (1-percent)),
        c.a,
    }
}


color_lerped :: proc(a, b: Color, t: f32) -> Color {
    return {
        u8(math.round( clamp(f32(a.r) * (1-t) + f32(b.r)*t, 0, 255) )),
        u8(math.round( clamp(f32(a.g) * (1-t) + f32(b.g)*t, 0, 255) )),
        u8(math.round( clamp(f32(a.b) * (1-t) + f32(b.b)*t, 0, 255) )),
        u8(math.round( clamp(f32(a.a) * (1-t) + f32(b.a)*t, 0, 255) )),
    }
}


/*******************************************************************************

		Constants

*******************************************************************************/
TRANSP  :: Color{  0,   0,   0,   0}
WHITE   :: Color{255, 255, 255, 255}
BLACK   :: Color{  0,   0,   0, 255}


LIGHT_BLUE   :: Color { 200, 230, 255, 255 }
LIGHT_GREEN  :: Color { 175, 246, 184, 255 }
LIGHT_RED    :: Color { 248, 183, 183, 255 }
LIGHT_BROWN  :: Color { 146, 119, 119, 255 }
LIGHT_PURPLE :: Color { 217, 172, 248, 255 }
LIGHT_YELLOW :: Color { 253, 250, 222, 255 }

DARK_GREEN   :: Color { 6, 53, 34, 255}
DARK_RED     :: Color { 127, 10, 10, 255 }
DARK_BROWN   :: Color { 50, 36, 32, 255 }


// dark grey
DGREY1        :: Color{   2,   2,   2, 255}
DGREY2        :: Color{  27,  27,  27, 255}
DGREY3        :: Color{  53,  53,  53, 255}
DGREY4        :: Color{  78,  78,  78, 255}
DGREY5        :: Color{ 104, 104, 104, 255}
DGREY6        :: Color{ 134, 134, 134, 255}
DGREY7        :: Color{ 167, 167, 167, 255}
DGREY8        :: Color{ 198, 198, 198, 255}

// grey
GREY1         :: Color{ 26,  26,  26, 255}
GREY2         :: Color{ 51,  51,  51, 255}
GREY3         :: Color{ 77,  77,  77, 255}
GREY4         :: Color{102, 102, 102, 255}
GREY5         :: Color{128, 128, 128, 255}
GREY6         :: Color{158, 158, 158, 255}
GREY7         :: Color{191, 191, 191, 255}
GREY8         :: Color{222, 222, 222, 255}

// light grey
LGREY1        :: Color{ 46,  46,  46, 255}
LGREY2        :: Color{ 71,  71,  71, 255}
LGREY3        :: Color{ 97,  97,  97, 255}
LGREY4        :: Color{122, 122, 122, 255}
LGREY5        :: Color{148, 148, 148, 255}
LGREY6        :: Color{178, 178, 178, 255}
LGREY7        :: Color{211, 211, 211, 255}
LGREY8        :: Color{242, 242, 242, 255}

// red
RED1          :: Color{ 64,   0,   0, 255}
RED2          :: Color{102,   0,   0, 255}
RED3          :: Color{140,   0,   0, 255}
RED4          :: Color{178,   0,   0, 255}
RED5          :: Color{217,   0,   0, 255}
RED6          :: Color{255,   0,   0, 255}
RED7          :: Color{255,  51,  51, 255}
RED8          :: Color{255, 102, 102, 255}

// blue
BLUE1         :: Color{  0,  32,  64, 255}
BLUE2         :: Color{  0,  51, 102, 255}
BLUE3         :: Color{  0,  70, 140, 255}
BLUE4         :: Color{  0,  89, 178, 255}
BLUE5         :: Color{  0, 108, 217, 255}
BLUE6         :: Color{  0, 128, 255, 255}
BLUE7         :: Color{ 51, 153, 255, 255}
BLUE8         :: Color{102, 178, 255, 255}

// dark red
DRED1         :: Color{ 64,  16,   0, 255}
DRED2         :: Color{102,  26,   0, 255}
DRED3         :: Color{140,  35,   0, 255}
DRED4         :: Color{178,  45,   0, 255}
DRED5         :: Color{217,  54,   0, 255}
DRED6         :: Color{255,  64,   0, 255}
DRED7         :: Color{255, 102,  51, 255}
DRED8         :: Color{255, 140, 102, 255}

// dark blue
DBLUE1        :: Color{  0,   0,  64, 255}
DBLUE2        :: Color{  0,   0, 102, 255}
DBLUE3        :: Color{  0,   0, 140, 255}
DBLUE4        :: Color{  0,   0, 178, 255}
DBLUE5        :: Color{  0,   0, 217, 255}
DBLUE6        :: Color{  0,   0, 255, 255}
DBLUE7        :: Color{ 51,  51, 255, 255}
DBLUE8        :: Color{102, 102, 255, 255}

// orange
ORANGE1       :: Color{ 64,  32,   0, 255}
ORANGE2       :: Color{102,  51,   0, 255}
ORANGE3       :: Color{140,  70,   0, 255}
ORANGE4       :: Color{178,  89,   0, 255}
ORANGE5       :: Color{217, 108,   0, 255}
ORANGE6       :: Color{255, 128,   0, 255}
ORANGE7       :: Color{255, 153,  51, 255}
ORANGE8       :: Color{255, 178, 102, 255}

// dark purple
DPURPLE1      :: Color{ 16,   0,  64, 255}
DPURPLE2      :: Color{ 26,   0, 102, 255}
DPURPLE3      :: Color{ 35,   0, 140, 255}
DPURPLE4      :: Color{ 45,   0, 178, 255}
DPURPLE5      :: Color{ 54,   0, 217, 255}
DPURPLE6      :: Color{ 64,   0, 255, 255}
DPURPLE7      :: Color{102,  51, 255, 255}
DPURPLE8      :: Color{140, 102, 255, 255}

// amber?
AMBER1        :: Color{ 64,  48,   0, 255}
AMBER2        :: Color{102,  77,   0, 255}
AMBER3        :: Color{140, 105,   0, 255}
AMBER4        :: Color{178, 134,   0, 255}
AMBER5        :: Color{217, 163,   0, 255}
AMBER6        :: Color{255, 191,   0, 255}
AMBER7        :: Color{255, 204,  51, 255}
AMBER8        :: Color{255, 217, 102, 255}

// purple
PURPLE1       :: Color{ 32,   0,  64, 255}
PURPLE2       :: Color{ 51,   0, 102, 255}
PURPLE3       :: Color{ 70,   0, 140, 255}
PURPLE4       :: Color{ 89,   0, 178, 255}
PURPLE5       :: Color{108,   0, 217, 255}
PURPLE6       :: Color{128,   0, 255, 255}
PURPLE7       :: Color{153,  51, 255, 255}
PURPLE8       :: Color{178, 102, 255, 255}

// yellow
YELLOW1       :: Color{ 64,  64,   0, 255}
YELLOW2       :: Color{102, 102,   0, 255}
YELLOW3       :: Color{140, 140,   0, 255}
YELLOW4       :: Color{178, 178,   0, 255}
YELLOW5       :: Color{217, 217,   0, 255}
YELLOW6       :: Color{255, 255,   0, 255}
YELLOW7       :: Color{255, 255,  51, 255}
YELLOW8       :: Color{255, 255, 102, 255}

// dark pink
DPINK1        :: Color{ 48,   0,  64, 255}
DPINK2        :: Color{ 77,   0, 102, 255}
DPINK3        :: Color{105,   0, 140, 255}
DPINK4        :: Color{134,   0, 178, 255}
DPINK5        :: Color{163,   0, 217, 255}
DPINK6        :: Color{191,   0, 255, 255}
DPINK7        :: Color{204,  51, 255, 255}
DPINK8        :: Color{217, 102, 255, 255}

// lime
LIME1         :: Color{ 48,  64,   0, 255}
LIME2         :: Color{ 77, 102,   0, 255}
LIME3         :: Color{105, 140,   0, 255}
LIME4         :: Color{134, 178,   0, 255}
LIME5         :: Color{163, 217,   0, 255}
LIME6         :: Color{191, 255,   0, 255}
LIME7         :: Color{204, 255,  51, 255}
LIME8         :: Color{217, 255, 102, 255}

// pink
PINK1         :: Color{ 64,   0,  64, 255}
PINK2         :: Color{102,   0, 102, 255}
PINK3         :: Color{140,   0, 140, 255}
PINK4         :: Color{178,   0, 178, 255}
PINK5         :: Color{217,   0, 217, 255}
PINK6         :: Color{255,   0, 255, 255}
PINK7         :: Color{255,  51, 255, 255}
PINK8         :: Color{255, 102, 255, 255}

// light green
LGREEN1       :: Color{ 32,  64,   0, 255}
LGREEN2       :: Color{ 51, 102,   0, 255}
LGREEN3       :: Color{ 70, 140,   0, 255}
LGREEN4       :: Color{ 89, 178,   0, 255}
LGREEN5       :: Color{108, 217,   0, 255}
LGREEN6       :: Color{128, 255,   0, 255}
LGREEN7       :: Color{153, 255,  51, 255}
LGREEN8       :: Color{178, 255, 102, 255}

// light pink
LPINK1        :: Color{ 64,   0,  48, 255}
LPINK2        :: Color{102,   0,  77, 255}
LPINK3        :: Color{140,   0, 105, 255}
LPINK4        :: Color{178,   0, 134, 255}
LPINK5        :: Color{217,   0, 163, 255}
LPINK6        :: Color{255,   0, 191, 255}
LPINK7        :: Color{255,  51, 204, 255}
LPINK8        :: Color{255, 102, 217, 255}

// green
GREEN1        :: Color{  0,  64,   0, 255}
GREEN2        :: Color{  0, 102,   0, 255}
GREEN3        :: Color{  0, 140,   0, 255}
GREEN4        :: Color{  0, 178,   0, 255}
GREEN5        :: Color{  0, 217,   0, 255}
GREEN6        :: Color{  0, 255,   0, 255}
GREEN7        :: Color{ 51, 255,  51, 255}
GREEN8        :: Color{102, 255, 102, 255}

// magenta
MAGENTA1      :: Color{ 64,   0,  32, 255}
MAGENTA2      :: Color{102,   0,  51, 255}
MAGENTA3      :: Color{140,   0,  70, 255}
MAGENTA4      :: Color{178,   0,  89, 255}
MAGENTA5      :: Color{217,   0, 108, 255}
MAGENTA6      :: Color{255,   0, 128, 255}
MAGENTA7      :: Color{255,  51, 153, 255}
MAGENTA8      :: Color{255, 102, 178, 255}

// TODO: wtf do I call this color?
BLUEISHGREEN1 :: Color{  0,   64,   32, 255}
BLUEISHGREEN2 :: Color{  0,  102,   51, 255}
BLUEISHGREEN3 :: Color{  0,  140,   70, 255}
BLUEISHGREEN4 :: Color{  0,  178,   89, 255}
BLUEISHGREEN5 :: Color{  0,  217,  108, 255}
BLUEISHGREEN6 :: Color{  0,  255,  128, 255}
BLUEISHGREEN7 :: Color{ 51,  255,  153, 255}
BLUEISHGREEN8 :: Color{102,  255,  178, 255}

// dark magenta
DMAGENTA1     :: Color{ 64,   0,  16, 255}
DMAGENTA2     :: Color{102,   0,  26, 255}
DMAGENTA3     :: Color{140,   0,  35, 255}
DMAGENTA4     :: Color{178,   0,  45, 255}
DMAGENTA5     :: Color{217,   0,  54, 255}
DMAGENTA6     :: Color{255,   0,  64, 255}
DMAGENTA7     :: Color{255,  51, 102, 255}
DMAGENTA8     :: Color{255, 102, 140, 255}

// light cian
LCIAN1        :: Color{  0,  64,  48, 255}
LCIAN2        :: Color{  0, 102,  77, 255}
LCIAN3        :: Color{  0, 140, 105, 255}
LCIAN4        :: Color{  0, 178, 134, 255}
LCIAN5        :: Color{  0, 217, 163, 255}
LCIAN6        :: Color{  0, 255, 191, 255}
LCIAN7        :: Color{ 51, 255, 204, 255}
LCIAN8        :: Color{102, 255, 217, 255}

// cian (I think)
CIAN1         :: Color{  0,  64,  64, 255}
CIAN2         :: Color{  0, 102, 102, 255}
CIAN3         :: Color{  0, 140, 140, 255}
CIAN4         :: Color{  0, 178, 178, 255}
CIAN5         :: Color{  0, 217, 217, 255}
CIAN6         :: Color{  0, 255, 255, 255}
CIAN7         :: Color{ 51, 255, 255, 255}
CIAN8         :: Color{102, 255, 255, 255}

// brown
BROWN1        :: Color{ 26,  20,  13, 255}
BROWN2        :: Color{ 51,  41,  26, 255}
BROWN3        :: Color{ 77,  61,  38, 255}
BROWN4        :: Color{102,  82,  51, 255}
BROWN5        :: Color{128, 102,  64, 255}
BROWN6        :: Color{158, 134, 100, 255}
BROWN7        :: Color{191, 171, 143, 255}
BROWN8        :: Color{222, 211, 195, 255}

// dark cian
DCIAN1        :: Color{  0,  48,  64, 255}
DCIAN2        :: Color{  0,  77, 102, 255}
DCIAN3        :: Color{  0, 105, 140, 255}
DCIAN4        :: Color{  0, 134, 178, 255}
DCIAN5        :: Color{  0, 163, 217, 255}
DCIAN6        :: Color{  0, 191, 255, 255}
DCIAN7        :: Color{ 51, 204, 255, 255}
DCIAN8        :: Color{102, 217, 255, 255}


/*******************************************************************************

		"grey" -> "gray" aliases

*******************************************************************************/
DGRAY1 :: DGREY1
DGRAY2 :: DGREY2
DGRAY3 :: DGREY3
DGRAY4 :: DGREY4
DGRAY5 :: DGREY5
DGRAY6 :: DGREY6
DGRAY7 :: DGREY7
DGRAY8 :: DGREY8

GRAY1 :: GREY1
GRAY2 :: GREY2
GRAY3 :: GREY3
GRAY4 :: GREY4
GRAY5 :: GREY5
GRAY6 :: GREY6
GRAY7 :: GREY7
GRAY8 :: GREY8

LGRAY1 :: LGREY1
LGRAY2 :: LGREY2
LGRAY3 :: LGREY3
LGRAY4 :: LGREY4
LGRAY5 :: LGREY5
LGRAY6 :: LGREY6
LGRAY7 :: LGREY7
LGRAY8 :: LGREY8





