module markdown_text_merge

import pulldown_cmark
import std_ops

@[heap]
struct Probe {
mut:
	calls int
}

struct Yield {
	present bool
mut:
	item EventRange
}

struct ScriptIterator {
mut:
	probe  &Probe
	script []Yield
	index  int
}

fn (mut iter ScriptIterator) next() ?EventRange {
	iter.probe.calls++
	if iter.index >= iter.script.len {
		return none
	}
	index := iter.index
	iter.index++
	if !iter.script[index].present {
		return none
	}
	item := iter.script[index].item
	iter.script[index].item = EventRange{}
	return item
}

fn text_event(value string, start usize, end usize) EventRange {
	return EventRange{
		event: pulldown_cmark.Event{ kind: .text, text: pulldown_cmark.CowStr.from_string(value) }
		range: std_ops.Range[usize]{ start: start, end: end }
	}
}

fn nontext_event(event pulldown_cmark.Event, start usize, end usize) EventRange {
	return EventRange{ event: event, range: std_ops.Range[usize]{ start: start, end: end } }
}

fn yielded(item EventRange) Yield {
	return Yield{ present: true, item: item }
}

fn test_constructor_and_boundary_peeking_are_lazy() {
	mut probe := &Probe{}
	mut merge := DecodedTextMerge.new(ScriptIterator{
		probe:  probe
		script: [
			yielded(text_event('left', 2, 6)),
			yielded(text_event('right', 7, 12)),
			yielded(nontext_event(pulldown_cmark.Event{ kind: .soft_break }, 12, 13)),
			yielded(text_event('tail', 13, 17)),
		]
	})
	assert probe.calls == 0
	first := merge.next() or { panic('missing merged text') }
	assert first == text_event('leftright', 2, 12)
	assert probe.calls == 3
	boundary := merge.next() or { panic('missing cached boundary') }
	assert boundary == nontext_event(pulldown_cmark.Event{ kind: .soft_break }, 12, 13)
	assert probe.calls == 3
	tail := merge.next() or { panic('missing tail') }
	assert tail == text_event('tail', 13, 17)
	assert probe.calls == 5
	if _ := merge.next() {
		assert false
	}
	assert probe.calls == 5
	if _ := merge.next() {
		assert false
	}
	assert probe.calls == 6
}

fn test_empty_iterator_calls_next_once_per_request() {
	mut probe := &Probe{}
	mut merge := DecodedTextMerge.new(ScriptIterator{ probe: probe })
	assert probe.calls == 0
	if _ := merge.next() {
		assert false
	}
	assert probe.calls == 1
	if _ := merge.next() {
		assert false
	}
	assert probe.calls == 2
}

fn test_decoded_contents_merge_without_raw_markdown_reconstruction() {
	mut probe := &Probe{}
	mut merge := DecodedTextMerge.new(ScriptIterator{
		probe:  probe
		script: [
			yielded(text_event('file', 0, 4)),
			yielded(text_event('_', 4, 6)),
			yielded(text_event('name & ', 6, 18)),
			yielded(text_event('“decoded”', 18, 35)),
		]
	})
	item := merge.next() or { panic('missing decoded text') }
	assert item == text_event('file_name & “decoded”', 0, 35)
	assert probe.calls == 5
}

fn test_merge_uses_first_start_and_last_end_even_for_disjoint_ranges() {
	mut probe := &Probe{}
	mut merge := DecodedTextMerge.new(ScriptIterator{
		probe:  probe
		script: [
			yielded(text_event('a', 30, 40)),
			yielded(text_event('b', 90, 100)),
			yielded(text_event('c', 0, 2)),
		]
	})
	assert merge.next() or { panic('missing text') } == text_event('abc', 30, 2)
}

fn test_empty_text_events_are_merged_and_update_the_end() {
	mut probe := &Probe{}
	mut merge := DecodedTextMerge.new(ScriptIterator{
		probe:  probe
		script: [
			yielded(text_event('', 4, 5)),
			yielded(text_event('body', 6, 10)),
			yielded(text_event('', 10, 14)),
		]
	})
	assert merge.next() or { panic('missing text') } == text_event('body', 4, 14)
}

