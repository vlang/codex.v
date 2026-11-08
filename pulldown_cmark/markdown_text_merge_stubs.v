module pulldown_cmark

// STUB: pulldown-cmark 0.10.3 CowStr variants. Inline strings use V string storage instead of
// Rust's fixed inline byte buffer; this loses the allocation optimization but retains decoded UTF-8.
pub enum CowStrKind {
	boxed
	borrowed
	inlined
}

// STUB: pulldown-cmark::CowStr preserves owned and shared-borrowed strings without a fake parser.
pub struct CowStr {
	kind     CowStrKind
	boxed    string
	borrowed &string = unsafe { nil }
	inlined  string
}

// STUB: pulldown-cmark::From<String> for CowStr consumes the owned string.
pub fn CowStr.from_string(value string) CowStr {
	return CowStr{ kind: .boxed, boxed: value }
}

// STUB: pulldown-cmark::From<&str> for CowStr borrows its owner; the owner must outlive the event.
pub fn CowStr.from_str(value &string) CowStr {
	return CowStr{ kind: .borrowed, borrowed: value }
}

// STUB: pulldown-cmark::From<char> for CowStr stores the scalar's decoded UTF-8 inline variant.
pub fn CowStr.from_char(value rune) CowStr {
	return CowStr{ kind: .inlined, inlined: value.str() }
}

// STUB: pulldown-cmark::CowStr::into_string moves boxed storage and copies borrowed/inline data.
pub fn (value CowStr) into_string() string {
	return match value.kind {
		.boxed { value.boxed }
		.borrowed { value.borrowed.clone() }
		.inlined { value.inlined.clone() }
	}
}

// STUB: pulldown-cmark::CowStr::as_ref/Deref returns a shared string view without allocation.
pub fn (value &CowStr) as_str() &string {
	return match value.kind {
		.boxed { &value.boxed }
		.borrowed { value.borrowed }
		.inlined { &value.inlined }
	}
}

// STUB: pulldown-cmark::MetadataBlockKind typed payload for Tag/TagEnd.
pub enum MetadataBlockKind {
	yaml_style
	pluses_style
}

// STUB: pulldown-cmark::HeadingLevel; values preserve Rust's explicit heading numbering.
pub enum HeadingLevel {
	h1 = 1
	h2
	h3
	h4
	h5
	h6
}

// STUB: pulldown-cmark::LinkType preserves reference, unresolved reference, and autolink variants.
pub enum LinkType {
	inline
	reference
	reference_unknown
	collapsed
	collapsed_unknown
	shortcut
	shortcut_unknown
	autolink
	email
}

// STUB: pulldown-cmark::Alignment for the typed table-column payload.
pub enum Alignment {
	none
	left
	center
	right
}

// STUB: pulldown-cmark::CodeBlockKind variant discriminator.
pub enum CodeBlockKindType {
	indented
	fenced
}

// STUB: pulldown-cmark::CodeBlockKind carries the fenced language, including an empty language.
pub struct CodeBlockKind {
pub:
	kind     CodeBlockKindType
	language CowStr
}

// STUB: owned Option<CowStr> representation used by heading IDs and attribute values. A tagged
// slot avoids V's unsafe &?CowStr and ?&CowStr representations; borrow the wrapper when inspecting.
pub struct OptionalCowStr {
pub:
	present bool
	value   CowStr
}

// STUB: pulldown-cmark heading attribute pair (CowStr, Option<CowStr>).
pub struct HeadingAttribute {
pub:
	name  CowStr
	value OptionalCowStr
}

// STUB: pulldown-cmark::Tag discriminator for every 0.10.3 block and inline variant.
pub enum TagKind {
	paragraph
	heading
	block_quote
	code_block
	html_block
	list
	item
	footnote_definition
	table
	table_head
	table_row
	table_cell
	emphasis
	strong
	strikethrough
	link
	image
	metadata_block
}

// STUB: pulldown-cmark::Tag's typed payloads. Only the fields belonging to kind are active;
// no tag, heading metadata, link target, list number, or table alignment is flattened into text.
pub struct Tag {
pub:
	kind           TagKind
	level          HeadingLevel = .h1
	id             OptionalCowStr
	classes        []CowStr
	attrs          []HeadingAttribute
	code_block     CodeBlockKind
	list_start     ?u64
	footnote_label CowStr
	alignments     []Alignment
	link_type      LinkType
	dest_url       CowStr
	title          CowStr
	link_id        CowStr
	metadata_kind  MetadataBlockKind
}

// STUB: pulldown-cmark::TagEnd retains Copy payloads for headings, ordered lists, and metadata.
pub struct TagEnd {
pub:
	kind          TagKind
	level         HeadingLevel = .h1
	ordered       bool
	metadata_kind MetadataBlockKind
}

// STUB: pulldown-cmark::Event variant discriminator.
pub enum EventKind {
	start
	end
	text
	code
	html
	inline_html
	footnote_reference
	soft_break
	hard_break
	rule
	task_list_marker
}

// STUB: pulldown-cmark::Event typed tagged payloads. Text/code/HTML/reference variants use text;
// start uses tag, end uses tag_end, and task_list_marker uses checked. Parser is untranslated.
pub struct Event {
pub:
	kind    EventKind
	tag     Tag
	tag_end TagEnd
	text    CowStr
	checked bool
}
