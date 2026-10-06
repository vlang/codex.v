module backend_banners

import codex_protocol.account
import serde_json

fn test_parse_rejects_more_actions_than_the_inline_banner_can_display() {
	mut labels := []string{}
	for index in 1 .. 9 { labels << 'Action ${index}' }
	mut ctas := []serde_json.Value{}
	for index in 0 .. labels.len {
		ctas << serde_json.Value.object({
			'action': serde_json.Value.string('view_usage')
			'label':  serde_json.Value.string(labels[index].clone())
		})
	}
	mut raw := serde_json.Value.object({
		'banner_type': serde_json.Value.string('usage_limit')
		'title':       serde_json.Value.string('Usage limit reached')
		'description': serde_json.Value.string('Choose how to continue.')
		'ctas':        serde_json.Value.array_value(ctas)
	})
	banner := BackendBanner.parse(&raw) or { panic('eight actions fit') }
	rendered := banner.actionable_banner()
	mut actual := []string{}
	for action in rendered.actions { actual << action.name }
	assert actual == labels

	{
		mut cta_value := raw.index_mut(&ctas_key)
		mut array := cta_value.as_array_mut()
		assert array.has_value
		array.push(serde_json.Value.object({
			'action': serde_json.Value.string('view_usage')
			'label':  serde_json.Value.string('Hidden ninth action')
		}))
	}
	assert BackendBanner.parse(&raw) == none
}

fn test_parse_rejects_unsupported_or_unrenderable_content() {
	valid := valid_banner_json()
	mut seventeen_models := []serde_json.Value{}
	for _ in 0 .. 17 { seventeen_models << serde_json.Value.string('model') }
	for invalid_fields in [
		serde_json.Value.object({
			'presentation': serde_json.Value.string('future_mode')
		}),
		serde_json.Value.object({
			'presentation': serde_json.Value{}
		}),
		serde_json.Value.object({
			'title': serde_json.Value.string(' ')
		}),
		serde_json.Value.object({
			'title': serde_json.Value.string('x'.repeat(1025))
		}),
		serde_json.Value.object({
			'title': serde_json.Value.string('line\n'.repeat(4))
		}),
		serde_json.Value.object({
			'description': serde_json.Value.string('x'.repeat(4097))
		}),
		serde_json.Value.object({
			'description': serde_json.Value.string('line\n'.repeat(13))
		}),
		serde_json.Value.object({
			'blocked_model_slug': serde_json.Value.string('')
		}),
		serde_json.Value.object({
			'blocked_model_slug': serde_json.Value.string('bad\nslug')
		}),
		serde_json.Value.object({
			'fallback_model_slugs': serde_json.Value.array_value([
				serde_json.Value.string('x'.repeat(257)),
			])
		}),
		serde_json.Value.object({
			'fallback_model_slugs': serde_json.Value.array_value(seventeen_models)
		}),
	] {
		mut raw := valid.clone()
		{
			mut object := raw.as_object_mut()
			assert object.has_value
			fields := invalid_fields.as_object()
			assert fields.has_value
			object.extend(fields.clone())
		}
		assert BackendBanner.parse(&raw) == none, '${invalid_fields}'
	}
}

