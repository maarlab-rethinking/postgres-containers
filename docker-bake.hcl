variable "environment" {
  default = "testing"
  validation {
    condition = contains(["testing", "production"], environment)
    error_message = "environment must be either testing or production"
  }
}

variable "registry" {
  default = "localhost:5000"
}

// Use the revision variable to identify the commit that generated the image
variable "revision" {
  default = ""
}

fullname = ( environment == "testing") ? "${registry}/postgresql-testing" : "${registry}/postgresql"
now = timestamp()
authors = "The CloudNativePG Contributors"
url = "https://github.com/maarlab-rethinking/postgres-containers"

// PostgreSQL versions to build
postgreSQLVersions = [
  "14.20",
  "15.15",
  "16.11",
  "17.7",
  "18.1"
]

// PostgreSQL preview versions to build, such as "18~beta1" or "18~rc1"
// Preview versions are automatically filtered out if present in the stable list
// MANUALLY EDIT THE CONTENT - AND UPDATE THE README.md FILE TOO
postgreSQLPreviewVersions = [
]

// Extensions version mapping for each PostgreSQL major version
extensionsVersionMap = {
  "citus" = {
    "13" = "11.3"
    "14" = "12.1"
    "15" = "13.2"
    "16" = "13.2"
    "17" = "13.2"
    "18" = "13.2"
  },
  "postgis" = {
    "13" = "3"
    "14" = "3"
    "15" = "3"
    "16" = "3"
    "17" = "3"
    "18" = "3"
  }
}

// Barman version to build
// renovate: datasource=pypi versioning=loose depName=barman
barmanVersion = "3.16.2"

// Extensions to be included in the `standard` image
extensions = [
  "pgaudit",
  "pgvector",
  "pg-failover-slots"
]

// Extensions to be included in the `extra` image
extraExtensions = [
  "citus",
  "postgis"
]

// Debian base images
trixieImage = "debian:trixie-slim@sha256:a347fd7510ee31a84387619a492ad6c8eb0af2f2682b916ff3e643eb076f925a"
bookwormImage = "debian:bookworm-slim@sha256:936abff852736f951dab72d91a1b6337cf04217b2a77a5eaadc7c0f2f1ec1758"
bullseyeImage = "debian:bullseye-slim@sha256:75e0b7a6158b4cc911d4be07d9f6b8a65254eb8c58df14023c3da5c462335593"

group "default" {
  targets = ["standard-targets", "extra-targets"]
}

target "_common" {
  platforms = [
    "linux/amd64",
    "linux/arm64"
  ]
  dockerfile = "Dockerfile"
  context = "."
  attest = [
    "type=provenance,mode=max",
    "type=sbom"
  ]
}

target "standard-targets" {
  inherits = ["_common"]
  matrix = {
    tgt = ["minimal", "standard", "system"]
    pgVersion = getPgVersions(postgreSQLVersions, postgreSQLPreviewVersions)
    base = [
      // renovate: datasource=docker versioning=loose
      trixieImage,
      // renovate: datasource=docker versioning=loose
      bookwormImage,
      // renovate: datasource=docker versioning=loose
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
    (tgt == "system" && distroVersion(base) == "bullseye" && isPreview(pgVersion) == false) ? getRollingTags("${fullname}", pgVersion) : []
  )
  args = {
    PG_VERSION = "${pgVersion}"
    PG_MAJOR = "${getMajor(pgVersion)}"
    BASE = "${base}"
    EXTENSIONS = "${getExtensionsString(pgVersion, extensions)}"
    PRELOAD_LIBRARIES = "${join(",", extensions)}"
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

target "extra-targets" {
  inherits = ["_common"]
  // Override platforms: exclude arm64 for extra target (Citus build issues on arm64)
  platforms = ["linux/amd64"]
  matrix = {
    tgt = ["extra"]
    // Exclude PostgreSQL 18 for extra target (some extensions not yet available)
    pgVersion = [
      for v in getPgVersions(postgreSQLVersions, postgreSQLPreviewVersions) : v
      if getMajor(v) < "18"
    ]
    // Exclude trixie-slim for extra target (Citus doesn't support it yet)
    base = [
      // renovate: datasource=docker versioning=loose
      bookwormImage,
      // renovate: datasource=docker versioning=loose
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
      for ext in extraExtensions : "${fullname}:${cleanVersion(pgVersion)}-${getExtensionTag(ext, getMajor(pgVersion))}-${tgt}-${distroVersion(base)}"
    ],
    [
      "${fullname}:${cleanVersion(pgVersion)}-${getCombinedExtensionsTag(extraExtensions, getMajor(pgVersion))}-${tgt}-${distroVersion(base)}"
    ]
  )
  args = {
    PG_VERSION = "${pgVersion}"
    PG_MAJOR = "${getMajor(pgVersion)}"
    BASE = "${base}"
    EXTENSIONS = "${getExtensionsString(pgVersion, extensions)}"
    EXTRA_EXTENSIONS = "${getExtensionsString(pgVersion, extraExtensions)}"
    PRELOAD_LIBRARIES = "${join(",", concat(extensions, extraExtensions))}"
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

function tag {
  params = [ imageNameWithSha ]
  result = index(split("@", index(split(":", imageNameWithSha), 1)), 0)
}

function distroVersion {
  params = [ imageNameWithSha ]
  result = index(split("-", tag(imageNameWithSha)), 0)
}

function digest {
  params = [ imageNameWithSha ]
  result = index(split("@", imageNameWithSha), 1)
}

function cleanVersion {
    params = [ version ]
    result = replace(version, "~", "")
}

function isPreview {
    params = [ version ]
    result = length(regexall("[0-9]+~(alpha|beta|rc).*", version)) > 0
}

function getMajor {
    params = [ version ]
    result = (isPreview(version) == true) ? index(split("~", version),0) : index(split(".", version),0)
}

function getExtensionsString {
    params = [ version, extensions ]
    result = isPreview(version) ? "" : join(" ", [
      for ext in extensions : format("postgresql-%s-%s%s", getMajor(version), ext, try("-${extensionsVersionMap[ext][getMajor(version)]}", ""))
    ])
}

// This function conditionally adds recommended PostgreSQL packages based on
// the version. For example, starting with version 18, PGDG moved `jit` out of
// the main package and into a separate one.
function getStandardAdditionalPostgresPackagesPerMajorVersion {
    params = [ majorVersion ]
    // Add PostgreSQL jit package from version 18
    result = join(" ", [
      majorVersion < 18 ? "" : format("postgresql-%s-jit", majorVersion)
    ])
}

function isMajorPresent {
  params = [major, pgVersions]
  result = contains([for v in pgVersions : getMajor(v)], major)
}

function getPgVersions {
  params = [stableVersions, previewVersions]
  // Remove any preview version if already present as stable
  result = concat(stableVersions,
    [
      for v in previewVersions : v
      if !isMajorPresent(getMajor(v), stableVersions)
    ]
  )
}

function getRollingTags {
    params = [ imageName, pgVersion ]
    result = [
      format("%s:%s", imageName, pgVersion),
      format("%s:%s", imageName, getMajor(pgVersion))
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
