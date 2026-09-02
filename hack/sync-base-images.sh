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

changed=0
for distro in trixie bookworm bullseye; do
	image="$(grep -o "debian:${distro}-slim@sha256:[0-9a-f]\{64\}" "${main}" | head -1)"
	if [ -z "${image}" ]; then
		echo "error: no ${distro} base image found in ${main}" >&2
		exit 1
	fi

	current="$(grep -o "^${distro}Image = \"[^\"]*\"" "${extra}" | sed 's/.*"\(.*\)"/\1/')"
	if [ -z "${current}" ]; then
		echo "error: no ${distro}Image variable found in ${extra}" >&2
		exit 1
	fi

	if [ "${current}" != "${image}" ]; then
		sed -i "s|^${distro}Image = \".*\"|${distro}Image = \"${image}\"|" "${extra}"
		echo "${distro}: ${current} -> ${image}"
		changed=1
	fi
done

if [ "${changed}" -eq 0 ]; then
	echo "${extra} already matches ${main}"
fi
