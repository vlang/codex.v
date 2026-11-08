// Portable HTML for copying Markdown responses into rich-text applications.
//
// Raw HTML is escaped, and destinations use the TUI's web-link policy. Link
// destinations that cannot be linked remain visible as escaped text. The original
// Markdown remains the plain-text clipboard representation. Images render only
// their alt text so pasting cannot trigger remote image requests.
module clipboard_html

import pulldown_cmark
import pulldown_cmark.html
import strings
import codex_tui.markdown as markdown_module
import codex_tui.terminal_hyperlinks

// V represents Rust's closure-captured Vec<Option<CowStr>> with explicit tagged
// slots: None denotes a permitted link and Some preserves an inert destination.
struct LinkDestination {
	inert bool
	value pulldown_cmark.CowStr
}

struct RenderMarkdownState {
mut:
	link_destinations []LinkDestination
}

pub fn render_markdown(markdown &string) string {
	normalized := markdown_module.unwrap_markdown_fences(markdown)
	options := pulldown_cmark.Options.enable_strikethrough | pulldown_cmark.Options.enable_tables
	// V cannot capture a mutable vector in a closure; the same filter_map closure
	// is a named mapper borrowing state. Filtering stays before html::push_html.
	parser := pulldown_cmark.Parser.new_ext(&normalized, options)
	mut events := parser.filter_map(RenderMarkdownState{}, filter_markdown_event)
	mut output := strings.new_builder(0)
	html.push_html(mut output, mut events)
	return output.str()
}

// Equivalent to render_markdown's Rust filter_map closure, including the
// destination stack and image-wrapper removal while retaining all alt events.
fn filter_markdown_event(event pulldown_cmark.Event, mut state RenderMarkdownState) ?pulldown_cmark.Event {
	match event.kind {
		.html, .inline_html { return pulldown_cmark.Event{ kind: .text, text: event.text } }
		.start {
			if event.tag.kind == .image {
				return none
			}
			if event.tag.kind == .link {
				if destination := terminal_hyperlinks.web_destination(event.tag.dest_url.as_str()) {
					state.link_destinations << LinkDestination{}
					return pulldown_cmark.Event{ kind: .start, tag: event.tag.with_link_destination(pulldown_cmark.CowStr.from_string(destination)) }
				} else {
					state.link_destinations << LinkDestination{ inert: true, value: pulldown_cmark.CowStr.from_string(event.tag.dest_url.as_str().clone()) }
					return none
				}
			}
			return event
		}
		.end {
			if event.tag_end.kind == .image {
				return none
			}
			if event.tag_end.kind == .link && state.link_destinations.len > 0 {
				index := state.link_destinations.len - 1
				destination := state.link_destinations[index]
				state.link_destinations[index] = LinkDestination{}
				state.link_destinations.delete_last()
				if destination.inert {
					return pulldown_cmark.Event{ kind: .text, text: pulldown_cmark.CowStr.from_string(' (${*destination.value.as_str()})') }
				}
			}
			return event
		}
		else { return event }
	}
}
