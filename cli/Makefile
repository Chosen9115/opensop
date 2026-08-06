# Makefile for opensop CLI maintenance tasks.
# There is no build step — bin/opensop is the binary.

# Regenerate bin/opensop.sha256 after editing bin/opensop.
# Run this before committing whenever bin/opensop changes.
# Format: "<digest>  opensop" (sha256sum / shasum two-field format).
# Both install.sh and cmd_upgrade use awk '{print $1}' to extract the digest,
# so this format is accepted by both verifiers.
.PHONY: checksum
checksum:
	@if command -v sha256sum >/dev/null 2>&1; then \
	  sha256sum bin/opensop | awk '{print $$1 "  opensop"}' > bin/opensop.sha256; \
	elif command -v shasum >/dev/null 2>&1; then \
	  shasum -a 256 bin/opensop | awk '{print $$1 "  opensop"}' > bin/opensop.sha256; \
	elif command -v openssl >/dev/null 2>&1; then \
	  openssl dgst -sha256 bin/opensop | awk '{print $$NF "  opensop"}' > bin/opensop.sha256; \
	else \
	  echo "error: no SHA-256 tool found (need sha256sum, shasum, or openssl)" >&2; exit 1; \
	fi
	@echo "wrote bin/opensop.sha256 — commit alongside bin/opensop"

# Run the syntax check + test suite (the only gate; there is no CI).
.PHONY: test
test:
	bash -n bin/opensop && bash test/test.sh
