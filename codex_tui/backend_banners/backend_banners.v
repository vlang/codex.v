// Backend banner payload and CTA mapping, supplied by the existing account usage read.
//
// The backend owns eligibility, copy, actions, and ordered model fallback instructions.
module backend_banners

import codex_protocol.account
import serde_json

pub const luna_reserve_banner = 'luna_reserve'
pub const luna_reserve_recovery_view_id = 'luna-reserve-recovery'

pub struct BackendBanner {
pub mut:
	banner_type          string
	title                string
	description          string
	ctas                 []BackendBannerCta
	reset_at             ?i64
	model_slug           ?string
	blocked_model_slug   ?string
	fallback_model_slugs []string
	presentation         BannerPresentation = .inline
mut:
	request_url ?string
pub mut:
	account_id string
	plan_type  ?account.PlanType
}

pub enum BannerPresentation {
	inline
	dismissible
}

pub fn BannerPresentation.default() BannerPresentation {
	return .inline
}

pub struct BackendBannerCta {
mut:
	action string
	label  string
}

/// Parse supported, bounded content before constructing rendered copy or CTA closures.
pub fn BackendBanner.parse(raw &serde_json.Value) ?BackendBanner {
	banner := serde_json.from_value[BackendBanner](raw.clone(), BackendBanner.deserialize_value) or { return none }
	valid_slug := fn (slug &string) bool {
		return !rust_trim_is_empty(slug) && slug.len <= 256 && !has_rust_control(slug)
	}
	if banner.title.len > 1024 || banner.description.len > 4096 || banner.ctas.len > 8
		|| rust_trim_is_empty(&banner.title) || rust_lines_count(&banner.title) > 3
		|| rust_lines_count(&banner.description) > 12 {
		return none
	}
	if slug := banner.blocked_model_slug {
		if !valid_slug(&slug) { return none }
	}
	if banner.fallback_model_slugs.len > 16 { return none }
	for index in 0 .. banner.fallback_model_slugs.len {
		if !valid_slug(&banner.fallback_model_slugs[index]) { return none }
	}
	return banner
}

// Explicit serde Deserialize preserves required fields, optional nulls, the two
// #[serde(default)] fields, and the skipped account metadata. Its typed callback
// borrows the cloned JSON tree and returns owned strings at that borrow boundary.
pub fn BackendBanner.deserialize_value(raw &serde_json.Value) !BackendBanner {
	if !raw.is_object() && !raw.is_array() {
		return error('expected BackendBanner map or sequence')
	}
	mut banner := BackendBanner{ presentation: BannerPresentation.default() }
	// Serde visits sequence fields before rejecting extra elements. Only the
	// explicitly defaulted fields can be absent from a sequence.
	if raw.is_array() {
		for index in 0 .. 10 {
			field := raw.get_index(index)
			if field.has_value {
				deserialize_banner_field(mut banner, index, field.value)!
			} else if index != 7 && index != 8 {
				return error('invalid length ${index}, expected struct BackendBanner with 10 elements')
			}
		}
		length := raw.array_len()!
		if length > 10 {
			return error('invalid length ${length}, expected fewer elements in array')
		}
		return banner
	}
	// Preserve object entry traversal before checking missing required fields;
	// skipped metadata and unknown keys never invoke a field deserializer.
	mut present := [false, false, false, false]!
	object := raw.as_object()
	for index in 0 .. object.len() {
		key := object.key(index)
		field_index := banner_field_index(key)
		if field_index >= 0 {
			field := object.get(key)
			deserialize_banner_field(mut banner, field_index, field.value)!
			if field_index < 4 { present[field_index] = true }
		}
	}
	for index, key in [banner_type_key, title_key, description_key, ctas_key] {
		if !present[index] { return error('missing field `${key}`') }
	}
	return banner
}

