#!/usr/bin/env bash

REVERSE="\x1b[7m"
RESET="\x1b[m"

if [ -z "$1" ]; then
  echo "usage: $0 FILENAME[:LINENO][:IGNORED]"
  exit 1
fi

IFS=':' read -r -a INPUT <<< "$1"
FILE=${INPUT[0]}
CENTER=${INPUT[1]}

if [[ $1 =~ ^[A-Z]:\\ ]]; then
  FILE=$FILE:${INPUT[1]}
  CENTER=${INPUT[2]}
fi

if [ ! -r "$FILE" ]; then
  echo "File not found ${FILE}"
  exit 1
fi

if [[ "$(file --dereference --mime "$FILE")" =~ binary ]]; then
  echo "$1 is a binary file"
  exit 0
fi

if [ -z "$CENTER" ]; then
  CENTER=0
fi

if [ -z "$LINES" ]; then
  if [ -r /dev/tty ]; then
    LINES=$(stty size < /dev/tty | awk '{print $1}')
  else
    LINES=40
  fi
fi

FIRST=$(($CENTER-$LINES/3))
FIRST=$(($FIRST < 1 ? 1 : $FIRST))
LAST=$((${FIRST}+${LINES}-1))

DEFAULT_COMMAND="bat --style=numbers --color=always {} || highlight -O ansi -l {} || coderay {} || rougify {} || cat {}"
CMD=${FZF_PREVIEW_COMMAND:-$DEFAULT_COMMAND}
CMD=${CMD//{\}/$(printf %q "$FILE")}

eval "$CMD" 2> /dev/null | awk "NR >= $FIRST && NR <= $LAST { \
    if (NR == $CENTER) \
        { gsub(/\x1b[[0-9;]*m/, \"&$REVERSE\"); printf(\"$REVERSE%s\n$RESET\", \$0); } \
    else printf(\"$RESET%s\n\", \$0); \
    }"
