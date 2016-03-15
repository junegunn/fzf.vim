" Copyright (c) 2016 Junegunn Choi
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
function! fzf#vim#wrap(opts)
  return extend(copy(a:opts), {
  \ 'options': get(a:opts, 'options', '').' --expect='.join(keys(get(g:, 'fzf_action', s:default_action)), ','),
  \ 'sink*':   get(a:opts, 'sink*', s:function('s:common_sink'))})
endfunction

function! s:strip(str)
  return substitute(a:str, '^\s*\|\s*$', '', 'g')
endfunction

function! s:chomp(str)
  return substitute(a:str, '\n*$', '', 'g')
endfunction

function! s:escape(path)
  return escape(a:path, ' %#''"\')
endfunction

if v:version >= 704
  function! s:function(name)
    return function(a:name)
  endfunction
else
  function! s:function(name)
    " By Ingo Karkat
    return function(substitute(a:name, '^s:', matchstr(expand('<sfile>'), '<SNR>\d\+_\zefunction$'), ''))
  endfunction
endif

function! s:ansi(str, col, bold)
  return printf("\x1b[%s%sm%s\x1b[m", a:col, a:bold ? ';1' : '', a:str)
endfunction

for [s:c, s:a] in items({'black': 30, 'red': 31, 'green': 32, 'yellow': 33, 'blue': 34, 'magenta': 35, 'cyan': 36})
  execute "function! s:".s:c."(str, ...)\n"
        \ "  return s:ansi(a:str, ".s:a.", get(a:, 1, 0))\n"
        \ "endfunction"
endfor

function! s:buflisted()
  return filter(range(1, bufnr('$')), 'buflisted(v:val)')
endfunction

function! s:fzf(opts, extra)
  let extra  = copy(get(a:extra, 0, {}))
  let eopts  = has_key(extra, 'options') ? remove(extra, 'options') : ''
  let merged = extend(copy(a:opts), extra)
  let merged.options = join(filter([get(merged, 'options', ''), eopts], '!empty(v:val)'))
  call fzf#run(merged)
  return 1
endfunction

let s:default_action = {
  \ 'ctrl-t': 'tab split',
  \ 'ctrl-x': 'split',
  \ 'ctrl-v': 'vsplit' }

function! s:common_sink(lines) abort
  if len(a:lines) < 2
    return
  endif
  let key = remove(a:lines, 0)
  let cmd = get(get(g:, 'fzf_action', s:default_action), key, 'e')
  if len(a:lines) > 1
    augroup fzf_swap
      autocmd SwapExists * let v:swapchoice='o'
            \| call s:warn('fzf: E325: swap file exists: '.expand('<afile>'))
    augroup END
  endif
  try
    let empty = empty(expand('%')) && line('$') == 1 && empty(getline(1)) && !&modified
    let autochdir = &autochdir
    set noautochdir
    for item in a:lines
      if empty
        execute 'e' s:escape(item)
        let empty = 0
      else
        execute cmd s:escape(item)
      endif
      if exists('#BufEnter') && isdirectory(item)
        doautocmd BufEnter
      endif
    endfor
  finally
    let &autochdir = autochdir
    silent! autocmd! fzf_swap
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

function! s:warn(message)
  echohl WarningMsg
  echom a:message
  echohl None
  return 0
endfunction

function! s:uniq(list)
  let visited = {}
  let ret = []
  for l in a:list
    if !empty(l) && !has_key(visited, l)
      call add(ret, l)
      let visited[l] = 1
    endif
  endfor
  return ret
endfunction

" ------------------------------------------------------------------
" Files
" ------------------------------------------------------------------
function! fzf#vim#files(dir, ...)
  let args = {'options': '-m'}
  if !empty(a:dir)
    if !isdirectory(expand(a:dir))
      return s:warn('Invalid directory')
    endif
    let dir = substitute(a:dir, '/*$', '/', '')
    let args.dir = dir
    let args.options .= ' --prompt '.shellescape(dir)
  else
    let args.options .= ' --prompt '.shellescape(pathshorten(getcwd())).'/'
  endif

  return s:fzf(fzf#vim#wrap(args), a:000)
endfunction

" ------------------------------------------------------------------
" Lines
" ------------------------------------------------------------------
function! s:line_handler(lines)
  if len(a:lines) < 2
    return
  endif
  normal! m'
  let cmd = get(get(g:, 'fzf_action', s:default_action), a:lines[0], '')
  if !empty(cmd)
    execute 'silent' cmd
  endif

  let keys = split(a:lines[1], '\t')
  execute 'buffer' keys[0][1:-2]
  execute keys[1][0:-2]
  normal! ^zz
endfunction

function! fzf#vim#_lines(all)
  let cur = []
  let rest = []
  let buf = bufnr('')
  for b in s:buflisted()
    let lines = getbufline(b, 1, "$")
    if empty(lines)
      let path = fnamemodify(bufname(b), ':p')
      let lines = filereadable(path) ? readfile(path) : []
    endif
    call extend(b == buf ? cur : rest,
    \ filter(
    \   map(lines,
    \       '(!a:all && empty(v:val)) ? "" : printf("[%s]\t%s:\t%s", s:blue(b), s:yellow(v:key + 1), v:val)'),
    \   'a:all || !empty(v:val)'))
  endfor
  return extend(cur, rest)
endfunction

function! fzf#vim#lines(...)
  return s:fzf(fzf#vim#wrap({
  \ 'source':  fzf#vim#_lines(1),
  \ 'sink*':   s:function('s:line_handler'),
  \ 'options': '+m --tiebreak=index --prompt "Lines> " --ansi --extended --nth=3.. --reverse --tabstop='.&tabstop
  \}), a:000)