fn test_all_empty_text_events_still_yield_one_empty_text() {
	mut probe := &Probe{}
	mut merge := DecodedTextMerge.new(ScriptIterator{
		probe:  probe
		script: [
			yielded(text_event('', 3, 3)),
			yielded(text_event('', 7, 9)),
		]
	})
	assert merge.next() or { panic('missing empty text') } == text_event('', 3, 9)
	if _ := merge.next() {
		assert false
	}
}

fn test_nontext_does_not_peek_or_consume_the_following_event() {
	mut probe := &Probe{}
	mut merge := DecodedTextMerge.new(ScriptIterator{
		probe:  probe
		script: [
			yielded(nontext_event(pulldown_cmark.Event{ kind: .rule }, 1, 4)),
			yielded(text_event('later', 5, 10)),
		]
	})
	assert merge.next() or { panic('missing rule') } == nontext_event(pulldown_cmark.Event{ kind: .rule }, 1, 4)
	assert probe.calls == 1
	assert merge.next() or { panic('missing following text') } == text_event('later', 5, 10)
}

fn test_each_nontext_variant_preserves_payload_and_range() {
	mut probe := &Probe{}
	mut merge := DecodedTextMerge.new(ScriptIterator{
		probe:  probe
		script: [
			yielded(nontext_event(pulldown_cmark.Event{
				kind: .start
				tag:  pulldown_cmark.Tag{
					kind:      .link
					link_type: .reference_unknown
					dest_url:  pulldown_cmark.CowStr.from_string('https://example.test/?x=1&y=2')
					title:     pulldown_cmark.CowStr.from_string('decoded title')
					link_id:   pulldown_cmark.CowStr.from_string('reference-id')
				}
			}, 5, 50)),
			yielded(nontext_event(pulldown_cmark.Event{
				kind:    .end
				tag_end: pulldown_cmark.TagEnd{
					kind:    .list
					ordered: true
				}
			}, 51, 54)),
			yielded(nontext_event(pulldown_cmark.Event{ kind: .code, text: pulldown_cmark.CowStr.from_string('`decoded`') }, 55, 70)),
			yielded(nontext_event(pulldown_cmark.Event{ kind: .html, text: pulldown_cmark.CowStr.from_string('<div>x</div>') }, 71, 82)),
			yielded(nontext_event(pulldown_cmark.Event{ kind: .inline_html, text: pulldown_cmark.CowStr.from_string('<b>') }, 82, 85)),
			yielded(nontext_event(pulldown_cmark.Event{ kind: .footnote_reference, text: pulldown_cmark.CowStr.from_string('note') }, 86, 93)),
			yielded(nontext_event(pulldown_cmark.Event{ kind: .soft_break }, 94, 95)),
			yielded(nontext_event(pulldown_cmark.Event{ kind: .hard_break }, 96, 99)),
			yielded(nontext_event(pulldown_cmark.Event{ kind: .rule }, 100, 103)),
			yielded(nontext_event(pulldown_cmark.Event{ kind: .task_list_marker, checked: true }, 104, 107)),
		]
	})
	link := merge.next() or { panic('missing link') }
	assert link == nontext_event(pulldown_cmark.Event{
		kind: .start
		tag:  pulldown_cmark.Tag{
			kind:      .link
			link_type: .reference_unknown
			dest_url:  pulldown_cmark.CowStr.from_string('https://example.test/?x=1&y=2')
			title:     pulldown_cmark.CowStr.from_string('decoded title')
			link_id:   pulldown_cmark.CowStr.from_string('reference-id')
		}
	}, 5, 50)
	assert merge.next() or { panic('missing end') } == nontext_event(pulldown_cmark.Event{ kind: .end, tag_end: pulldown_cmark.TagEnd{ kind: .list, ordered: true } }, 51, 54)
	assert merge.next() or { panic('missing code') } == nontext_event(pulldown_cmark.Event{ kind: .code, text: pulldown_cmark.CowStr.from_string('`decoded`') }, 55, 70)
	assert merge.next() or { panic('missing html') } == nontext_event(pulldown_cmark.Event{ kind: .html, text: pulldown_cmark.CowStr.from_string('<div>x</div>') }, 71, 82)
	assert merge.next() or { panic('missing inline html') } == nontext_event(pulldown_cmark.Event{ kind: .inline_html, text: pulldown_cmark.CowStr.from_string('<b>') }, 82, 85)
	assert merge.next() or { panic('missing reference') } == nontext_event(pulldown_cmark.Event{ kind: .footnote_reference, text: pulldown_cmark.CowStr.from_string('note') }, 86, 93)
	assert merge.next() or { panic('missing soft break') } == nontext_event(pulldown_cmark.Event{ kind: .soft_break }, 94, 95)
	assert merge.next() or { panic('missing hard break') } == nontext_event(pulldown_cmark.Event{ kind: .hard_break }, 96, 99)
	assert merge.next() or { panic('missing rule') } == nontext_event(pulldown_cmark.Event{ kind: .rule }, 100, 103)
	assert merge.next() or { panic('missing task marker') } == nontext_event(pulldown_cmark.Event{ kind: .task_list_marker, checked: true }, 104, 107)
	assert probe.calls == 10
}

