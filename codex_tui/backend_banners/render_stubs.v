module backend_banners

import codex_tui.bottom_pane

// STUB: backend_banners/render.rs::BackendBanner::actionable_banner, limited
// to the original parser tests' view_usage CTA label projection. The source
// validates labels, preserves order and duplicates, and clones each name.
// Other action resolution, rendered copy, dismissal, and dispatch callbacks
// await the actions/render modules; unsupported actions fail explicitly here.
pub fn (banner &BackendBanner) actionable_banner() bottom_pane.ActionableBanner {
	mut actions := []bottom_pane.SelectionItem{}
	for index in 0 .. banner.ctas.len {
		cta := &banner.ctas[index]
		if !rust_trim_is_empty(&cta.label) && cta.label.len <= 256 && !has_rust_control(&cta.label) {
			if cta.action != 'view_usage' {
				panic('backend banner action rendering is not translated: ${cta.action}')
			}
			actions << bottom_pane.SelectionItem{ name: cta.label.clone() }
		}
	}
	return bottom_pane.ActionableBanner{ actions: actions }
}