endfunction

" ------------------------------------------------------------------
" BLines
" ------------------------------------------------------------------
function! s:buffer_line_handler(lines)
  if len(a:lines) < 2
    return
  endif
  normal! m'
  let cmd = get(get(g:, 'fzf_action', s:default_action), a:lines[0], '')
  if !empty(cmd)
    execute 'silent' cmd
  endif

  execute split(a:lines[1], '\t')[0][0:-2]
  normal! ^zz
endfunction

function! s:buffer_lines()
  return map(getline(1, "$"),
    \ 'printf("%s:\t%s", s:yellow(v:key + 1), v:val)')
endfunction

function! fzf#vim#buffer_lines(...)
  return s:fzf(fzf#vim#wrap({
  \ 'source':  s:buffer_lines(),
  \ 'sink*':   s:function('s:buffer_line_handler'),
  \ 'options': '+m --tiebreak=index --prompt "BLines> " --ansi --extended --nth=2.. --reverse --tabstop='.&tabstop
  \}), a:000)
endfunction

" ------------------------------------------------------------------
" Colors
" ------------------------------------------------------------------
function! fzf#vim#colors(...)
  return s:fzf({
  \ 'source':  map(split(globpath(&rtp, "colors/*.vim"), "\n"),
  \               "substitute(fnamemodify(v:val, ':t'), '\\..\\{-}$', '', '')"),
  \ 'sink':    'colo',
  \ 'options': '+m --prompt="Colors> "'
  \}, a:000)
endfunction

" ------------------------------------------------------------------
" Locate
" ------------------------------------------------------------------
function! fzf#vim#locate(query, ...)
  return s:fzf(fzf#vim#wrap({
  \ 'source':  'locate '.a:query,
  \ 'options': '-m --prompt "Locate> "'
  \}), a:000)
endfunction

" ------------------------------------------------------------------
" History[:/]
" ------------------------------------------------------------------
function! s:all_files()
  return extend(
  \ filter(reverse(copy(v:oldfiles)),
  \        "v:val !~ 'fugitive:\\|__Tagbar__\\|NERD_tree\\|^/tmp/\\|\\.git/'"),
  \ filter(map(s:buflisted(), 'bufname(v:val)'), '!empty(v:val)'))
endfunction

function! s:history_source(type)
  let max  = histnr(a:type)
  let fmt  = '%'.len(string(max)).'d'
  let list = filter(map(range(1, max), 'histget(a:type, - v:val)'), '!empty(v:val)')
  return extend([' :: Press '.s:magenta('CTRL-E').' to edit'],
    \ map(list, 's:yellow(printf(fmt, len(list) - v:key)).": ".v:val'))
endfunction

nnoremap <plug>(-fzf-vim-do) :execute g:__fzf_command<cr>

