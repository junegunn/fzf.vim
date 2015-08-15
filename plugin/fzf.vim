" Copyright (c) 2015 Junegunn Choi
"
" MIT License
"
" Permission is hereby granted, free of charge, to any person obtaining
" a copy of this software and associated documentation files (the
" "Software"), to deal in the Software without restriction, including
" without limitation the rights to use, copy, modify, merge, publish,
" distribute, sublicense, and/or sell copies of the Software, and to
" permit persons to whom the Software is furnished to do so, subject to
" the following conditions:
"
" The above copyright notice and this permission notice shall be
" included in all copies or substantial portions of the Software.
"
" THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
" EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
" MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
" NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE
" LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION
" OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION
" WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

let s:cpo_save = &cpo
set cpo&vim

" ------------------------------------------------------------------
" Common
" ------------------------------------------------------------------
function! s:strip(str)
  return substitute(a:str, '^\s*\|\s*$', '', 'g')
endfunction

function! s:escape(path)
  return escape(a:path, ' %#\')
endfunction

function! s:ansi(str, col, bold)
  return printf("\x1b[%s%sm%s\x1b[m", a:col, a:bold ? ';1' : '', a:str)
endfunction

for [s:c, s:a] in items({'red': 31, 'green': 32, 'yellow': 33, 'blue': 34, 'magenta': 35})
  execute "function! s:".s:c."(str, ...)\n"
        \ "  return s:ansi(a:str, ".s:a.", get(a:, 1, 0))\n"
        \ "endfunction"
endfor

function! s:buflisted()
  return filter(range(1, bufnr('$')), 'buflisted(v:val)')
endfunction

function! s:fzf(opts, bang)
  return fzf#run(extend(a:opts, a:bang ? {} : get(g:, 'fzf_window', {'down': '40%'})))
endfunction

let s:default_action = {
  \ 'ctrl-t': 'tab split',
  \ 'ctrl-x': 'split',
  \ 'ctrl-v': 'vsplit' }

function! s:expect()
  return ' --expect='.join(keys(get(g:, 'fzf_action', s:default_action)), ',')
endfunction

function! s:common_sink(lines) abort
  if len(a:lines) < 2
    return
  endif
  let key = remove(a:lines, 0)
  let cmd = get(get(g:, 'fzf_action', s:default_action), key, 'e')
  try
    let autochdir = &autochdir
    set noautochdir
    for item in a:lines
      execute 'silent' cmd s:escape(item)
    endfor
  finally
    let &autochdir = autochdir
  endtry
endfunction

function! s:align_lists(lists)
  let maxes = {}
  for list in a:lists
    let i = 0
    while i < len(list)
      let maxes[i] = max([get(maxes, i, 0), len(list[i])])
      let i += 1
    endwhile
  endfor
  for list in a:lists
    call map(list, "printf('%-'.maxes[v:key].'s', v:val)")
  endfor
  return a:lists
endfunction

" ------------------------------------------------------------------
" Lines
" ------------------------------------------------------------------
function! s:line_handler(lines)
  if len(a:lines) < 2
    return
  endif
  let cmd = get(get(g:, 'fzf_action', s:default_action), a:lines[0], '')
  if !empty(cmd)
    execute 'silent' cmd
  endif

  let keys = split(a:lines[1], '\t')
  execute 'buffer' keys[0][1:-2]
  execute keys[1][0:-2]
  normal! ^zz
endfunction

function! s:buffer_lines()
  let res = []
  for b in s:buflisted()
    call extend(res,
    \ map(getbufline(b, 0, "$"),
    \ 'printf("[%s]\t%s:\t%s", s:blue(b, 1), s:yellow(v:key + 1, 1), v:val)'))
  endfor
  return res
endfunction

command! -bang Lines call s:fzf({
\ 'source':  <sid>buffer_lines(),
\ 'sink*':   function('<sid>line_handler'),
\ 'options': '+m --prompt "Lines> " --ansi --extended --nth=3..'.s:expect()
\}, <bang>0)

" ------------------------------------------------------------------
" Colors
" ------------------------------------------------------------------
command! -bang Colors call s:fzf({
\ 'source':  map(split(globpath(&rtp, "colors/*.vim"), "\n"),
\               "substitute(fnamemodify(v:val, ':t'), '\\..\\{-}$', '', '')"),
\ 'sink':    'colo',
\ 'options': '+m --prompt="Colors> "'
\}, <bang>0)

" ------------------------------------------------------------------
" Locate
" ------------------------------------------------------------------
command! -bang -nargs=1 Locate call s:fzf({
\ 'source':  'locate <q-args>',
\ 'sink*':   function('<sid>common_sink'),
\ 'options': '-m --prompt "Locate> "' . s:expect()
\}, <bang>0)

" ------------------------------------------------------------------
" History
" ------------------------------------------------------------------
function! s:all_files()
  return extend(
  \ filter(reverse(copy(v:oldfiles)),
  \        "v:val !~ 'fugitive:\\|NERD_tree\\|^/tmp/\\|.git/'"),
  \ filter(map(s:buflisted(), 'bufname(v:val)'), '!empty(v:val)'))
endfunction

command! -bang History call s:fzf({
\ 'source':  reverse(s:all_files()),
\ 'sink*':   function('<sid>common_sink'),
\ 'options': '--prompt "Hist> " -m' . s:expect(),
\}, <bang>0)

" ------------------------------------------------------------------
" Buffers
" ------------------------------------------------------------------
function! s:bufopen(lines)
  if len(a:lines) < 2
    return
  endif
  let cmd = get(get(g:, 'fzf_action', s:default_action), a:lines[0], '')
  if !empty(cmd)
    execute 'silent' cmd
  endif
  execute 'buffer' matchstr(a:lines[1], '\[\zs[0-9]*\ze\]')
endfunction

function! s:format_buffer(b)
  let name = bufname(a:b)
  let flag = a:b == bufnr('')  ? s:blue('%') :
          \ (a:b == bufnr('#') ? s:magenta('#') : ' ')
  let modified = getbufvar(a:b, '&modified') ? s:red(' [+]') : ''
  let readonly = getbufvar(a:b, '&modifiable') ? '' : s:green(' [RO]')
  let extra = join(filter([modified, readonly], '!empty(v:val)'), '')
  return s:strip(printf("[%s] %s\t%s\t%s", s:yellow(a:b, 1), flag, name, extra))
endfunction

function! s:bufselect(bang)
  let bufs = map(s:buflisted(), 's:format_buffer(v:val)')
  let height = min([len(bufs), &lines * 4 / 10])

  call fzf#run(extend({
  \ 'source':  reverse(bufs),
  \ 'sink*':   function('s:bufopen'),
  \ 'options': '+m --ansi -d "\t" -n 2,1..2 --prompt="Buf> "'.s:expect(),
  \}, a:bang ? {} : {'down': height + 2}))