fn deserialize_banner_field(mut banner BackendBanner, index int, raw &serde_json.Value) ! {
	match index {
		0 { banner.banner_type = raw.string_owned()! }
		1 { banner.title = raw.string_owned()! }
		2 { banner.description = raw.string_owned()! }
		3 {
			mut ctas := []BackendBannerCta{}
			for position in 0 .. raw.array_len()! {
				field := raw.get_index(position)
				ctas << BackendBannerCta.deserialize_value(field.value)!
			}
			banner.ctas = ctas
		}
		4 {
			decoded := optional_timestamp(raw)!
			banner.reset_at = decoded.into_option()
		}
		5 {
			decoded := optional_string(raw)!
			banner.model_slug = decoded.into_option()
		}
		6 {
			decoded := optional_string(raw)!
			banner.blocked_model_slug = decoded.into_option()
		}
		7 {
			mut slugs := []string{}
			for position in 0 .. raw.array_len()! {
				field := raw.get_index(position)
				slugs << field.value.string_owned()!
			}
			banner.fallback_model_slugs = slugs
		}
		8 { banner.presentation = BannerPresentation.deserialize_value(raw)! }
		9 {
			decoded := optional_string(raw)!
			banner.request_url = decoded.into_option()
		}
		else { panic('invalid BackendBanner field index') }
	}
}

fn banner_field_index(key &string) int {
	return match *key {
		'banner_type' { 0 }
		'title' { 1 }
		'description' { 2 }
		'ctas' { 3 }
		'reset_at' { 4 }
		'model_slug' { 5 }
		'blocked_model_slug' { 6 }
		'fallback_model_slugs' { 7 }
		'presentation' { 8 }
		'request_url' { 9 }
		else { -1 }
	}
}

pub fn BannerPresentation.deserialize_value(raw &serde_json.Value) !BannerPresentation {
	text := raw.as_str()
	if text.has_value {
		return presentation_variant(text.value)
	}
	object := raw.as_object()
	if object.has_value && object.len() == 1 {
		variant := object.key(0)
		presentation := presentation_variant(variant)!
		payload := object.get(variant)
		if payload.value.is_null() { return presentation }
	}
	return error('expected BannerPresentation unit variant')
}

pub fn BackendBannerCta.deserialize_value(raw &serde_json.Value) !BackendBannerCta {
	if !raw.is_object() && !raw.is_array() {
		return error('expected BackendBannerCta map or sequence')
	}
	if raw.is_array() {
		action := cta_sequence_field(raw, 0)!.string_owned()!
		label := cta_sequence_field(raw, 1)!.string_owned()!
		length := raw.array_len()!
		if length > 2 { return error('invalid length ${length}, expected fewer elements in array') }
		return BackendBannerCta{ action: action, label: label }
	}
	mut cta := BackendBannerCta{}
	mut action_present := false
	mut label_present := false
	object := raw.as_object()
	for index in 0 .. object.len() {
		key := object.key(index)
		field := object.get(key)
		match *key {
			'action' {
				cta.action = field.value.string_owned()!
				action_present = true
			}
			'label' {
				cta.label = field.value.string_owned()!
				label_present = true
			}
			else {}
		}
	}
	if !action_present { return error('missing field `action`') }
	if !label_present { return error('missing field `label`') }
	return cta
}

fn cta_sequence_field(raw &serde_json.Value, index int) !&serde_json.Value {
	field := raw.get_index(index)
	if field.has_value { return field.value }
	return error('invalid length ${index}, expected struct BackendBannerCta with 2 elements')
}

pub fn (banner &BackendBanner) clone() BackendBanner {
	mut ctas := []BackendBannerCta{cap: banner.ctas.len}
	for index in 0 .. banner.ctas.len { ctas << (&banner.ctas[index]).clone() }
	mut fallback_model_slugs := []string{cap: banner.fallback_model_slugs.len}
	for index in 0 .. banner.fallback_model_slugs.len {
		fallback_model_slugs << banner.fallback_model_slugs[index].clone()
	}
	return BackendBanner{
		banner_type:          banner.banner_type.clone()
		title:                banner.title.clone()
		description:          banner.description.clone()
		ctas:                 ctas
		reset_at:             banner.reset_at
		model_slug:           if value := banner.model_slug { value.clone() } else { none }
		blocked_model_slug:   if value := banner.blocked_model_slug { value.clone() } else { none }
		fallback_model_slugs: fallback_model_slugs
		presentation:         banner.presentation
		request_url:          if value := banner.request_url { value.clone() } else { none }
		account_id:           banner.account_id.clone()
		plan_type:            banner.plan_type
	}
}

