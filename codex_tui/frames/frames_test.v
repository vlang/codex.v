module frames

import crypto.sha256

// include_str! must preserve every asset byte, including whitespace and whether
// its final line has a terminator. This source-derived local fingerprint manifest
// checks the complete expanded include order without reading the Rust checkout.
fn test_all_embedded_assets_preserve_source_bytes_and_order() {
	expected := $embed_file('assets_sha256.txt').to_string().split_into_lines()
	variant_names := ['default', 'codex', 'openai', 'blocks', 'dots', 'hash', 'hbars', 'vbars',
		'shapes', 'slug']
	mut entry_idx := 0
	for variant_idx, variant in *all_variants {
		for frame_idx in 0 .. (*variant).len {
			fields := expected[entry_idx].fields()
			assert fields[1] == '${variant_names[variant_idx]}/frame_${frame_idx + 1}.txt'
			// sha256's standard-library API consumes a string value under ownership;
			// create its owned input explicitly from the shared static frame.
			assert sha256.hexhash((*variant)[frame_idx].clone()) == fields[0]
			entry_idx++
		}
	}
	assert entry_idx == expected.len
}

// This is the same immutable nested borrow exposed to the animation consumer.
// Reading every byte makes the lifetime check cover strings as well as arrays.
fn frame_byte_fingerprint(variants &[]&[]string) u64 {
	mut fingerprint := u64(0xcbf29ce484222325)
	for variant in *variants {
		for frame_idx in 0 .. (*variant).len {
			frame := &(*variant)[frame_idx]
			for byte_idx in 0 .. frame.len {
				fingerprint = (fingerprint ^ u64((*frame)[byte_idx])) * u64(0x100000001b3)
			}
		}
	}
	return fingerprint
}

fn test_static_frames_remain_readable_after_repeated_borrows() {
	before := frame_byte_fingerprint(all_variants)
	assert frame_byte_fingerprint(all_variants) == before
	assert frame_byte_fingerprint(all_variants) == before
	// Read an asset owner through its separately exported constant afterward.
	assert sha256.hexhash((*frames_slug)[35].clone()) ==
		sha256.hexhash((*(*all_variants)[9])[35].clone())
}

fn test_nested_borrow_does_not_consume_dynamic_frame_owners() {
	mut first := 'first frame\n'
	mut second := 'second frame without newline'
	$if ownership ? {
		first = first.to_owned()
		second = second.to_owned()
	}
	owned_frames := [first, second]
	borrowed_variants := [&owned_frames]
	before := frame_byte_fingerprint(&borrowed_variants)
	assert frame_byte_fingerprint(&borrowed_variants) == before
	assert frame_byte_fingerprint(&borrowed_variants) == before
	assert owned_frames[0] == 'first frame\n'
	assert owned_frames[1] == 'second frame without newline'
}