fn test_deserialize_defaults_nulls_unknown_and_skipped_fields() ! {
	raw := valid_banner_json()
	banner := BackendBanner.parse(&raw) or { panic('default fields are supported') }
	assert banner.banner_type == 'usage_limit'
	assert banner.title == 'Usage limit reached'
	assert banner.description == 'Choose how to continue.'
	assert banner.ctas.len == 0
	assert banner.reset_at == none
	assert banner.model_slug == none
	assert banner.blocked_model_slug == none
	assert banner.request_url == none
	assert banner.fallback_model_slugs.len == 0
	assert banner.presentation == .inline
	assert banner.account_id == ''
	assert banner.plan_type == none
	assert luna_reserve_banner == 'luna_reserve'
	assert luna_reserve_recovery_view_id == 'luna-reserve-recovery'

	extra := serde_json.Value.object({
		'reset_at':           serde_json.Value{}
		'model_slug':         serde_json.Value{}
		'blocked_model_slug': serde_json.Value{}
		'request_url':        serde_json.Value{}
		'account_id':         serde_json.Value.array_value([serde_json.Value.boolean(true)])
		'plan_type':          serde_json.Value.boolean(false)
		'unknown':            serde_json.Value.object({
			'nested': serde_json.Value.string('ignored')
		})
	})
	with_extra := banner_with_fields(&extra)
	parsed := BackendBanner.parse(&with_extra) or { panic('optional nulls and skipped metadata are supported') }
	assert banner.equals(&parsed)
}

fn test_deserialize_rejects_missing_fields_and_wrong_types() ! {
	for text in [
		'null',
		'true',
		'"banner"',
		'{}',
		'{"title":"title","description":"description","ctas":[]}',
		'{"banner_type":"type","description":"description","ctas":[]}',
		'{"banner_type":"type","title":"title","ctas":[]}',
		'{"banner_type":"type","title":"title","description":"description"}',
	] {
		raw := serde_json.from_str(&text)!
		assert BackendBanner.parse(&raw) == none, text
	}
	for fields_text in [
		'{"banner_type":null}',
		'{"banner_type":1}',
		'{"title":null}',
		'{"description":false}',
		'{"ctas":null}',
		'{"ctas":{}}',
		'{"ctas":[{}]}',
		'{"ctas":[{"action":"view_usage"}]}',
		'{"ctas":[{"label":"label"}]}',
		'{"ctas":[{"action":false,"label":"label"}]}',
		'{"ctas":[{"action":"view_usage","label":null}]}',
		'{"model_slug":[]}',
		'{"blocked_model_slug":1}',
		'{"request_url":{}}',
		'{"fallback_model_slugs":null}',
		'{"fallback_model_slugs":{}}',
		'{"fallback_model_slugs":[null]}',
		'{"fallback_model_slugs":[false]}',
		'{"presentation":1}',
		'{"presentation":[]}',
		'{"presentation":"Inline"}',
	] {
		fields := serde_json.from_str(&fields_text)!
		raw := banner_with_fields(&fields)
		assert BackendBanner.parse(&raw) == none, fields_text
	}
}