function! s:history_sink(type, lines)
  if len(a:lines) < 2
    return
  endif

  let key  = a:lines[0]
  let item = matchstr(a:lines[1], ': \zs.*')
  if key == 'ctrl-e'
    call histadd(a:type, item)
    call feedkeys(a:type."\<up>")
  else
    let g:__fzf_command = "normal ".a:type.item."\<cr>"
    call feedkeys("\<plug>(-fzf-vim-do)")
  endif
endfunction

function! s:cmd_history_sink(lines)
  call s:history_sink(':', a:lines)
endfunction

function! fzf#vim#command_history(...)
  return s:fzf({
  \ 'source':  s:history_source(':'),
  \ 'sink*':   s:function('s:cmd_history_sink'),
  \ 'options': '+m --ansi --prompt="Hist:> " --header-lines=1 --expect=ctrl-e --tiebreak=index'}, a:000)
endfunction

function! s:search_history_sink(lines)
  call s:history_sink('/', a:lines)
endfunction

function! fzf#vim#search_history(...)
  return s:fzf({
  \ 'source':  s:history_source('/'),
  \ 'sink*':   s:function('s:search_history_sink'),
  \ 'options': '+m --ansi --prompt="Hist/> " --header-lines=1 --expect=ctrl-e --tiebreak=index'}, a:000)
endfunction

function! fzf#vim#history(...)
  return s:fzf(fzf#vim#wrap({
  \ 'source':  reverse(s:all_files()),
  \ 'options': '-m --prompt "Hist> "'
  \}), a:000)
endfunction

" ------------------------------------------------------------------
" GitFiles
" ------------------------------------------------------------------

function! fzf#vim#gitfiles(...)
  let root = systemlist('git rev-parse --show-toplevel')[0]
  if v:shell_error
    return s:warn('Not in git repo')
  endif
  return s:fzf(fzf#vim#wrap({
  \ 'source':  'git ls-tree --name-only -r HEAD',
  \ 'dir':     root,
  \ 'options': '-m --prompt "GitFiles> "'
  \}), a:000)
endfunction

" ------------------------------------------------------------------
" Buffers
" ------------------------------------------------------------------
function! s:find_open_window(b)
  let [tcur, tcnt] = [tabpagenr() - 1, tabpagenr('$')]
  for toff in range(0, tabpagenr('$') - 1)
    let t = (tcur + toff) % tcnt + 1
    let buffers = tabpagebuflist(t)
    for w in range(1, len(buffers))
      let b = buffers[w - 1]
      if b == a:b
        return [t, w]
      endif
    endfor
  endfor
  return [0, 0]
endfunction

function! s:jump(t, w)
  execute 'normal!' a:t.'gt'
  execute a:w.'wincmd w'
endfunction

function! s:bufopen(lines)
  if len(a:lines) < 2
    return
  endif
  let b = matchstr(a:lines[1], '\[\zs[0-9]*\ze\]')
  if empty(a:lines[0]) && get(g:, 'fzf_buffers_jump')
    let [t, w] = s:find_open_window(b)
    if t
      call s:jump(t, w)
      return
    endif
  endif
  let cmd = get(get(g:, 'fzf_action', s:default_action), a:lines[0], '')
  if !empty(cmd)
    execute 'silent' cmd
  endif
  execute 'buffer' b
endfunction

function! s:format_buffer(b)
  let name = bufname(a:b)
  let name = empty(name) ? '[No Name]' : name
  let flag = a:b == bufnr('')  ? s:blue('%') :
          \ (a:b == bufnr('#') ? s:magenta('#') : ' ')
  let modified = getbufvar(a:b, '&modified') ? s:red(' [+]') : ''
  let readonly = getbufvar(a:b, '&modifiable') ? '' : s:green(' [RO]')
  let extra = join(filter([modified, readonly], '!empty(v:val)'), '')
  return s:strip(printf("[%s] %s\t%s\t%s", s:yellow(a:b), flag, name, extra))
endfunction

function! s:sort_buffers(...)
  let [b1, b2] = map(copy(a:000), 'get(g:fzf#vim#buffers, v:val, v:val)')
  return b1 - b2
endfunction

