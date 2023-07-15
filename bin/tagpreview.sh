#!/usr/bin/env bash

REVERSE="\x1b[7m"
RESET="\x1b[m"

if [ -z "$1" ]; then
  echo "usage: $0 FILENAME:TAGFILE:EXCMD"
  exit 1
fi

IFS=':' read -r FILE TAGFILE EXCMD <<< "$*"

# Complete file paths which are relative to the given tag file
if [ "${FILE:0:1}" != "/" ]; then
  FILE="$(dirname "${TAGFILE}")/${FILE}"
fi

if [ ! -r "$FILE" ]; then
  echo "File not found ${FILE}"
  exit 1
fi

# If users aren't using vim, they are probably using neovim
if command -v vim > /dev/null; then
  VIMNAME="vim"
elif command -v nvim > /dev/null; then
  VIMNAME="nvim"
else
  echo "Cannot preview tag: vim or nvim unavailable"
  exit 1
fi

CENTER="$("${VIMNAME}" -R -i NONE -u NONE -e -m -s "${FILE}" \
              -c "set nomagic" \
              -c "${EXCMD}" \
              -c 'let l=line(".") | new | put =l | print | qa!')" || exit

START_LINE="$(( CENTER - FZF_PREVIEW_LINES / 2 ))"
if (( START_LINE <= 0 )); then
    START_LINE=1
fi
END_LINE="$(( START_LINE + FZF_PREVIEW_LINES - 1 ))"

# Sometimes bat is installed as batcat.
if command -v batcat > /dev/null; then
  BATNAME="batcat"
elif command -v bat > /dev/null; then
  BATNAME="bat"
fi

if [ -z "$FZF_PREVIEW_COMMAND" ] && [ "${BATNAME:+x}" ]; then
  ${BATNAME} --style="${BAT_STYLE:-numbers}" \
             --color=always \
             --pager=never \
             --wrap=never \
             --terminal-width="${FZF_PREVIEW_COLUMNS}" \
             --line-range="${START_LINE}:${END_LINE}" \
             --highlight-line="${CENTER}" \
             "$FILE"
  exit $?
fi

DEFAULT_COMMAND="highlight -O ansi -l {} || coderay {} || rougify {} || cat {}"
CMD=${FZF_PREVIEW_COMMAND:-$DEFAULT_COMMAND}
CMD=${CMD//{\}/$(printf %q "$FILE")}

eval "$CMD" 2> /dev/null | awk "{ \
    if (NR >= $START_LINE && NR <= $END_LINE) { \
        if (NR == $CENTER) \
            { gsub(/\x1b[[0-9;]*m/, \"&$REVERSE\"); printf(\"$REVERSE%s\n$RESET\", \$0); } \
        else printf(\"$RESET%s\n\", \$0); \
        } \
    }"