fn test_presentation_unit_variants_and_struct_sequences() ! {
	for text in ['"inline"', '{"inline":null}', '"dismissible"', '{"dismissible":null}'] {
		value := serde_json.from_str(&text)!
		fields := serde_json.Value.object({
			'presentation': value
		})
		raw := banner_with_fields(&fields)
		banner := BackendBanner.parse(&raw) or { panic(text.clone()) }
		assert banner.presentation == if text.contains('dismissible') {
			BannerPresentation.dismissible
		} else {
			BannerPresentation.inline
		}
	}
	for text in ['{}', '{"inline":[]}', '{"inline":{}}', '{"inline":false}',
		'{"inline":null,"dismissible":null}', '{"future_mode":null}'] {
		value := serde_json.from_str(&text)!
		fields := serde_json.Value.object({
			'presentation': value
		})
		raw := banner_with_fields(&fields)
		assert BackendBanner.parse(&raw) == none, text
	}
	sequence_text := '["usage_limit","Title","Description",[["view_usage","Label"]],null,null,null,[],"dismissible",null]'
	sequence := serde_json.from_str(&sequence_text)!
	banner := BackendBanner.parse(&sequence) or { panic('serde structs accept sequences') }
	assert banner.title == 'Title'
	assert banner.presentation == .dismissible
	assert banner.ctas.len == 1
	assert banner.ctas[0].action == 'view_usage'
	assert banner.ctas[0].label == 'Label'
	assert banner.account_id == ''
	assert banner.plan_type == none
	for text in [
		'["usage_limit","Title","Description",[],null,null,null,[],"inline"]',
		'["usage_limit","Title","Description",[],null,null,null,[],"inline",null,"extra"]',
		'["usage_limit","Title","Description",[["view_usage"]],null,null,null,[],"inline",null]',
		'["usage_limit","Title","Description",[["view_usage","Label","extra"]],null,null,null,[],"inline",null]',
	] {
		raw := serde_json.from_str(&text)!
		assert BackendBanner.parse(&raw) == none, text
	}
	for text in ['[false]', '[false,"Title","Description",[],null,null,null,[],"inline",null,"extra"]',
		'{"model_slug":false}', '{"model_slug":false,"presentation":null}'] {
		raw := serde_json.from_str(&text)!
		if _ := BackendBanner.deserialize_value(&raw) {
			assert false, text
		} else {
			assert err.msg() == 'expected a string', text
		}
	}
	ordered_text := '{"presentation":null,"model_slug":false}'
	ordered := serde_json.from_str(&ordered_text)!
	if _ := BackendBanner.deserialize_value(&ordered) {
		assert false
	} else {
		assert err.msg() == 'expected BannerPresentation unit variant'
	}
	for text in ['[false]', '[false,"Label","extra"]', '{"label":false}'] {
		raw := serde_json.from_str(&text)!
		if _ := BackendBannerCta.deserialize_value(&raw) {
			assert false, text
		} else {
			assert err.msg() == 'expected a string', text
		}
	}
	short_text := '["usage_limit","Title","Description",[],null,null,null]'
	short := serde_json.from_str(&short_text)!
	if _ := BackendBanner.deserialize_value(&short) {
		assert false
	} else {
		assert err.msg() == 'invalid length 9, expected struct BackendBanner with 10 elements'
	}
}

fn test_timestamp_integer_range_and_type() ! {
	for timestamp in ['-9223372036854775808', '-1', '0', '1', '9223372036854775807'] {
		text := '{"reset_at":${timestamp}}'
		fields := serde_json.from_str(&text)!
		raw := banner_with_fields(&fields)
		banner := BackendBanner.parse(&raw) or { panic(timestamp.clone()) }
		value := match timestamp {
			'-9223372036854775808' { i64(-9223372036854775807) - 1 }
			'-1' { i64(-1) }
			'0' { i64(0) }
			'1' { i64(1) }
			else { i64(9223372036854775807) }
		}
		if actual := banner.reset_at {
			assert actual == value
		} else {
			assert false
		}
	}
	for timestamp in ['-9223372036854775809', '9223372036854775808', '18446744073709551615', '1.0',
		'1e0', '-0', 'true', '"1"', '[]', '{}'] {
		text := '{"reset_at":${timestamp}}'
		fields := serde_json.from_str(&text)!
		raw := banner_with_fields(&fields)
		assert BackendBanner.parse(&raw) == none, timestamp
	}
}

fn test_byte_limits_and_rust_line_semantics() {
	for title in ['x'.repeat(1024), 'é'.repeat(512), 'line\n'.repeat(3), 'line\r\n'.repeat(3),
		'one\r two\r three\r four', 'one\n\ntwo\n'] {
		fields := serde_json.Value.object({
			'title': serde_json.Value.string(title)
		})
		raw := banner_with_fields(&fields)
		assert BackendBanner.parse(&raw) != none
	}
	for title in ['é'.repeat(513), 'line\r\n'.repeat(4), 'one\n\n\ntwo'] {
		fields := serde_json.Value.object({
			'title': serde_json.Value.string(title)
		})
		raw := banner_with_fields(&fields)
		assert BackendBanner.parse(&raw) == none
	}
	for description in ['', 'x'.repeat(4096), 'é'.repeat(2048), 'line\n'.repeat(12),
		'line\r\n'.repeat(12)] {
		fields := serde_json.Value.object({
			'description': serde_json.Value.string(description)
		})
		raw := banner_with_fields(&fields)
		assert BackendBanner.parse(&raw) != none
	}
	for description in ['é'.repeat(2049), 'line\r\n'.repeat(13)] {
		fields := serde_json.Value.object({
			'description': serde_json.Value.string(description)
		})
		raw := banner_with_fields(&fields)
		assert BackendBanner.parse(&raw) == none
	}
}