function! fzf#vim#buffers(...)
  let bufs = map(sort(s:buflisted(), 's:sort_buffers'), 's:format_buffer(v:val)')
  return s:fzf(fzf#vim#wrap({
  \ 'source':  reverse(bufs),
  \ 'sink*':   s:function('s:bufopen'),
  \ 'options': '+m -x --tiebreak=index --ansi -d "\t" -n 2,1..2 --prompt="Buf> "',
  \}), a:000)
endfunction

" ------------------------------------------------------------------
" Ag
" ------------------------------------------------------------------
function! s:ag_to_qf(line)
  let parts = split(a:line, ':')
  return {'filename': &acd ? fnamemodify(parts[0], ':p') : parts[0], 'lnum': parts[1], 'col': parts[2],
        \ 'text': join(parts[3:], ':')}
endfunction

function! s:ag_handler(lines)
  if len(a:lines) < 2
    return
  endif

  let cmd = get(get(g:, 'fzf_action', s:default_action), a:lines[0], 'e')
  let list = map(a:lines[1:], 's:ag_to_qf(v:val)')

  let first = list[0]
  try
    execute cmd s:escape(first.filename)
    execute first.lnum
    execute 'normal!' first.col.'|zz'
  catch
  endtry

  if len(list) > 1
    call setqflist(list)
    copen
    wincmd p
  endif
endfunction

" query, [[ag options], options]
function! fzf#vim#ag(query, ...)
  let args = copy(a:000)
  let ag_opts = len(args) > 1 ? remove(args, 0) : ''
  return s:fzf(fzf#vim#wrap({
  \ 'source':  printf('ag --nogroup --column --color %s "%s"',
  \                   ag_opts,
  \                   escape(empty(a:query) ? '^(?=.)' : a:query, '"\-')),
  \ 'sink*':    s:function('s:ag_handler'),
  \ 'options': '--ansi --delimiter : --nth 4..,.. --prompt "Ag> " '.
  \            '--multi --bind alt-a:select-all,alt-d:deselect-all '.
  \            '--color hl:68,hl+:110'}), args)
endfunction

" ------------------------------------------------------------------
" BTags
" ------------------------------------------------------------------
function! s:btags_source(tag_cmds)
  if !filereadable(expand('%'))
    throw 'Save the file first'
  endif

  for cmd in a:tag_cmds
    let lines = split(system(cmd), "\n")
    if !v:shell_error
      break
    endif
  endfor
  if v:shell_error
    throw get(lines, 0, 'Failed to extract tags')
  elseif empty(lines)
    throw 'No tags found'
  endif
  return map(s:align_lists(map(lines, 'split(v:val, "\t")')), 'join(v:val, "\t")')
endfunction

function! s:btags_sink(lines)
  if len(a:lines) < 2
    return
  endif
  normal! m'
  let cmd = get(get(g:, 'fzf_action', s:default_action), a:lines[0], '')
  if !empty(cmd)
    execute 'silent' cmd '%'
  endif
  let qfl = []
  for line in a:lines[1:]
    execute split(line, "\t")[2]
    call add(qfl, {'filename': expand('%'), 'lnum': line('.'), 'text': getline('.')})
  endfor
  if len(qfl) > 1
    call setqflist(qfl)
    copen
    wincmd p
    cfirst
  endif
  normal! zz
endfunction

function! s:q(query)
  return ' --query "'.escape(a:query, '"').'"'
endfunction

" query, [[tag commands], options]
function! fzf#vim#buffer_tags(query, ...)
  let args = copy(a:000)
  let tag_cmds = len(args) > 1 ? remove(args, 0) : [
    \ printf('ctags -f - --sort=no --excmd=number --language-force=%s %s', &filetype, expand('%:S')),
    \ printf('ctags -f - --sort=no --excmd=number %s', expand('%:S'))]
  try
    return s:fzf(fzf#vim#wrap({
    \ 'source':  s:btags_source(tag_cmds),
    \ 'sink*':   s:function('s:btags_sink'),
    \ 'options': '--reverse -m -d "\t" --with-nth 1,4.. -n 1 --prompt "BTags> "'.s:q(a:query)}), args)
  catch
    return s:warn(v:exception)
  endtry
endfunction