pub fn (cta &BackendBannerCta) clone() BackendBannerCta {
	return BackendBannerCta{ action: cta.action.clone(), label: cta.label.clone() }
}

pub fn (banner &BackendBanner) equals(other &BackendBanner) bool {
	if banner.banner_type != other.banner_type || banner.title != other.title
		|| banner.description != other.description || banner.reset_at != other.reset_at
		|| banner.model_slug != other.model_slug || banner.blocked_model_slug != other.blocked_model_slug
		|| banner.presentation != other.presentation || banner.request_url != other.request_url
		|| banner.account_id != other.account_id || banner.plan_type != other.plan_type
		|| banner.ctas.len != other.ctas.len || banner.fallback_model_slugs.len != other.fallback_model_slugs.len {
		return false
	}
	for index in 0 .. banner.ctas.len {
		if !(&banner.ctas[index]).equals(&other.ctas[index]) { return false }
	}
	for index in 0 .. banner.fallback_model_slugs.len {
		if banner.fallback_model_slugs[index] != other.fallback_model_slugs[index] { return false }
	}
	return true
}

pub fn (cta &BackendBannerCta) equals(other &BackendBannerCta) bool {
	return cta.action == other.action && cta.label == other.label
}

fn presentation_variant(value &string) !BannerPresentation {
	return match *value {
		'inline' { BannerPresentation.inline }
		'dismissible' { BannerPresentation.dismissible }
		else { return error('unknown BannerPresentation variant') }
	}
}

// V cannot nest an Option inside a fallible return. This temporary tag retains
// serde's null/error distinction before assembling the owned optional field.
struct DecodedOptionalString {
	is_some bool
	value   string
}

fn optional_string(raw &serde_json.Value) !DecodedOptionalString {
	if raw.is_null() { return DecodedOptionalString{} }
	return DecodedOptionalString{ is_some: true, value: raw.string_owned()! }
}

fn (value DecodedOptionalString) into_option() ?string {
	if value.is_some { return value.value }
	return none
}

struct DecodedOptionalTimestamp {
	is_some bool
	value   i64
}

fn optional_timestamp(raw &serde_json.Value) !DecodedOptionalTimestamp {
	if raw.is_null() { return DecodedOptionalTimestamp{} }
	if value := raw.as_i64() { return DecodedOptionalTimestamp{ is_some: true, value: value } }
	return error('expected i64 timestamp')
}

fn (value DecodedOptionalTimestamp) into_option() ?i64 {
	if value.is_some { return value.value }
	return none
}

fn rust_trim_is_empty(text &string) bool {
	for character in text.runes() {
		if !(character in [`\t`, `\n`, `\v`, `\f`, `\r`, ` `, rune(0x85), rune(0xa0), rune(0x1680),
			rune(0x2028), rune(0x2029), rune(0x202f), rune(0x205f), rune(0x3000)] || (character >= 0x2000 && character <= 0x200a)) {
			return false
		}
	}
	return true
}

fn has_rust_control(text &string) bool {
	for character in text.runes() {
		if character <= 0x1f || (character >= 0x7f && character <= 0x9f) { return true }
	}
	return false
}

fn rust_lines_count(text &string) int {
	if text.len == 0 { return 0 }
	mut count := 0
	for byte in *text { if byte == `\n` { count++ } }
	return count + if (*text)[text.len - 1] == `\n` { 0 } else { 1 }
}

const banner_type_key = 'banner_type'
const title_key = 'title'
const description_key = 'description'
const ctas_key = 'ctas'
const reset_at_key = 'reset_at'
const model_slug_key = 'model_slug'
const blocked_model_slug_key = 'blocked_model_slug'
const fallback_model_slugs_key = 'fallback_model_slugs'
const presentation_key = 'presentation'
const request_url_key = 'request_url'
const action_key = 'action'
const label_key = 'label'
