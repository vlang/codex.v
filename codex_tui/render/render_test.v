module render

import ratatui.layout

fn test_asymmetric_insets_preserve_tlbr_argument_order() {
	area := layout.Rect{ x: 10, y: 20, width: 30, height: 40 }
	assert inset(&area, Insets.tlbr(2, 3, 5, 7)) == layout.Rect{
		x:      13
		y:      22
		width:  20
		height: 33
	}
}

fn test_symmetric_insets_apply_vertical_and_horizontal_to_both_sides() {
	area := layout.Rect{ x: 10, y: 20, width: 30, height: 40 }
	assert inset(&area, Insets.vh(3, 4)) == layout.Rect{
		x:      14
		y:      23
		width:  22
		height: 34
	}
}

fn test_insets_larger_than_dimensions_produce_empty_rectangle_at_shifted_origin() {
	area := layout.Rect{ x: 10, y: 20, width: 3, height: 4 }
	assert inset(&area, Insets.tlbr(6, 7, 8, 9)) == layout.Rect{
		x: 17
		y: 26
	}
}

fn test_inset_coordinates_saturate_at_u16_maximum() {
	area := layout.Rect{ x: 65534, y: 65530, width: 100, height: 100 }
	assert inset(&area, Insets.tlbr(8, 2, 2, 1)) == layout.Rect{
		x:      65535
		y:      65535
		width:  97
		height: 90
	}
}

fn test_total_insets_saturate_before_subtracting_from_dimensions() {
	area := layout.Rect{ width: 65535, height: 65535 }
	assert inset(&area, Insets.vh(32768, 32768)) == layout.Rect{
		x: 32768
		y: 32768
	}
	assert inset(&area, Insets.vh(65535, 65535)) == layout.Rect{
		x: 65535
		y: 65535
	}
}

fn test_zero_insets_preserve_raw_rectangle_even_when_far_edges_exceed_u16() {
	area := layout.Rect{ x: 65535, y: 65535, width: 65535, height: 65535 }
	assert inset(&area, Insets.vh(0, 0)) == area
}

fn test_empty_rectangle_still_shifts_and_saturates_origin() {
	area := layout.Rect{ x: 65534, y: 65530 }
	assert inset(&area, Insets.tlbr(8, 2, 1, 1)) == layout.Rect{
		x: 65535
		y: 65535
	}
}

fn test_borrowed_rectangle_and_copy_insets_remain_reusable() {
	area := layout.Rect{ x: 10, y: 20, width: 30, height: 40 }
	insets := Insets.tlbr(2, 3, 5, 7)
	for _ in 0 .. 4 {
		assert inset(&area, insets) == layout.Rect{
			x:      13
			y:      22
			width:  20
			height: 33
		}
	}
	assert area == layout.Rect{ x: 10, y: 20, width: 30, height: 40 }
	assert insets == Insets.tlbr(2, 3, 5, 7)
	assert insets.clone() == insets
}