fn test_code_and_breaks_separate_text_runs() {
	mut probe := &Probe{}
	mut merge := DecodedTextMerge.new(ScriptIterator{
		probe:  probe
		script: [
			yielded(text_event('a', 0, 1)),
			yielded(nontext_event(pulldown_cmark.Event{ kind: .code, text: pulldown_cmark.CowStr.from_string('b') }, 1, 4)),
			yielded(text_event('c', 4, 5)),
			yielded(text_event('d', 5, 6)),
			yielded(nontext_event(pulldown_cmark.Event{ kind: .hard_break }, 6, 9)),
			yielded(text_event('e', 9, 10)),
		]
	})
	assert merge.next() or { panic('missing first text') } == text_event('a', 0, 1)
	assert merge.next() or { panic('missing code') } == nontext_event(pulldown_cmark.Event{ kind: .code, text: pulldown_cmark.CowStr.from_string('b') }, 1, 4)
	assert merge.next() or { panic('missing merged second run') } == text_event('cd', 4, 6)
	assert merge.next() or { panic('missing break') } == nontext_event(pulldown_cmark.Event{ kind: .hard_break }, 6, 9)
	assert merge.next() or { panic('missing last text') } == text_event('e', 9, 10)
}

fn test_peeked_end_is_cached_but_iterator_is_not_fused() {
	mut probe := &Probe{}
	mut merge := DecodedTextMerge.new(ScriptIterator{
		probe:  probe
		script: [
			yielded(text_event('before', 0, 6)),
			Yield{},
			yielded(text_event('after', 8, 13)),
			Yield{},
		]
	})
	assert merge.next() or { panic('missing before') } == text_event('before', 0, 6)
	assert probe.calls == 2
	if _ := merge.next() {
		assert false
	}
	assert probe.calls == 2
	assert merge.next() or { panic('missing after') } == text_event('after', 8, 13)
	assert probe.calls == 4
	if _ := merge.next() {
		assert false
	}
	assert probe.calls == 4
}

fn test_single_borrowed_text_keeps_its_borrow_without_copying() {
	mut owner := 'borrowed decoded text'
	$if ownership ? {
		owner = 'borrowed decoded text'.to_owned()
	}
	mut probe := &Probe{}
	mut merge := DecodedTextMerge.new(ScriptIterator{
		probe:  probe
		script: [yielded(EventRange{
			event: pulldown_cmark.Event{ kind: .text, text: pulldown_cmark.CowStr.from_str(&owner) }
			range: std_ops.Range[usize]{ start: 4, end: 32 }
		})]
	})
	item := merge.next() or { panic('missing borrowed text') }
	assert item.event.text.as_str() == &owner
	assert *item.event.text.as_str() == 'borrowed decoded text'
	assert *item.event.text.as_str() == owner
	assert owner == 'borrowed decoded text'
}

