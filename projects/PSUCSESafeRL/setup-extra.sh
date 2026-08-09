#!/usr/bin/env bash
# Called by bootstrap.sh (bash setup-extra.sh <venv_dir>) after requirements-extra.txt
# is installed. Handles the one step that isn't a plain pip install: this
# project's Readme.md notes the PyPI release of safety-gymnasium (v1.0.0) is
# outdated and v1.2.0 must be installed from source.
#
# Uses a plain (non-editable) `pip install .` rather than `-e .`: the clone
# lives in a scratch dir on ephemeral instance disk, which won't survive
# instance termination. An editable install would break next session since
# it keeps a path reference back to that clone; a regular install copies the
# built package into the venv itself, which does persist on the filesystem.
set -euo pipefail

venv_dir="$1"
pip="$venv_dir/bin/pip"

scratch="$(mktemp -d)"
trap 'rm -rf "$scratch"' EXIT

git clone --depth 1 https://github.com/PKU-Alignment/safety-gymnasium.git "$scratch/safety-gymnasium"
"$pip" install "$scratch/safety-gymnasium"
