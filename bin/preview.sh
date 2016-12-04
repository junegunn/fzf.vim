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

if [ -r /dev/tty ]; then
    LINES=$(stty size < /dev/tty | awk '{print $1}')
else
    LINES=40
fi

if [ -n "$SPLIT" ]; then
    LINES=$(($LINES/2)) # using horizontal split
fi
LINES=$(($LINES-2)) # remove preview border

FIRST=$(($CENTER-$LINES/3))
FIRST=$(($FIRST < 1 ? 1 : $FIRST))
LAST=$((${FIRST}+${LINES}-1))

awk "NR >= $FIRST && NR <= $LAST {if (NR == $CENTER) printf(\"\x1b[7m%5d %s\n\x1b[m\", NR, \$0); else printf(\"%5d %s\n\", NR, \$0)}" $FILE
