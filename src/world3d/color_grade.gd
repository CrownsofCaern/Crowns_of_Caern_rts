class_name ColorGrade
extends RefCounted
## The final colour grade of the 3D view, as a small 3D lookup texture for
## Environment.adjustment_color_correction (works on the Compatibility renderer and
## costs one texture read per pixel). It ties units, buildings and ground into one
## picture the way the main game's battlefield paintings are lit: warm, golden light
## against cool slate shadows, a gentle S-curve, and blacks lifted just off pure black.
## Purely visual; the numbers below are the whole look.

const SIZE := 17  ## samples per axis; the GPU interpolates between them
const CONTRAST := 0.22  ## 0 = none, 1 = full smoothstep S-curve
const SHADOW_TINT := Vector3(-0.012, 0.004, 0.034)  ## added in the darks: cool slate
const HIGHLIGHT_TINT := Vector3(0.034, 0.014, -0.026)  ## added in the lights: warm gold
const LIFT := Vector3(0.018, 0.02, 0.026)  ## floor of the blacks (slightly cool)

static var _cached: ImageTexture3D


## The shared lookup texture (built once).
static func texture() -> ImageTexture3D:
	if _cached == null:
		_cached = build(SIZE)
	return _cached


static func build(n: int) -> ImageTexture3D:
	var layers: Array[Image] = []
	for b in n:
		var img := Image.create(n, n, false, Image.FORMAT_RGB8)
		for g in n:
			for r in n:
				var c := grade(Color(float(r) / (n - 1), float(g) / (n - 1), float(b) / (n - 1)))
				img.set_pixel(r, g, c)
		layers.append(img)
	var tex := ImageTexture3D.new()
	tex.create(Image.FORMAT_RGB8, n, n, n, false, layers)
	return tex


## The grade of one display colour (0..1 per channel).
static func grade(c: Color) -> Color:
	var v := Vector3(c.r, c.g, c.b)
	var s := v * v * (Vector3.ONE * 3.0 - v * 2.0)
	v = v.lerp(s, CONTRAST)
	var lum := v.dot(Vector3(0.2126, 0.7152, 0.0722))
	var dark := (1.0 - lum) * (1.0 - lum)
	v += SHADOW_TINT * dark + HIGHLIGHT_TINT * lum * lum
	v = LIFT + v * (Vector3.ONE - LIFT)
	return Color(clampf(v.x, 0.0, 1.0), clampf(v.y, 0.0, 1.0), clampf(v.z, 0.0, 1.0))
