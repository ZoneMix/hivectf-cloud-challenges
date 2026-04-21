#!/bin/bash

set -ex

NAME="the-enigma-of-annabelle"

docker rm -f "$NAME" >/dev/null 2>&1 || true
docker build --tag="$NAME" .
docker run -d -p 9999:9999 --rm --name="$NAME" "$NAME"