fn test_merging_borrowed_text_keeps_both_dynamic_owners_reusable() {
	mut first := 'dynamic left '
	mut second := 'dynamic right'
	$if ownership ? {
		first = 'dynamic left '.to_owned()
		second = 'dynamic right'.to_owned()
	}
	mut probe := &Probe{}
	mut merge := DecodedTextMerge.new(ScriptIterator{
		probe:  probe
		script: [
			yielded(EventRange{ event: pulldown_cmark.Event{ kind: .text, text: pulldown_cmark.CowStr.from_str(&first) }, range: std_ops.Range[usize]{ start: 10, end: 24 } }),
			yielded(EventRange{ event: pulldown_cmark.Event{ kind: .text, text: pulldown_cmark.CowStr.from_str(&second) }, range: std_ops.Range[usize]{ start: 24, end: 37 } }),
		]
	})
	item := merge.next() or { panic('missing merged borrowed text') }
	assert *item.event.text.as_str() == 'dynamic left dynamic right'
	assert *item.event.text.as_str() == 'dynamic left dynamic right'
	assert first == 'dynamic left '
	assert second == 'dynamic right'
	assert item.range == std_ops.Range[usize]{ start: 10, end: 37 }
}

fn test_merging_boxed_and_inline_unicode_contents() {
	mut owned := 'owned text '
	$if ownership ? {
		owned = 'owned text '.to_owned()
	}
	mut probe := &Probe{}
	mut merge := DecodedTextMerge.new(ScriptIterator{
		probe:  probe
		script: [
			yielded(text_event(owned, 3, 15)),
			yielded(EventRange{ event: pulldown_cmark.Event{ kind: .text, text: pulldown_cmark.CowStr.from_char(`藏`) }, range: std_ops.Range[usize]{ start: 15, end: 18 } }),
			yielded(EventRange{ event: pulldown_cmark.Event{ kind: .text, text: pulldown_cmark.CowStr.from_char(`🍔`) }, range: std_ops.Range[usize]{ start: 18, end: 22 } }),
		]
	})
	assert merge.next() or { panic('missing Unicode text') } == text_event('owned text 藏🍔', 3, 22)
}

struct GeneratedIterator {
mut:
	index int
	probe &Probe
}

fn (mut iter GeneratedIterator) next() ?EventRange {
	iter.probe.calls++
	iter.index++
	return if iter.index % 2 == 1 {
		text_event('generated', usize(iter.index), usize(iter.index + 1))
	} else {
		nontext_event(pulldown_cmark.Event{ kind: .soft_break }, usize(iter.index), usize(iter.index + 1))
	}
}

fn test_generic_merge_accepts_an_infinite_lazy_generator() {
	mut probe := &Probe{}
	mut merge := DecodedTextMerge.new(GeneratedIterator{ probe: probe })
	assert probe.calls == 0
	assert merge.next() or { panic('missing generated text') } == text_event('generated', 1, 2)
	assert probe.calls == 2
	assert merge.next() or { panic('missing generated break') } == nontext_event(pulldown_cmark.Event{ kind: .soft_break }, 2, 3)
	assert probe.calls == 2
	assert merge.next() or { panic('missing later text') } == text_event('generated', 3, 4)
	assert probe.calls == 4
}

fn owned_test_string(value string) string {
	$if ownership ? {
		return value.to_owned()
	} $else {
		return value.clone()
	}
}

