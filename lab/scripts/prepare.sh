#!/bin/bash
set -Eeuo pipefail
source "$(dirname "$0")/common.sh"
lock_operation
prepare_runtime
