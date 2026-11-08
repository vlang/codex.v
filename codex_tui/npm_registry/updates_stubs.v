module npm_registry

import serde_json

// STUB: tui/npm_registry.rs's release-only registry endpoint. The full module
// and its independent source tests remain a later translation target.
pub const package_url = 'https://registry.npmjs.org/@openai%2fcodex'

// STUB: npm_registry::NpmPackageInfo preserves both owned maps and serde's
// "dist-tags" wire name; metadata is not reduced to an untyped string.
pub struct NpmPackageInfo {
	dist_tags map[string]string
	versions  map[string]NpmPackageVersionInfo
}

// STUB: npm_registry::NpmPackageVersionInfo's observed nullable dist metadata.
pub struct NpmPackageVersionInfo {
	dist ?NpmPackageDist
}

// STUB: npm_registry::NpmPackageDist's two independently nullable strings.
pub struct NpmPackageDist {
	tarball   ?string
	integrity ?string
}

// STUB: npm's serde derive boundary; required top-level fields, wire names,
// duplicate known fields, and absent optional dist members are preserved.
pub fn NpmPackageInfo.deserialize_json(source &string) !NpmPackageInfo {
	fields := ['dist-tags', 'versions']
	input := serde_json.deserialize_struct(source, &fields)!
	mut tags := ?map[string]string(none)
	mut versions := ?map[string]NpmPackageVersionInfo(none)
	if input.is_sequence {
		if input.sequence.len != 2 {
			return error('invalid NpmPackageInfo sequence length')
		}
		tags = decode_dist_tags(&input.sequence[0])!
		versions = decode_versions(&input.sequence[1])!
	} else {
		for index in 0 .. input.fields.len {
			field := &input.fields[index]
			match field.name {
				'dist-tags' {
					if tags != none {
						return error('duplicate field `dist-tags`')
					}
					tags = decode_dist_tags(&field.value)!
				}
				'versions' {
					if versions != none {
						return error('duplicate field `versions`')
					}
					versions = decode_versions(&field.value)!
				}
				else {}
			}
		}
	}
	return NpmPackageInfo{ dist_tags: tags or { return error('missing field `dist-tags`') }, versions: versions or { return error('missing field `versions`') } }
}

// STUB: serde HashMap<String, String> constructs independent owned map entries.
fn decode_dist_tags(value &serde_json.Value) !map[string]string {
	keys := value.object_keys() or { return error('expected dist-tags map') }
	mut tags := map[string]string{}
	for index in 0 .. keys.len {
		key := &keys[index]
		entry := value.get(key)
		tags[key.clone()] = entry.value.string_owned()!
	}
	return tags
}

// STUB: serde HashMap<String, NpmPackageVersionInfo> retains typed dist owners.
fn decode_versions(value &serde_json.Value) !map[string]NpmPackageVersionInfo {
	keys := value.object_keys() or { return error('expected versions map') }
	mut versions := map[string]NpmPackageVersionInfo{}
	for index in 0 .. keys.len {
		key := &keys[index]
		entry := value.get(key)
		encoded := entry.value.to_string()
		versions[key.clone()] = NpmPackageVersionInfo.deserialize_json(&encoded)!
	}
	return versions
}

// STUB: the source nested serde struct defaults absent Option<Dist> to None.
pub fn NpmPackageVersionInfo.deserialize_json(source &string) !NpmPackageVersionInfo {
	fields := ['dist']
	input := serde_json.deserialize_struct(source, &fields)!
	mut dist := ?NpmPackageDist(none)
	mut seen := false
	if input.is_sequence {
		if input.sequence.len > 1 {
			return error('invalid NpmPackageVersionInfo sequence length')
		}
		if input.sequence.len == 1 && !input.sequence[0].is_null() {
			encoded := input.sequence[0].to_string()
			dist = NpmPackageDist.deserialize_json(&encoded)!
		}
	} else {
		for index in 0 .. input.fields.len {
			field := &input.fields[index]
			if seen {
				return error('duplicate field `dist`')
			}
			seen = true
			if !field.value.is_null() {
				encoded := field.value.to_string()
				dist = NpmPackageDist.deserialize_json(&encoded)!
			}
		}
	}
	return NpmPackageVersionInfo{ dist: dist }
}

// STUB: nullable dist strings use the source serde optional-field semantics.
pub fn NpmPackageDist.deserialize_json(source &string) !NpmPackageDist {
	fields := ['tarball', 'integrity']
	input := serde_json.deserialize_struct(source, &fields)!
	mut tarball := ?string(none)
	mut integrity := ?string(none)
	mut tarball_seen := false
	mut integrity_seen := false
	if input.is_sequence {
		if input.sequence.len > 2 {
			return error('invalid NpmPackageDist sequence length')
		}
		if input.sequence.len > 0 && !input.sequence[0].is_null() {
			tarball = input.sequence[0].string_owned()!
		}
		if input.sequence.len > 1 && !input.sequence[1].is_null() {
			integrity = input.sequence[1].string_owned()!
		}
	} else {
		for index in 0 .. input.fields.len {
			field := &input.fields[index]
			match field.name {
				'tarball' {
					if tarball_seen {
						return error('duplicate field `tarball`')
					}
					tarball_seen = true
					if !field.value.is_null() {
						tarball = field.value.string_owned()!
					}
				}
				'integrity' {
					if integrity_seen {
						return error('duplicate field `integrity`')
					}
					integrity_seen = true
					if !field.value.is_null() {
						integrity = field.value.string_owned()!
					}
				}
				else {}
			}
		}
	}
	return NpmPackageDist{ tarball: tarball, integrity: integrity }
}

// STUB: executable boundary for npm_registry::ensure_version_ready. This is
// only the source-observed registry-readiness API, not the full npm module.
pub fn ensure_version_ready(package_info &NpmPackageInfo, version &string) ! {
	trimmed := version.trim('\u0009\u000a\u000b\u000c\u000d\u0020\u0085\u00a0\u1680\u2000\u2001\u2002\u2003\u2004\u2005\u2006\u2007\u2008\u2009\u200a\u2028\u2029\u202f\u205f\u3000')
	if 'latest' !in package_info.dist_tags {
		return error('npm package is missing latest dist-tag')
	}
	// These verified entries are borrowed only while their shared map owner is
	// alive; neither map is mutated, so V's unsafe map-reference boundary is safe.
	latest := unsafe { &package_info.dist_tags['latest'] }
	if *latest != trimmed {
		return error('npm latest dist-tag points to ${*latest}, expected GitHub release ${trimmed}')
	}
	if trimmed !in package_info.versions {
		return error('npm package version ${trimmed} is missing')
	}
	info := unsafe { &package_info.versions[trimmed] }
	dist := info.dist or { return error('npm package version ${trimmed} is missing dist metadata') }
	if tarball := dist.tarball {
		if tarball.len == 0 {
			return error('npm package version ${trimmed} is missing dist.tarball')
		}
	} else {
		return error('npm package version ${trimmed} is missing dist.tarball')
	}
	if integrity := dist.integrity {
		if integrity.len == 0 {
			return error('npm package version ${trimmed} is missing dist.integrity')
		}
	} else {
		return error('npm package version ${trimmed} is missing dist.integrity')
	}
}
