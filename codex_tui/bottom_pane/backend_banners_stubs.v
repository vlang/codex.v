module bottom_pane

// STUB: bottom_pane::list_selection_view::SelectionItem. Backend banner tests
// observe owned action names; selection callbacks and the remaining list UI
// fields await the list-selection translation.
pub struct SelectionItem {
pub:
	name string
}

// STUB: bottom_pane::actionable_banner::ActionableBanner's observed ordered
// action list. Copy, dismissal, and UI event callbacks await that translation.
pub struct ActionableBanner {
pub:
	actions []SelectionItem
}
