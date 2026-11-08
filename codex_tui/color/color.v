module color

import math

// Named stand-in for the Rust `(u8, u8, u8)` RGB tuples passed between the color, terminal
// palette, and style helpers. V has no anonymous tuple type, so the components are named.
pub struct Rgb {
pub:
	r u8
	g u8
	b u8
}

pub fn is_light(bg Rgb) bool {
	r, g, b := bg.r, bg.g, bg.b
	y := f32(0.299) * f32(r) + f32(0.587) * f32(g) + f32(0.114) * f32(b)
	return y > 128.0
}

pub fn blend(fg Rgb, bg Rgb, alpha f32) Rgb {
	r := f32_as_u8(f32(fg.r) * alpha + f32(bg.r) * (1.0 - alpha))
	g := f32_as_u8(f32(fg.g) * alpha + f32(bg.g) * (1.0 - alpha))
	b := f32_as_u8(f32(fg.b) * alpha + f32(bg.b) * (1.0 - alpha))
	return Rgb{r, g, b}
}

// Returns the perceptual color distance between two RGB colors.
// Uses the CIE76 formula (Euclidean distance in Lab space approximation).
pub fn perceptual_distance(a Rgb, b Rgb) f32 {
	x1, y1, z1 := rgb_to_xyz(a.r, a.g, a.b)
	x2, y2, z2 := rgb_to_xyz(b.r, b.g, b.b)

	l1, a1, b1 := xyz_to_lab(x1, y1, z1)
	l2, a2, b2 := xyz_to_lab(x2, y2, z2)

	dl := l1 - l2
	da := a1 - a2
	db := b1 - b2

	return math.sqrtf(dl * dl + da * da + db * db)
}

// Rust nests these conversion helpers inside `perceptual_distance`; V has no nested named
// functions, so they are private module functions with the same bodies.

// Convert sRGB to linear RGB
fn srgb_to_linear(c u8) f32 {
	value := f32(c) / 255.0
	if value <= 0.04045 {
		return value / 12.92
	}
	return math.powf((value + 0.055) / 1.055, 2.4)
}

// Convert RGB to XYZ
fn rgb_to_xyz(r u8, g u8, b u8) (f32, f32, f32) {
	linear_r := srgb_to_linear(r)
	linear_g := srgb_to_linear(g)
	linear_b := srgb_to_linear(b)

	x := linear_r * 0.4124 + linear_g * 0.3576 + linear_b * 0.1805
	y := linear_r * 0.2126 + linear_g * 0.7152 + linear_b * 0.0722
	z := linear_r * 0.0193 + linear_g * 0.1192 + linear_b * 0.9505
	return x, y, z
}

// Convert XYZ to Lab
fn xyz_to_lab(x f32, y f32, z f32) (f32, f32, f32) {
	// D65 reference white
	xr := x / 0.95047
	yr := y / 1.00000
	zr := z / 1.08883

	fx := lab_f(xr)
	fy := lab_f(yr)
	fz := lab_f(zr)

	l := 116.0 * fy - 16.0
	a := 500.0 * (fx - fy)
	b := 200.0 * (fy - fz)
	return l, a, b
}

// Rust's `f` helper nested inside `xyz_to_lab`.
fn lab_f(t f32) f32 {
	if t > 0.008856 {
		return math.powf(t, f32(1.0) / f32(3.0))
	}
	return f32(7.787) * t + f32(16.0) / f32(116.0)
}

// Rust's float-to-integer `as u8` cast truncates toward zero and saturates at the target bounds
// (NaN becomes 0). A raw V/C conversion is undefined outside that range, so the cast is explicit.
fn f32_as_u8(value f32) u8 {
	if math.is_nan(f64(value)) || value <= 0.0 {
		return 0
	}
	if value >= 255.0 {
		return 255
	}
	return u8(value)
}
