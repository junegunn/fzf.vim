#!/usr/bin/env bash

QUERY="$1"
shift
TAGSFILES="$@"

for t in ${TAGSFILES}; do
    readtags -t "${t}" -e -p - "${QUERY}"  | sed 's/kind://' |  sed "s,$,\t${t},"
done
