# Beryl's SHA-256 is written in Crystal and needs Crystal 1.21 or newer; on
# those compilers it is the default, so lock checksums and every other digest
# Minecart takes link no OpenSSL. Older compilers keep Crystal's
# `Digest::SHA256`, which calls OpenSSL. Both are `::Digest` subclasses and
# give the same bytes, so a lock written by either verifies with the other.
{% if flag?(:without_openssl) || compare_versions(Crystal::VERSION, "1.21.0") >= 0 %}
  require "./vendor/beryl/crypto"
{% else %}
  require "digest/sha256"
{% end %}

module Shards
  # The SHA-256 behind lock checksums (`sha256-v2:` and legacy `sha256:`),
  # AI docs and postinstall fingerprints, the change log and the vulnerability
  # cache keys.
  #
  # On Crystal 1.21 or newer (and with `-Dwithout_openssl`) it is the pinned
  # copy of Beryl under `src/vendor` (see `src/vendor/BERYL_VENDORED.json`).
  # On older compilers it is Crystal's `Digest::SHA256`.
  {% if flag?(:without_openssl) || compare_versions(Crystal::VERSION, "1.21.0") >= 0 %}
    alias SHA256Digest = Shards::Beryl::Crypto::V1::SHA256
  {% else %}
    alias SHA256Digest = ::Digest::SHA256
  {% end %}
end