" ------------------------------------------------------------------
" Tags
" ------------------------------------------------------------------
function! s:tags_sink(lines)
  if len(a:lines) < 2
    return
  endif
  normal! m'
  let qfl = []
  let cmd = get(get(g:, 'fzf_action', s:default_action), a:lines[0], 'e')
  let [magic, &magic] = [&magic, 0]
  for line in a:lines[1:]
    let parts = split(line, '\t\zs')
    let excmd = matchstr(join(parts[2:], ''), '^.*\ze;"\t')
    execute cmd s:escape(parts[1][:-2])
    execute excmd
    call add(qfl, {'filename': expand('%'), 'lnum': line('.'), 'text': getline('.')})
  endfor
  let &magic = magic
  if len(qfl) > 1
    call setqflist(qfl)
    copen
    wincmd p
    clast
  endif
  normal! zz
endfunction

function! fzf#vim#tags(query, ...)
  if empty(tagfiles())
    call s:warn('Preparing tags')
    call system('ctags -R')
    if empty(tagfiles())
      return s:warn('Failed to create tags')
    endif
  endif

  let tagfile = tagfiles()[0]
  " We don't want to apply --ansi option when tags file is large as it makes
  " processing much slower.
  if getfsize(tagfile) > 1024 * 1024 * 20
    let proc = 'grep -v ''^\!'' '
    let copt = ''
  else
    let proc = 'perl -ne ''unless (/^\!/) { s/^(.*?)\t(.*?)\t/\x1b[33m\1\x1b[m\t\x1b[34m\2\x1b[m\t/; print }'' '
    let copt = '--ansi '
  endif
  return s:fzf(fzf#vim#wrap({
  \ 'source':  proc.shellescape(fnamemodify(tagfile, ':t')),
  \ 'sink*':   s:function('s:tags_sink'),
  \ 'dir':     fnamemodify(tagfile, ':h'),
  \ 'options': copt.'-m --tiebreak=begin --prompt "Tags> "'.s:q(a:query)}), a:000)
endfunction

" ------------------------------------------------------------------
" Snippets (UltiSnips)
" ------------------------------------------------------------------
function! s:inject_snippet(line)
  let snip = split(a:line, "\t")[0]
  execute 'normal! a'.s:strip(snip)."\<c-r>=UltiSnips#ExpandSnippet()\<cr>"
endfunction

function! fzf#vim#snippets(...)
  if !exists(':UltiSnipsEdit')
    return s:warn('UltiSnips not found')
  endif
  let list = UltiSnips#SnippetsInCurrentScope()
  if empty(list)
    return s:warn('No snippets available here')
  endif
  let aligned = sort(s:align_lists(items(list)))
  let colored = map(aligned, 's:yellow(v:val[0])."\t".v:val[1]')
  return s:fzf({
  \ 'source':  colored,
  \ 'options': '--ansi --tiebreak=index +m -n 1 -d "\t"',
  \ 'sink':    s:function('s:inject_snippet')}, a:000)
endfunction

" ------------------------------------------------------------------
" Commands
" ------------------------------------------------------------------
let s:nbs = nr2char(0x2007)

function! s:format_cmd(line)
  return substitute(a:line, '\C \([A-Z]\S*\) ',
        \ '\=s:nbs.s:yellow(submatch(1)).s:nbs', '')
endfunction

function! s:command_sink(cmd)
  let cmd = matchstr(a:cmd, s:nbs.'\zs\S*\ze'.s:nbs)
  call feedkeys(':'.cmd.(a:cmd[0] == '!' ? '' : ' '))
endfunction

function! s:format_excmd(ex)
  let match = matchlist(a:ex, '^|:\(\S\+\)|\s*\S*\(.*\)')
  return printf("   \x1b[34m%-38s\x1b[m%s", s:nbs.match[1].s:nbs, s:strip(match[2]))
endfunction

function! s:excmds()
  let help = globpath($VIMRUNTIME, 'doc/index.txt')
  if empty(help)
    return []
  endif

  let commands = []
  let command = ''
  for line in readfile(help)
    if line =~ '^|:[^|]'
      if !empty(command)
        call add(commands, s:format_excmd(command))
      endif
      let command = line
    elseif line =~ '^\s\+\S' && !empty(command)
      let command .= substitute(line, '^\s*', ' ', '')
    elseif !empty(commands) && line =~ '^\s*$'
      break
    endif
  endfor
  if !empty(command)
    call add(commands, s:format_excmd(command))
  endif
  return commands