fn test_heading_metadata_and_optional_attribute_values_are_preserved() {
	mut probe := &Probe{}
	mut merge := DecodedTextMerge.new(ScriptIterator{
		probe:  probe
		script: [yielded(nontext_event(pulldown_cmark.Event{
			kind: .start
			tag:  pulldown_cmark.Tag{
				kind:    .heading
				level:   .h4
				id:      pulldown_cmark.OptionalCowStr{
					present: true
					value:   pulldown_cmark.CowStr.from_string(owned_test_string('heading-id'))
				}
				classes: [
					pulldown_cmark.CowStr.from_string(owned_test_string('first-class')),
					pulldown_cmark.CowStr.from_string(owned_test_string('second-class')),
				]
				attrs:   [
					pulldown_cmark.HeadingAttribute{
						name:  pulldown_cmark.CowStr.from_string(owned_test_string('key'))
						value: pulldown_cmark.OptionalCowStr{
							present: true
							value:   pulldown_cmark.CowStr.from_string(owned_test_string('value'))
						}
					},
					pulldown_cmark.HeadingAttribute{
						name: pulldown_cmark.CowStr.from_string(owned_test_string('without-value'))
					},
				]
			}
		}, 8, 64))]
	})
	item := merge.next() or { panic('missing heading') }
	assert item.range == std_ops.Range[usize]{ start: 8, end: 64 }
	assert item.event.kind == .start
	assert item.event.tag.kind == .heading
	assert item.event.tag.level == .h4
	assert item.event.tag.id.present
	assert *item.event.tag.id.value.as_str() == 'heading-id'
	assert *item.event.tag.classes[0].as_str() == 'first-class'
	assert *item.event.tag.classes[1].as_str() == 'second-class'
	assert *item.event.tag.attrs[0].name.as_str() == 'key'
	assert item.event.tag.attrs[0].value.present
	assert *item.event.tag.attrs[0].value.value.as_str() == 'value'
	assert *item.event.tag.attrs[1].name.as_str() == 'without-value'
	assert !item.event.tag.attrs[1].value.present
	assert *item.event.tag.id.value.as_str() == 'heading-id'
	assert probe.calls == 1
}

fn test_typed_table_alignment_and_fenced_code_language_survive_cached_passthrough() {
	mut probe := &Probe{}
	mut merge := DecodedTextMerge.new(ScriptIterator{
		probe:  probe
		script: [
			yielded(text_event('before', 1, 7)),
			yielded(nontext_event(pulldown_cmark.Event{
				kind: .start
				tag:  pulldown_cmark.Tag{ kind: .table, alignments: [.left, .none, .right, .center] }
			}, 9, 60)),
			yielded(text_event('after', 60, 65)),
			yielded(nontext_event(pulldown_cmark.Event{
				kind: .start
				tag:  pulldown_cmark.Tag{
					kind:       .code_block
					code_block: pulldown_cmark.CodeBlockKind{
						kind:     .fenced
						language: pulldown_cmark.CowStr.from_string(owned_test_string('v decoded-language'))
					}
				}
			}, 65, 85)),
		]
	})
	assert merge.next() or { panic('missing text') } == text_event('before', 1, 7)
	table := merge.next() or { panic('missing table') }
	assert table.event.tag.kind == .table
	assert table.event.tag.alignments == [pulldown_cmark.Alignment.left, .none, .right, .center]
	assert table.range == std_ops.Range[usize]{ start: 9, end: 60 }
	assert merge.next() or { panic('missing second text') } == text_event('after', 60, 65)
	code := merge.next() or { panic('missing fenced block') }
	assert code.event.tag.kind == .code_block
	assert code.event.tag.code_block.kind == .fenced
	assert *code.event.tag.code_block.language.as_str() == 'v decoded-language'
	assert *code.event.tag.code_block.language.as_str() == 'v decoded-language'
	assert code.range == std_ops.Range[usize]{ start: 65, end: 85 }
}

fn test_list_footnote_and_metadata_payloads_are_not_flattened() {
	mut probe := &Probe{}
	mut merge := DecodedTextMerge.new(ScriptIterator{
		probe:  probe
		script: [
			yielded(nontext_event(pulldown_cmark.Event{
				kind: .start
				tag:  pulldown_cmark.Tag{ kind: .list, list_start: u64(18446744073709551615) }
			}, 2, 22)),
			yielded(nontext_event(pulldown_cmark.Event{
				kind: .start
				tag:  pulldown_cmark.Tag{ kind: .footnote_definition, footnote_label: pulldown_cmark.CowStr.from_string(owned_test_string('note-label')) }
			}, 24, 42)),
			yielded(nontext_event(pulldown_cmark.Event{
				kind: .start
				tag:  pulldown_cmark.Tag{ kind: .metadata_block, metadata_kind: .pluses_style }
			}, 44, 47)),
			yielded(nontext_event(pulldown_cmark.Event{
				kind:    .end
				tag_end: pulldown_cmark.TagEnd{ kind: .metadata_block, metadata_kind: .pluses_style }
			}, 50, 53)),
		]
	})
	list := merge.next() or { panic('missing list') }
	assert list.event.tag.kind == .list
	assert list.event.tag.list_start or { u64(0) } == u64(18446744073709551615)
	footnote := merge.next() or { panic('missing footnote') }
	assert footnote.event.tag.kind == .footnote_definition
	assert *footnote.event.tag.footnote_label.as_str() == 'note-label'
	metadata := merge.next() or { panic('missing metadata') }
	assert metadata.event.tag.kind == .metadata_block
	assert metadata.event.tag.metadata_kind == .pluses_style
	end := merge.next() or { panic('missing metadata end') }
	assert end.event.tag_end.kind == .metadata_block
	assert end.event.tag_end.metadata_kind == .pluses_style
	assert probe.calls == 4
}

