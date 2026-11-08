module codex_protocol

$if ownership ? {
	import json2
}

// V3 0.5.2 rejects json2's unspecialized generic counter when this module is imported by an
// ownership build that otherwise only decodes JSON. A concrete encode keeps that compiler-only
// specialization available; the branch is absent from normal builds.
struct ThreadProcessorJson2OwnershipProbe {
	value string
}

fn init() {
	$if ownership ? {
		_ = json2.encode(ThreadProcessorJson2OwnershipProbe{ value: 'probe' })
	}
}