endfunction

function! fzf#vim#commands(...)
  redir => cout
  silent command
  redir END
  let list = split(cout, "\n")
  return s:fzf({
  \ 'source':  extend(extend(list[0:0], map(list[1:], 's:format_cmd(v:val)')), s:excmds()),
  \ 'sink':    s:function('s:command_sink'),
  \ 'options': '--ansi --tiebreak=index --header-lines 1 -x --prompt "Commands> " -n2,3,2..3 -d'.s:nbs}, a:000)
endfunction

" ------------------------------------------------------------------
" Marks
" ------------------------------------------------------------------
function! s:format_mark(line)
  return substitute(a:line, '\S', '\=s:yellow(submatch(0))', '')
endfunction

function! s:mark_sink(lines)
  if len(a:lines) < 2
    return
  endif
  let cmd = get(get(g:, 'fzf_action', s:default_action), a:lines[0], '')
  if !empty(cmd)
    execute 'silent' cmd
  endif
  execute 'normal! `'.matchstr(a:lines[1], '\S').'zz'
endfunction

function! fzf#vim#marks(...)
  redir => cout
  silent marks
  redir END
  let list = split(cout, "\n")
  return s:fzf(fzf#vim#wrap({
  \ 'source':  extend(list[0:0], map(list[1:], 's:format_mark(v:val)')),
  \ 'sink*':   s:function('s:mark_sink'),
  \ 'options': '+m -x --ansi --tiebreak=index --header-lines 1 --tiebreak=begin --prompt "Marks> "'}), a:000)
endfunction

" ------------------------------------------------------------------
" Help tags
" ------------------------------------------------------------------
function! s:helptag_sink(line)
  let [tag, file, path] = split(a:line, "\t")[0:2]
  let rtp = fnamemodify(path, ':p:h:h')
  if stridx(&rtp, rtp) < 0
    execute 'set rtp+='.s:escape(rtp)
  endif
  execute 'help' tag
endfunction

function! fzf#vim#helptags(...)
  let tags = uniq(sort(split(globpath(&runtimepath, '**/doc/tags'), '\n')))

  return s:fzf({
  \ 'source':  "grep -H '.*' ".join(map(tags, 'shellescape(v:val)')).
    \ "| perl -ne '/(.*?):(.*?)\t(.*?)\t/; printf(qq(\x1b[33m%-40s\x1b[m\t%s\t%s\n), $2, $3, $1)' | sort",
  \ 'sink':    s:function('s:helptag_sink'),
  \ 'options': '--ansi +m --tiebreak=begin --with-nth ..-2'}, a:000)
endfunction

" ------------------------------------------------------------------
" Windows
" ------------------------------------------------------------------
function! s:format_win(tab, win, buf)
  let modified = getbufvar(a:buf, '&modified')
  let name = bufname(a:buf)
  let name = empty(name) ? '[No Name]' : name
  let active = tabpagewinnr(a:tab) == a:win
  return (active? s:blue('> ') : '  ') . name . (modified? s:red(' [+]') : '')
endfunction

function! s:windows_sink(line)
  let list = matchlist(a:line, '\([ 0-9]*\):\([ 0-9]*\)')
  call s:jump(list[1], list[2])
endfunction

function! fzf#vim#windows(...)
  let lines = []
  for t in range(1, tabpagenr('$'))
    let buffers = tabpagebuflist(t)
    for w in range(1, len(buffers))
      call add(lines,
        \ printf('%s:%s: %s',
            \ s:yellow(printf('%3d', t)),
            \ s:cyan(printf('%3d', w)),
            \ s:format_win(t, w, buffers[w-1])))
    endfor
  endfor
  return s:fzf({
  \ 'source':  extend(['Tab Win    Name'], lines),
  \ 'sink':    s:function('s:windows_sink'),
  \ 'options': '+m --ansi --tiebreak=begin --header-lines=1'}, a:000)
endfunction