fn test_generic_iterator_can_be_composed_with_another_merge() {
	mut probe := &Probe{}
	inner := DecodedTextMerge.new(ScriptIterator{
		probe:  probe
		script: [
			yielded(text_event('nested ', 4, 11)),
			yielded(text_event('merge', 11, 16)),
			yielded(nontext_event(pulldown_cmark.Event{ kind: .soft_break }, 16, 17)),
		]
	})
	mut outer := DecodedTextMerge.new(inner)
	assert probe.calls == 0
	assert outer.next() or { panic('missing nested text') } == text_event('nested merge', 4, 16)
	assert probe.calls == 3
	assert outer.next() or { panic('missing nested boundary') } == nontext_event(pulldown_cmark.Event{ kind: .soft_break }, 16, 17)
	assert probe.calls == 3
}

fn test_owned_cached_payloads_survive_refills_and_remain_reusable_after_draining() {
	mut probe := &Probe{}
	mut merge := DecodedTextMerge.new(ScriptIterator{
		probe:  probe
		script: [
			yielded(text_event(owned_test_string('first dynamic text, '), 1, 21)),
			yielded(text_event(owned_test_string('with owned continuation'), 21, 44)),
			yielded(nontext_event(pulldown_cmark.Event{
				kind: .html
				text: pulldown_cmark.CowStr.from_string(owned_test_string('<div>cached dynamic HTML payload</div>'))
			}, 44, 81)),
			yielded(text_event(owned_test_string('second dynamic text, '), 81, 102)),
			yielded(text_event(owned_test_string('with another owned continuation'), 102, 133)),
			yielded(nontext_event(pulldown_cmark.Event{
				kind: .start
				tag:  pulldown_cmark.Tag{
					kind:    .heading
					level:   .h2
					id:      pulldown_cmark.OptionalCowStr{
						present: true
						value:   pulldown_cmark.CowStr.from_string(owned_test_string('dynamic cached heading-id'))
					}
					classes: [pulldown_cmark.CowStr.from_string(owned_test_string('dynamic cached class'))]
					attrs:   [pulldown_cmark.HeadingAttribute{
						name:  pulldown_cmark.CowStr.from_string(owned_test_string('dynamic cached attribute'))
						value: pulldown_cmark.OptionalCowStr{
							present: true
							value:   pulldown_cmark.CowStr.from_string(owned_test_string('dynamic cached value'))
						}
					}]
				}
			}, 133, 199)),
			yielded(text_event(owned_test_string('third dynamic text, '), 199, 219)),
			yielded(text_event(owned_test_string('with final owned continuation'), 219, 248)),
			yielded(nontext_event(pulldown_cmark.Event{ kind: .soft_break }, 248, 249)),
		]
	})
	first := merge.next() or { panic('missing first owned run') }
	html := merge.next() or { panic('missing cached HTML') }
	second := merge.next() or { panic('missing second owned run') }
	heading := merge.next() or { panic('missing cached heading') }
	third := merge.next() or { panic('missing third owned run') }
	_ := merge.next() or { panic('missing cached boundary') }
	if _ := merge.next() {
		assert false
	}
	assert *first.event.text.as_str() == 'first dynamic text, with owned continuation'
	assert *html.event.text.as_str() == '<div>cached dynamic HTML payload</div>'
	assert *second.event.text.as_str() == 'second dynamic text, with another owned continuation'
	assert *heading.event.tag.id.value.as_str() == 'dynamic cached heading-id'
	assert *heading.event.tag.classes[0].as_str() == 'dynamic cached class'
	assert *heading.event.tag.attrs[0].name.as_str() == 'dynamic cached attribute'
	assert *heading.event.tag.attrs[0].value.value.as_str() == 'dynamic cached value'
	assert *third.event.text.as_str() == 'third dynamic text, with final owned continuation'
	assert *html.event.text.as_str() == '<div>cached dynamic HTML payload</div>'
	assert *first.event.text.as_str() == 'first dynamic text, with owned continuation'
	assert *heading.event.tag.classes[0].as_str() == 'dynamic cached class'
	assert probe.calls == 10
}