fn test_rust_unicode_whitespace_and_control_slug_validation() {
	whitespace := '\t\n\v\f\r \u0085\u00a0\u1680\u2000\u2001\u2002\u2003\u2004\u2005\u2006\u2007\u2008\u2009\u200a\u2028\u2029\u202f\u205f\u3000'
	for character in whitespace.runes() {
		fields := serde_json.Value.object({
			'title': serde_json.Value.string(character.str())
		})
		raw := banner_with_fields(&fields)
		assert BackendBanner.parse(&raw) == none
	}
	for slug in ['', whitespace.clone(), 'bad\nslug', 'bad\u007fslug', 'bad\u009fslug',
		'é'.repeat(129)] {
		for key in [blocked_model_slug_key, fallback_model_slugs_key] {
			value := if key == blocked_model_slug_key {
				serde_json.Value.string(slug.clone())
			} else {
				serde_json.Value.array_value([serde_json.Value.string(slug.clone())])
			}
			fields := serde_json.Value.object({
				key: value
			})
			raw := banner_with_fields(&fields)
			assert BackendBanner.parse(&raw) == none
		}
	}
	for slug in ['é'.repeat(128), ' model ', '\u200b', '\u2060', 'model\u2028name'] {
		fields := serde_json.Value.object({
			'blocked_model_slug':   serde_json.Value.string(slug.clone())
			'fallback_model_slugs': serde_json.Value.array_value([serde_json.Value.string(slug)])
		})
		raw := banner_with_fields(&fields)
		assert BackendBanner.parse(&raw) != none
	}
	for title in ['\u200b', '\u0000', '\u007f', '\u2028title\u2029'] {
		fields := serde_json.Value.object({
			'title': serde_json.Value.string(title)
		})
		raw := banner_with_fields(&fields)
		assert BackendBanner.parse(&raw) != none
	}
}

fn test_validation_is_limited_to_source_fields_and_caps() {
	mut models := []serde_json.Value{}
	for _ in 0 .. 16 { models << serde_json.Value.string('model') }
	fields := serde_json.Value.object({
		'banner_type':          serde_json.Value.string('')
		'model_slug':           serde_json.Value.string('bad\nslug'.repeat(200))
		'request_url':          serde_json.Value.string('not a URL')
		'fallback_model_slugs': serde_json.Value.array_value(models)
		'ctas':                 serde_json.Value.array_value([
			serde_json.Value.object({
				'action': serde_json.Value.string('unknown')
				'label':  serde_json.Value.string('')
			}),
			serde_json.Value.object({
				'action': serde_json.Value.string('')
				'label':  serde_json.Value.string('bad\nlabel'.repeat(200))
			}),
		])
	})
	raw := banner_with_fields(&fields)
	banner := BackendBanner.parse(&raw) or { panic('only source-specified fields are validated') }
	assert banner.fallback_model_slugs.len == 16
	assert banner.ctas.len == 2
	assert banner.ctas[0].action == 'unknown'
	assert banner.ctas[0].label == ''
}

fn test_render_stub_preserves_duplicate_label_order_and_filters_labels() {
	mut ctas := []serde_json.Value{}
	for label in ['Second', 'First', 'Second', ' ', 'bad\nlabel', 'é'.repeat(129)] {
		ctas << serde_json.Value.object({
			'action': serde_json.Value.string('view_usage')
			'label':  serde_json.Value.string(label)
		})
	}
	fields := serde_json.Value.object({
		'ctas': serde_json.Value.array_value(ctas)
	})
	raw := banner_with_fields(&fields)
	banner := BackendBanner.parse(&raw) or { panic('CTA labels are validated at rendering') }
	rendered := banner.actionable_banner()
	mut labels := []string{}
	for action in rendered.actions { labels << action.name }
	assert labels == ['Second', 'First', 'Second']
}