" ------------------------------------------------------------------
" Commits / BCommits
" ------------------------------------------------------------------
function! s:commits_sink(lines)
  if len(a:lines) < 2
    return
  endif

  let cmd = get(extend({'ctrl-d': ''}, get(g:, 'fzf_action', s:default_action)), a:lines[0], 'e')
  let buf = bufnr('')
  for idx in range(1, len(a:lines) - 1)
    let sha = matchstr(a:lines[idx], '[0-9a-f]\{7}')
    if !empty(sha)
      if empty(cmd)
        if idx > 1
          execute 'tab sb' buf
        endif
        execute 'Gdiff' sha
      else
        " Since fugitive buffers are unlisted, we can't keep using 'e'
        let c = (cmd == 'e' && idx > 1) ? 'tab split' : cmd
        execute c 'fugitive://'.s:git_root.'/.git//'.sha
      endif
    endif
  endfor
endfunction

function! s:commits(buffer_local, args)
  let s:git_root = s:chomp(system('git rev-parse --show-toplevel'))
  if v:shell_error
    return s:warn('Not in git repository')
  endif

  let source = 'git log '.get(g:, 'fzf_commits_log_options', '--graph --color=always --format="%C(auto)%h%d %s %C(black)%C(bold)%cr"')
  let current = expand('%:S')
  let managed = 0
  if !empty(current)
    call system('git show '.current.' 2> /dev/null')
    let managed = !v:shell_error
  endif

  if a:buffer_local
    if !managed
      return s:warn('The current buffer is not in the working tree')
    endif
    let source .= ' --follow '.current
  endif

  let command = a:buffer_local ? 'BCommits' : 'Commits'
  let options = fzf#vim#wrap({
  \ 'source':  source,
  \ 'sink*':   s:function('s:commits_sink'),
  \ 'options': '--ansi --multi --no-sort --tiebreak=index --reverse '.
  \   '--inline-info --prompt "'.command.'> " --bind=ctrl-s:toggle-sort'
  \ })

  if a:buffer_local
    let options.options .= ',ctrl-d --header ":: Press '.s:magenta('CTRL-S').' to toggle sort, '.s:magenta('CTRL-D').' to diff"'
  else
    let options.options .=        ' --header ":: Press '.s:magenta('CTRL-S').' to toggle sort"'
  endif

  return s:fzf(options, a:args)
endfunction

function! fzf#vim#commits(...)
  return s:commits(0, a:000)
endfunction

function! fzf#vim#buffer_commits(...)
  return s:commits(1, a:000)
endfunction

" ------------------------------------------------------------------
" fzf#vim#maps(mode, opts[with count and op])
" ------------------------------------------------------------------
function! s:align_pairs(list)
  let maxlen = 0
  let pairs = []
  for elem in a:list
    let match = matchlist(elem, '^\(\S*\)\s*\(.*\)$')
    let [_, k, v] = match[0:2]
    let maxlen = max([maxlen, len(k)])
    call add(pairs, [k, substitute(v, '^\*\?[@ ]\?', '', '')])
  endfor
  let maxlen = min([maxlen, 35])
  return map(pairs, "printf('%-'.maxlen.'s', v:val[0]).' '.v:val[1]")
endfunction

function! s:highlight_keys(str)
  return substitute(
        \ substitute(a:str, '<[^ >]\+>', "\x1b[33m\\0\x1b[m", 'g'),
        \ "\x1b[33m<Plug>\x1b[m", "\x1b[34m<Plug>\x1b[m", 'g')
endfunction

function! s:key_sink(line)
  let key = matchstr(a:line, '^\S*')
  redraw
  call feedkeys(s:map_gv.s:map_cnt.s:map_reg.s:map_op.
        \ substitute(key, '<[^ >]\+>', '\=eval("\"\\".submatch(0)."\"")', 'g'))
endfunction

" To avoid conflict with other plugins also using feedkeys (peekaboo)
noremap <plug>(-fzf-vim-dq) "

