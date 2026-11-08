module serde_json

fn test_json_equality_preserves_cloned_content_and_object_order_independence() {
	mut input := '{"items":[1,{"enabled":true}],"name":"owned settings"}'
	$if ownership ? {
		input = input.to_owned()
	}
	owner := from_str(&input) or { panic(err) }
	first := owner.clone()
	second := owner.clone()
	assert first.equals(&second)
	assert owner.equals(&first)
	reordered_text := '{"name":"owned settings","items":[1,{"enabled":true}]}'
	reordered := from_str(&reordered_text) or { panic(err) }
	assert owner.equals(&reordered)
	changed_text := '{"name":"owned settings","items":[1,{"enabled":false}]}'
	changed := from_str(&changed_text) or { panic(err) }
	assert !owner.equals(&changed)
	assert owner.to_string() == input
	assert input.contains('owned settings')
}

fn test_json_number_equality_keeps_integer_float_distinction_and_signed_zero() {
	negative_zero_text := '-0.0'
	positive_zero_text := '0.0'
	integer_zero_text := '0'
	negative_zero := from_str(&negative_zero_text) or { panic(err) }
	positive_zero := from_str(&positive_zero_text) or { panic(err) }
	integer_zero := from_str(&integer_zero_text) or { panic(err) }
	assert negative_zero.equals(&positive_zero)
	assert !integer_zero.equals(&positive_zero)
	assert !positive_zero.equals(&integer_zero)
	normalized_text := '1.25e2'
	decimal_text := '125.0'
	normalized := from_str(&normalized_text) or { panic(err) }
	decimal := from_str(&decimal_text) or { panic(err) }
	assert normalized.equals(&decimal)
}