endfunction

command! -bang Buffers call s:bufselect(<bang>0)

" ------------------------------------------------------------------
" Ag
" ------------------------------------------------------------------
function! s:ag_to_qf(line)
  let parts = split(a:line, ':')
  return {'filename': parts[0], 'lnum': parts[1], 'col': parts[2],
        \ 'text': join(parts[3:], ':')}
endfunction

function! s:ag_handler(lines)
  if len(a:lines) < 2
    return
  endif

  let cmd = get(get(g:, 'fzf_action', s:default_action), a:lines[0], 'e')
  let list = map(a:lines[1:], 's:ag_to_qf(v:val)')

  let first = list[0]
  execute cmd s:escape(first.filename)
  execute first.lnum
  execute 'normal!' first.col.'|zz'

  if len(list) > 1
    call setqflist(list)
    copen
    wincmd p
  endif
endfunction

command! -bang -nargs=* Ag call s:fzf({
\ 'source':  printf('ag --nogroup --column --color "%s"',
\                   escape(empty(<q-args>) ? '^(?=.)' : <q-args>, '"\')),
\ 'sink*':    function('<sid>ag_handler'),
\ 'options': '--ansi --delimiter : --nth 4.. --prompt "Ag> " '.
\            '--multi --bind ctrl-a:select-all,ctrl-d:deselect-all '.
\            '--color hl:68,hl+:110'.s:expect()}, <bang>0)

" ------------------------------------------------------------------
" BTags
" ------------------------------------------------------------------
function! s:btags_source()
  let lines = map(split(system(printf(
    \ 'ctags -f - --sort=no --excmd=number --language-force=%s %s',
    \ &filetype, expand('%:S'))), "\n"), 'split(v:val, "\t")')
  if v:shell_error
    throw 'failed to extract tags'
  endif
  return map(s:align_lists(lines), 'join(v:val, "\t")')
endfunction

function! s:btags_sink(lines)
  if len(a:lines) < 2
    return
  endif
  let cmd = get(get(g:, 'fzf_action', s:default_action), a:lines[0], '')
  if !empty(cmd)
    execute 'silent' cmd '%'
  endif
  execute split(a:lines[1], "\t")[2]
endfunction

function! s:btags(bang)
  try
    call s:fzf({
    \ 'source':  s:btags_source(),
    \ 'options': '+m -d "\t" --with-nth 1,4.. -n 1 --prompt "BTags> "'.s:expect(),
    \ 'sink*':   function('s:btags_sink')}, a:bang)
  catch
    echohl WarningMsg
    echom v:exception
    echohl None
  endtry
endfunction

command! -bang BTags call s:btags(<bang>0)

" ------------------------------------------------------------------
" Tags
" ------------------------------------------------------------------
function! s:tags_sink(lines)
  if len(a:lines) < 2
    return
  endif
  let cmd = get(get(g:, 'fzf_action', s:default_action), a:lines[0], 'e')
  let parts = split(a:lines[1], '\t\zs')
  let excmd = matchstr(parts[2:], '^.*\ze;"\t')
  execute 'silent' cmd s:escape(parts[1][:-2])
  let [magic, &magic] = [&magic, 0]
  execute excmd
  let &magic = magic
endfunction

function! s:tags(bang)
  if empty(tagfiles())
    echohl WarningMsg
    echom 'Preparing tags'
    echohl None
    call system('ctags -R')
  endif

  call s:fzf({
  \ 'source':  'cat '.join(map(tagfiles(), 'fnamemodify(v:val, ":S")')).
  \            '| grep -v "^!"',
  \ 'options': '+m -d "\t" --with-nth 1,4.. -n 1 --prompt "Tags> "'.s:expect(),
  \ 'sink*':   function('s:tags_sink')}, a:bang)
endfunction

command! -bang Tags call s:tags(<bang>0)

" ------------------------------------------------------------------
let &cpo = s:cpo_save
unlet s:cpo_save

