#!/bin/bash
set -euxo pipefail

if kubectl -n tink-system get workflow.tinkerbell.org t1 >/dev/null 2>&1; then
  kubectl -n tink-system delete workflow.tinkerbell.org t1
fi
if kubectl -n tink-system get hardware.tinkerbell.org t1 >/dev/null 2>&1; then
  kubectl -n tink-system delete hardware.tinkerbell.org t1
fi
if kubectl -n tink-system get templates.tinkerbell.org hello >/dev/null 2>&1; then
  kubectl -n tink-system delete templates.tinkerbell.org hello
fi
