#!/usr/bin/env bash
#
# Copy the Debian base images pinned in docker-bake.hcl over to the
# `<distro>Image` variables in docker-bake.extra.hcl.
#
# The extra targets cannot read the base images out of upstream's matrix --
# bake does not expose target.default.matrix -- so they keep their own copy.
# Renovate normally updates both in one grouped PR, but a merge from upstream
# carries a digest bump into docker-bake.hcl alone, leaving the two files out
# of step until this is run.

set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."

main="docker-bake.hcl"
extra="docker-bake.extra.hcl"

# The distributions are whatever docker-bake.hcl currently pins, so adding or
# retiring one upstream needs no change here.
mapfile -t images < <(grep -o 'debian:[a-z]\+-slim@sha256:[0-9a-f]\{64\}' "${main}" | sort -u)

if [ "${#images[@]}" -eq 0 ]; then
	echo "error: no Debian base images found in ${main}" >&2
	exit 1
fi

changed=0
for image in "${images[@]}"; do
	distro="${image#debian:}"
	distro="${distro%%-slim@*}"

	current="$(sed -n "s/^${distro}Image = \"\(.*\)\"$/\1/p" "${extra}")"
	if [ -z "${current}" ]; then
		echo "error: ${extra} has no ${distro}Image variable for ${image}" >&2
		exit 1
	fi

	if [ "${current}" != "${image}" ]; then
		sed -i "s|^${distro}Image = \".*\"|${distro}Image = \"${image}\"|" "${extra}"
		echo "${distro}: ${current} -> ${image}"
		changed=1
	fi
done

# Anything pinned only in the extra file would silently keep building on a
# stale base, so treat it as an error rather than leaving it behind.
mapfile -t orphans < <(
	grep -o '^[a-z]\+Image' "${extra}" | sed 's/Image$//' | sort -u |
		grep -vxF -f <(printf '%s\n' "${images[@]}" | sed 's/^debian:\([a-z]*\)-slim@.*/\1/' | sort -u) || true
)
if [ "${#orphans[@]}" -gt 0 ]; then
	echo "error: ${extra} pins ${orphans[*]}, which ${main} no longer builds" >&2
	exit 1
fi

if [ "${changed}" -eq 0 ]; then
	echo "${extra} already matches ${main} (${#images[@]} distributions)"
fi
