module codex_install_context

import codex_utils_absolute_path

// STUB: codex-install-context::StandalonePlatform is the Copy platform tag.
pub enum StandalonePlatform {
	unix
	windows
}

// STUB: codex-install-context::CodexPackageLayout preserves the eventual
// package owner's full path fields; package discovery is untranslated.
pub struct CodexPackageLayout {
pub:
	package_dir   codex_utils_absolute_path.AbsolutePathBuf
	bin_dir       codex_utils_absolute_path.AbsolutePathBuf
	resources_dir ?codex_utils_absolute_path.AbsolutePathBuf
	path_dir      ?codex_utils_absolute_path.AbsolutePathBuf
}

// STUB: codex-install-context::InstallContext retains the real owned method and
// optional package layout. The InstallMethod enum uses typed V payload variants.
@[heap]
pub struct InstallContext {
pub:
	method         InstallMethod = Other{}
	package_layout ?CodexPackageLayout
}

// STUB: codex-install-context::InstallMethod's complete enum variant set.
pub type InstallMethod = Brew | Bun | Npm | Other | Pnpm | Standalone | VitePlus

// STUB: codex-install-context::InstallMethod::Standalone's owned path payload.
pub struct Standalone {
pub:
	release_dir   codex_utils_absolute_path.AbsolutePathBuf
	resources_dir ?codex_utils_absolute_path.AbsolutePathBuf
	platform      StandalonePlatform
}

// STUB: codex-install-context::InstallMethod::Npm's allocation-free tag.
pub struct Npm {}

// STUB: codex-install-context::InstallMethod::Bun's allocation-free tag.
pub struct Bun {}

// STUB: codex-install-context::InstallMethod::Pnpm's allocation-free tag.
pub struct Pnpm {}

// STUB: codex-install-context::InstallMethod::VitePlus's allocation-free tag.
pub struct VitePlus {}

// STUB: codex-install-context::InstallMethod::Brew's allocation-free tag.
pub struct Brew {}

// STUB: codex-install-context::InstallMethod::Other's allocation-free tag.
pub struct Other {}

// STUB: codex-install-context's static OnceLock<InstallContext> boundary. Only
// test fixtures can initialize this cell until real installation discovery is
// translated. Heap owners keep previously returned shared views valid.
@[heap]
struct CurrentInstallContext {
mut:
	value &InstallContext = unsafe { nil }
}

// STUB: backing owner for the untranslated static InstallContext::current API.
const current_install_context = &CurrentInstallContext{}

// STUB: codex-install-context::InstallContext::current returns a shared static
// owner. Explicit failure prevents claiming that unknown installs are Other.
pub fn InstallContext.current() &InstallContext {
	if current_install_context.value == unsafe { nil } {
		panic('STUB: codex-install-context installation discovery is untranslated')
	}
	return current_install_context.value
}

$if test {
	// STUB: typed test-only fixture boundary for InstallContext::current; moves
	// the supplied owner into static heap storage without invoking discovery.
	pub fn InstallContext.set_current_fixture(context InstallContext) {
		mut cache := unsafe { current_install_context }
		cache.value = &InstallContext{
			method:         context.method
			package_layout: context.package_layout
		}
	}
}
