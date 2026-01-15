#!/usr/bin/env bash
# A test plugin that exits with an error
echo "about to fail" >&2
return 1
