// Extra image variants for this fork: PostgreSQL plus Citus and PostGIS.
//
// Kept apart from docker-bake.hcl so that file can stay as close to upstream
// as possible and absorb its changes without conflicts. Load both:
//   docker buildx bake -f docker-bake.hcl -f docker-bake.extra.hcl all

// Extensions to be included in the `extra` image
extraExtensions = [
  "citus",
  "postgis"
]

// Supported PostgreSQL major version range for each extra extension on
// specific distros. Use `min` and/or `max` to define bounds.
// Extensions or distros not listed are unconstrained.
extensionDistroConstraints = {
  "citus" = {
    "trixie" = { min = 16 }
  }
  "postgis" = {
    "bullseye" = { max = 17 }
  }
}

// Debian base images
// renovate: datasource=docker versioning=loose depName=debian
trixieImage = "debian:trixie-slim@sha256:d7e12182ce18b85b93007c1dedf31f2d29e01ccf3182cc4017c709b6259bc132"
// renovate: datasource=docker versioning=loose depName=debian
bookwormImage = "debian:bookworm-slim@sha256:88200866dfff7ea7f5cbcb6ec7c8a701889efe6fe859fe64d6990e4b07ea4171"
// renovate: datasource=docker versioning=loose depName=debian
bullseyeImage = "debian:bullseye-slim@sha256:e5b6442dd2e9684cf5e87d8338b5968f3b348636fc0be6d7850a381e3731a2bd"

group "all" {
  targets = ["default", "extra-targets"]
}

target "extra-targets" {
  dockerfile = "Dockerfile"
  context = "."
  output = [
    "type=image,oci-mediatypes=true,oci-artifact=true",
  ]
  attest = [
    "type=provenance,mode=max",
    "type=sbom"
  ]
  // Override platforms: exclude arm64 for extra target (Citus build issues on arm64)
  platforms = ["linux/amd64"]
  matrix = {
    tgt = ["extra"]
    // Only build majors covered by `extensionsVersionMap`: the extra
    // extensions have no packages yet for the newest (preview) majors.
    pgVersion = [
      for v in getPgVersions(postgreSQLVersions, postgreSQLPreviewVersions) : v
      if length([
        for ext in extraExtensions : ext
        if !contains(keys(extensionsVersionMap[ext]), getMajor(v))
      ]) == 0
    ]
    base = [
      trixieImage,
      bookwormImage,
      bullseyeImage
    ]
  }
  name = "postgresql-${index(split(".",cleanVersion(pgVersion)),0)}-${tgt}-${distroVersion(base)}"
  target = "${tgt}"
  tags = concat(
    [
      "${fullname}:${index(split(".",cleanVersion(pgVersion)),0)}-${tgt}-${distroVersion(base)}",
      "${fullname}:${cleanVersion(pgVersion)}-${tgt}-${distroVersion(base)}",
      "${fullname}:${cleanVersion(pgVersion)}-${formatdate("YYYYMMDDhhmm", now)}-${tgt}-${distroVersion(base)}",
    ],
    [
      for ext in getExtraExtensionsForDistro(pgVersion, base, extraExtensions) : "${fullname}:${cleanVersion(pgVersion)}-${getExtensionTag(ext, getMajor(pgVersion))}-${tgt}-${distroVersion(base)}"
    ],
    [
      "${fullname}:${cleanVersion(pgVersion)}-${getCombinedExtensionsTag(getExtraExtensionsForDistro(pgVersion, base, extraExtensions), getMajor(pgVersion))}-${tgt}-${distroVersion(base)}"
    ]
  )
  args = {
    PG_VERSION = "${pgVersion}"
    PG_MAJOR = "${getMajor(pgVersion)}"
    BASE = "${base}"
    EXTENSIONS = "${getExtensionsString(pgVersion, extensions)}"
    EXTRA_EXTENSIONS = "${getExtensionsString(pgVersion, getExtraExtensionsForDistro(pgVersion, base, extraExtensions))}"
    PRELOAD_LIBRARIES = "${join(",", concat(extensions, getExtraExtensionsForDistro(pgVersion, base, extraExtensions)))}"
    STANDARD_ADDITIONAL_POSTGRES_PACKAGES = "${getStandardAdditionalPostgresPackagesPerMajorVersion(getMajor(pgVersion))}"
    BARMAN_VERSION = "${barmanVersion}"
  }
  annotations = [
    "index,manifest:org.opencontainers.image.created=${now}",
    "index,manifest:org.opencontainers.image.url=${url}",
    "index,manifest:org.opencontainers.image.source=${url}",
    "index,manifest:org.opencontainers.image.version=${pgVersion}",
    "index,manifest:org.opencontainers.image.revision=${revision}",
    "index,manifest:org.opencontainers.image.vendor=${authors}",
    "index,manifest:org.opencontainers.image.title=CloudNativePG PostgreSQL ${pgVersion} ${tgt}",
    "index,manifest:org.opencontainers.image.description=A ${tgt} PostgreSQL ${pgVersion} container image",
    "index,manifest:org.opencontainers.image.documentation=${url}",
    "index,manifest:org.opencontainers.image.authors=${authors}",
    "index,manifest:org.opencontainers.image.licenses=Apache-2.0",
    "index,manifest:org.opencontainers.image.base.name=docker.io/library/debian:${tag(base)}",
    "index,manifest:org.opencontainers.image.base.digest=${digest(base)}"
  ]
  labels = {
    "org.opencontainers.image.created" = "${now}",
    "org.opencontainers.image.url" = "${url}",
    "org.opencontainers.image.source" = "${url}",
    "org.opencontainers.image.version" = "${pgVersion}",
    "org.opencontainers.image.revision" = "${revision}",
    "org.opencontainers.image.vendor" = "${authors}",
    "org.opencontainers.image.title" = "CloudNativePG PostgreSQL ${pgVersion} ${tgt}",
    "org.opencontainers.image.description" = "A ${tgt} PostgreSQL ${pgVersion} container image",
    "org.opencontainers.image.documentation" = "${url}",
    "org.opencontainers.image.authors" = "${authors}",
    "org.opencontainers.image.licenses" = "Apache-2.0"
    "org.opencontainers.image.base.name" = "docker.io/library/debian:${tag(base)}"
    "org.opencontainers.image.base.digest" = "${digest(base)}"
  }
}

function getExtraExtensionsForDistro {
    params = [pgVersion, base, extraExts]
    result = [
      for ext in extraExts : ext
      if !(
        contains(keys(extensionDistroConstraints), ext) &&
        contains(keys(extensionDistroConstraints[ext]), distroVersion(base)) &&
        (
          try(getMajor(pgVersion) < extensionDistroConstraints[ext][distroVersion(base)].min, false) ||
          try(getMajor(pgVersion) > extensionDistroConstraints[ext][distroVersion(base)].max, false)
        )
      )
    ]
}

function getExtensionTag {
    params = [ extension, majorVersion ]
    result = format("%s%s", extension, extensionsVersionMap[extension][majorVersion])
}

function getCombinedExtensionsTag {
    params = [ extensions, majorVersion ]
    result = join("-", [for ext in extensions : getExtensionTag(ext, majorVersion)])
}