function! fzf#vim#maps(mode, ...)
  let s:map_gv  = a:mode == 'x' ? 'gv' : ''
  let s:map_cnt = v:count == 0 ? '' : v:count
  let s:map_reg = empty(v:register) ? '' : ("\<plug>(-fzf-vim-dq)".v:register)
  let s:map_op  = a:mode == 'o' ? v:operator : ''

  redir => cout
  silent execute 'verbose' a:mode.'map'
  redir END
  let list = []
  let curr = ''
  for line in split(cout, "\n")
    let src = matchstr(line, 'Last set from \zs.*')
    if empty(src)
      let curr = line[3:]
    else
      let src = '  '.join(reverse(reverse(split(src, '/'))[0:2]), '/')
      call add(list, printf('%s %s', curr, s:black(src)))
      let curr = ''
    endif
  endfor
  if !empty(curr)
    call add(list, curr)
  endif
  let aligned = s:align_pairs(list)
  let sorted  = sort(aligned)
  let colored = map(sorted, 's:highlight_keys(v:val)')
  let pcolor  = a:mode == 'x' ? 9 : a:mode == 'o' ? 10 : 12
  return s:fzf({
  \ 'source':  colored,
  \ 'sink':    s:function('s:key_sink'),
  \ 'options': '--prompt "Maps ('.a:mode.')> " --ansi --no-hscroll --nth 1,.. --color prompt:'.pcolor}, a:000)
endfunction

" ----------------------------------------------------------------------------
" fzf#vim#complete - completion helper
" ----------------------------------------------------------------------------
inoremap <silent> <Plug>(-fzf-complete-trigger) <c-o>:call <sid>complete_trigger()<cr>

function! s:pluck(dict, key, default)
  return has_key(a:dict, a:key) ? remove(a:dict, a:key) : a:default
endfunction

function! s:complete_trigger()
  let opts = copy(s:opts)
  let opts.options = printf('+m -q %s %s', shellescape(s:query), get(opts, 'options', ''))
  let opts['sink*'] = s:function('s:complete_insert')
  let s:reducer = s:pluck(opts, 'reducer', s:function('s:first_line'))
  call fzf#run(opts)
endfunction

" The default reducer
function! s:first_line(lines)
  return a:lines[0]
endfunction

function! s:complete_insert(lines)
  if empty(a:lines)
    return
  endif

  let chars = strchars(s:query)
  if     chars == 0 | let del = ''
  elseif chars == 1 | let del = '"_x'
  else              | let del = (chars - 1).'"_dvh'
  endif

  let data = call(s:reducer, [a:lines])
  execute 'normal!' ((s:eol || empty(chars)) ? '' : 'h').del.(s:eol ? 'a': 'i').data
  if has('nvim')
    call feedkeys('a')
  else
    execute "normal! \<esc>la"
  endif
endfunction

let s:TYPE = {'dict': type({}), 'funcref': type(function('call'))}

function! s:eval(dict, key, arg)
  if has_key(a:dict, a:key) && type(a:dict[a:key]) == s:TYPE.funcref
    let ret = copy(a:dict)
    let ret[a:key] = call(a:dict[a:key], [a:arg])
    return ret
  endif
  return a:dict
endfunction

function! fzf#vim#complete(...)
  if a:0 == 0
    let s:opts = g:fzf#vim#default_layout
  elseif type(a:1) == s:TYPE.dict
    if has_key(a:1, 'sink') || has_key(a:1, 'sink*')
      echoerr 'sink not allowed'
      return ''
    endif
    let s:opts = copy(a:1)
  else
    let s:opts = extend({'source': a:1}, g:fzf#vim#default_layout)
  endif

  let eol = col('$')
  let ve = &ve
  set ve=all
  let s:eol = col('.') == eol
  let &ve = ve

  let Prefix = s:pluck(s:opts, 'prefix', '\k*$')
  if col('.') == 1
    let s:query = ''
  else
    let full_prefix = getline('.')[0 : col('.')-2]
    if type(Prefix) == s:TYPE.funcref
      let s:query = call(Prefix, [full_prefix])
    else
      let s:query = matchstr(full_prefix, Prefix)
    endif
  endif
  let s:opts = s:eval(s:opts, 'source', s:query)
  let s:opts = s:eval(s:opts, 'options', s:query)
  let s:opts = s:eval(s:opts, 'extra_options', s:query)
  if has_key(s:opts, 'extra_options')
    let s:opts.options =
      \ join(filter([get(s:opts, 'options', ''), remove(s:opts, 'extra_options')], '!empty(v:val)'))
  endif

  call feedkeys("\<Plug>(-fzf-complete-trigger)")
  return ''
endfunction

" ------------------------------------------------------------------
let &cpo = s:cpo_save
unlet s:cpo_save

