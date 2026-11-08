module prelude

import ratatui.style

// STUB: ratatui::prelude re-exports of `ratatui::style`. V rejects `import ratatui.style` (even
// with an alias) inside a translated module that is itself named `style`, so such modules name
// the ratatui types through these re-exports instead.
pub type Color = style.Color

// STUB: ratatui::prelude re-export of the `Color` variant tags.
pub type ColorKind = style.ColorKind

// STUB: ratatui::prelude re-export of `ratatui::style::Modifier`.
pub type Modifier = style.Modifier

// STUB: ratatui::prelude re-export of `ratatui::style::Style`.
pub type Style = style.Style
