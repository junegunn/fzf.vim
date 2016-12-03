#!/bin/bash

REVERSE="\x1b[7m"
RESET="\x1b[m"

if [ "$1" == "-v" ]; then
    SPLIT=1
    shift
fi

if [ -z "$1" ]; then
    echo "usage: $0 [-v] FILENAME[:LINENO][:IGNORED]"
    exit 1
fi

IFS=':' read -r -a INPUT <<< "$1"
FILE=${INPUT[0]}
CENTER=${INPUT[1]}

if [ ! -r "$FILE" ]; then
    echo "File not found ${FILE}"
    exit 1
fi

if [ -z "$CENTER" ]; then
    CENTER=1
fi

LINES=40
COLUMNS=80

if [ -r /dev/tty ]; then
    SIZE=$(stty size < /dev/tty)
    LINES=$(echo $SIZE | awk '{print $1}')
    COLUMNS=$(echo $SIZE | awk '{print $2}')
fi

LINES=$(($LINES-2)) # remove preview border
FIRST=$(($CENTER-$LINES/2))
FIRST=$(($FIRST < 1 ? 1 : $FIRST))
LAST=$((${FIRST}+${LINES}))

awk "NR >= $FIRST && NR <= $LAST {if (NR == $CENTER) printf(\"\x1b[7m%5d %s\n\x1b[m\", NR, \$0); else printf(\"%5d %s\n\", NR, \$0)}" $FILE | cut -c -60
