#!/bin/sh
docker build --tag=dsu_ctf_wom .
docker run -it -p 1337:1337 --rm --name=dsu_ctf_wom dsu_ctf_wom
