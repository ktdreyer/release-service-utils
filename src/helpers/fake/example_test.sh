#!/bin/bash
# Example: Testing publish_index_image with fake skopeo client
#
# This script demonstrates how to use the fake skopeo client
# in Tekton tests or integration tests.

set -euo pipefail

# Setup: Create a temporary mock config
MOCK_CONFIG=$(mktemp --suffix=.yaml)
trap "rm -f $MOCK_CONFIG" EXIT

cat > "$MOCK_CONFIG" <<'EOF'
# Mock configuration for testing successful publish

inspect:
  # Target image doesn't exist yet (returns error)
  - match:
      image: "docker://quay.io/target/image:tag"
      format: "{{.Digest}}"
    return: "sha256:different123"  # Different digest

copy:
  # Copy succeeds
  - match:
      source:
        regex: "docker://.*source.*@sha256:.*"
      destination: "docker://quay.io/target/image:tag"
    # No return = success
EOF

# Export the config path
export RELEASE_SERVICE_UTILS_FAKE_SKOPEO_SETUP="$MOCK_CONFIG"

# Create bash wrapper function for publish_index_image
publish_index_image() {
    # Get paths relative to this script
    local SCRIPT_DIR="$(dirname "$0")"
    local HELPERS_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
    local TASKS_DIR="$(cd "$SCRIPT_DIR/../../tasks/internal" && pwd)"

    python3 - "$@" <<EOF
import sys
import os

# Add directories to path
sys.path.insert(0, '$HELPERS_DIR')
sys.path.insert(0, '$TASKS_DIR')

# Patch BEFORE importing publish_index_image
from fake import patch_skopeo_client
patch_skopeo_client()

# Now import and run
from publish_index_image import main
sys.exit(main())
EOF
}

# Create temporary credential files
SRC_CRED=$(mktemp)
DEST_CRED=$(mktemp)
trap "rm -f $SRC_CRED $DEST_CRED $MOCK_CONFIG" EXIT

echo "user:pass" > "$SRC_CRED"
echo "user:pass" > "$DEST_CRED"

# Run the test!
echo "Running publish_index_image with fake skopeo client..."
echo

if publish_index_image \
    --source-index "quay.io/source/image@sha256:abc123def456" \
    --target-index "quay.io/target/image:tag" \
    --retries 3 \
    --source-credential-path "$SRC_CRED" \
    --target-credential-path "$DEST_CRED"; then
    echo
    echo "✓ Test passed: Image published successfully"
    exit 0
else
    echo
    echo "✗ Test failed"
    exit 1
fi