fn test_clone_owns_all_fields_and_equality_observes_metadata() ! {
	text := '{"model_slug":"model","blocked_model_slug":"blocked","fallback_model_slugs":["fallback"],"request_url":"https://example.com","ctas":[{"action":"view_usage","label":"Usage"}],"reset_at":12,"presentation":"dismissible"}'
	fields := serde_json.from_str(&text)!
	raw := banner_with_fields(&fields)
	mut banner := BackendBanner.parse(&raw) or { panic('valid banner') }
	banner.account_id = 'account'.clone()
	banner.plan_type = account.PlanType.plus
	mut cloned := banner.clone()
	assert banner.equals(&cloned)
	cloned.ctas[0].label = 'changed'.clone()
	cloned.fallback_model_slugs[0] = 'changed'.clone()
	cloned.account_id = 'changed'.clone()
	cloned.model_slug = 'changed'.clone()
	assert banner.ctas[0].label == 'Usage'
	assert banner.fallback_model_slugs[0] == 'fallback'
	assert banner.account_id == 'account'
	if slug := banner.model_slug {
		assert slug == 'model'
	} else {
		assert false
	}
	assert !banner.equals(&cloned)
	mut metadata := banner.clone()
	metadata.plan_type = account.PlanType.pro
	assert !banner.equals(&metadata)
}

fn test_heap_owned_input_and_borrowed_apis_remain_reusable() ! {
	text := $if ownership ? {
		'{"banner_type":"usage_limit","title":"Heap title","description":"Heap description","ctas":[{"action":"view_usage","label":"Heap label"}],"model_slug":"heap-model","blocked_model_slug":"heap-blocked","fallback_model_slugs":["heap-fallback"],"request_url":"https://example.com"}'.to_owned()
	} $else {
		'{"banner_type":"usage_limit","title":"Heap title","description":"Heap description","ctas":[{"action":"view_usage","label":"Heap label"}],"model_slug":"heap-model","blocked_model_slug":"heap-blocked","fallback_model_slugs":["heap-fallback"],"request_url":"https://example.com"}'.clone()
	}
	raw := serde_json.from_str(&text)!
	first := BackendBanner.parse(&raw) or { panic('first borrowed parse') }
	second := BackendBanner.parse(&raw) or { panic('second borrowed parse') }
	assert first.equals(&second)
	cloned := first.clone()
	assert first.equals(&cloned)
	rendered_first := first.actionable_banner()
	rendered_second := first.actionable_banner()
	assert rendered_first.actions[0].name == 'Heap label'
	assert rendered_second.actions[0].name == 'Heap label'
	assert first.ctas[0].label == 'Heap label'
	assert first.title == 'Heap title'
	assert first.fallback_model_slugs[0] == 'heap-fallback'
	if slug := first.model_slug {
		assert slug == 'heap-model'
	} else {
		assert false
	}
	assert raw.index(&title_key).string_owned()! == 'Heap title'
	assert text.contains('heap-blocked')
}

fn valid_banner_json() serde_json.Value {
	return serde_json.Value.object({
		'banner_type': serde_json.Value.string('usage_limit')
		'title':       serde_json.Value.string('Usage limit reached')
		'description': serde_json.Value.string('Choose how to continue.')
		'ctas':        serde_json.Value.array_value([]serde_json.Value{})
	})
}

fn banner_with_fields(fields &serde_json.Value) serde_json.Value {
	mut raw := valid_banner_json()
	mut object := raw.as_object_mut()
	assert object.has_value
	incoming := fields.as_object()
	assert incoming.has_value
	object.extend(incoming.clone())
	return raw
}
