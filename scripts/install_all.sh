#!/usr/bin/env bash

set -x
set -e

for ver in 2.7 3.5 3.6 3.7 pypy2.7 pypy3.6; do
    ./scripts/install.sh $ver
done