fn cached_borrowed_heading_after_iterator_teardown(id &string, class &string, name &string, value &string) EventRange {
	mut probe := &Probe{}
	mut merge := DecodedTextMerge.new(ScriptIterator{
		probe:  probe
		script: [
			yielded(text_event(owned_test_string('before heading'), 0, 14)),
			yielded(nontext_event(pulldown_cmark.Event{
				kind: .start
				tag:  pulldown_cmark.Tag{
					kind:    .heading
					level:   .h3
					id:      pulldown_cmark.OptionalCowStr{ present: true, value: pulldown_cmark.CowStr.from_str(id) }
					classes: [pulldown_cmark.CowStr.from_str(class)]
					attrs:   [pulldown_cmark.HeadingAttribute{
						name:  pulldown_cmark.CowStr.from_str(name)
						value: pulldown_cmark.OptionalCowStr{ present: true, value: pulldown_cmark.CowStr.from_str(value) }
					}]
				}
			}, 14, 40)),
			yielded(text_event(owned_test_string('after '), 40, 46)),
			yielded(text_event(owned_test_string('heading'), 46, 53)),
			yielded(nontext_event(pulldown_cmark.Event{ kind: .soft_break }, 53, 54)),
		]
	})
	assert merge.next() or { panic('missing leading text') } == text_event('before heading', 0, 14)
	heading := merge.next() or { panic('missing borrowed cached heading') }
	assert merge.next() or { panic('missing following text') } == text_event('after heading', 40, 53)
	_ := merge.next() or { panic('missing final boundary') }
	if _ := merge.next() {
		assert false
	}
	assert probe.calls == 6
	return heading
}

fn test_borrowed_cached_heading_survives_refills_and_iterator_teardown() {
	mut id := 'borrowed dynamic heading id'
	mut class := 'borrowed dynamic heading class'
	mut name := 'borrowed dynamic attribute name'
	mut value := 'borrowed dynamic attribute value'
	$if ownership ? {
		id = 'borrowed dynamic heading id'.to_owned()
		class = 'borrowed dynamic heading class'.to_owned()
		name = 'borrowed dynamic attribute name'.to_owned()
		value = 'borrowed dynamic attribute value'.to_owned()
	}
	heading := cached_borrowed_heading_after_iterator_teardown(&id, &class, &name, &value)
	assert heading.range == std_ops.Range[usize]{ start: 14, end: 40 }
	assert heading.event.tag.level == .h3
	assert heading.event.tag.id.value.as_str() == &id
	assert heading.event.tag.classes[0].as_str() == &class
	assert heading.event.tag.attrs[0].name.as_str() == &name
	assert heading.event.tag.attrs[0].value.value.as_str() == &value
	assert *heading.event.tag.id.value.as_str() == 'borrowed dynamic heading id'
	assert *heading.event.tag.classes[0].as_str() == 'borrowed dynamic heading class'
	assert *heading.event.tag.attrs[0].name.as_str() == 'borrowed dynamic attribute name'
	assert *heading.event.tag.attrs[0].value.value.as_str() == 'borrowed dynamic attribute value'
	assert *heading.event.tag.classes[0].as_str() == class
	assert *heading.event.tag.attrs[0].value.value.as_str() == value
	assert id == 'borrowed dynamic heading id'
	assert class == 'borrowed dynamic heading class'
	assert name == 'borrowed dynamic attribute name'
	assert value == 'borrowed dynamic attribute value'
}
