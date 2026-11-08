// Surface-independent literal Vim search queries. Matches span complete graphemes;
// callers own navigation, operator ranges, and the lifetime of accepted versus pending input.
module vim_search

import std_ops
import unicode_segmentation

pub enum SearchDirection {
	forward
	backward
}

pub fn SearchDirection.default() SearchDirection {
	return .forward
}

pub fn (direction SearchDirection) reversed() SearchDirection {
	return match direction {
		.forward { SearchDirection.backward }
		.backward { SearchDirection.forward }
	}
}

pub struct SearchQuery {
pub mut:
	text      string
	direction SearchDirection
}

pub fn SearchQuery.default() SearchQuery {
	return SearchQuery{}
}

pub fn (query &SearchQuery) clone() SearchQuery {
	return SearchQuery{
		text:      query.text.clone()
		direction: query.direction
	}
}

// V names Rust's opaque borrowing iterator. The text and query owners must outlive it,
// matching the source lifetime; neither owner is copied or consumed. The existing Unicode
// adapter yields byte offsets instead of a borrowing iterator, so boundary storage is
// initialized at the first next() call. Match filtering and range production remain lazy.
pub struct MatchingRanges {
	text  &string = unsafe { nil }
	query &string = unsafe { nil }
mut:
	initialized bool
	graphemes   []int
	cursor      int
}

pub fn matching_ranges(text &string, query &string) MatchingRanges {
	return MatchingRanges{
		text:  text
		query: query
	}
}

pub fn (mut ranges MatchingRanges) next() ?std_ops.Range[usize] {
	if ranges.query.len == 0 {
		return none
	}
	if !ranges.initialized {
		ranges.graphemes = unicode_segmentation.grapheme_indices(ranges.text, /* is_extended */
			true)
		ranges.initialized = true
	}
	for ranges.cursor < ranges.graphemes.len {
		start := ranges.graphemes[ranges.cursor]
		ranges.cursor++
		if ranges.query.len > ranges.text.len - start {
			continue
		}
		// Compare the borrowed UTF-8 bytes directly: V's owned substring API would
		// otherwise allocate a temporary string for Rust's text[start..].starts_with(query).
		mut matches := true
		for offset in 0 .. ranges.query.len {
			if (*ranges.text)[start + offset] != (*ranges.query)[offset] {
				matches = false
				break
			}
		}
		if !matches {
			continue
		}
		mut end := ranges.text.len
		// Starting at a complete extended grapheme boundary gives the same suffix
		// boundaries as grapheme_indices(/* is_extended */ true) in Rust's second iterator.
		for index in ranges.cursor .. ranges.graphemes.len {
			candidate := ranges.graphemes[index]
			if candidate >= start + ranges.query.len {
				end = candidate
				break
			}
		}
		return std_ops.Range[usize]{
			start: usize(start)
			end:   usize(end)
		}
	}
	return none
}
