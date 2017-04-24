" Copyright (c) 2017 Junegunn Choi
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

let s:layout_keys = ['window', 'up', 'down', 'left', 'right']
let s:bin_dir = expand('<sfile>:h:h:h').'/bin/'
let s:bin = {
\ 'preview': s:bin_dir.(executable('ruby') ? 'preview.rb' : 'preview.sh'),
\ 'tags':    s:bin_dir.'tags.pl' }
let s:TYPE = {'dict': type({}), 'funcref': type(function('call')), 'string': type('')}

" [[options to wrap], preview window expression, [toggle-preview keys...]]
function! fzf#vim#with_preview(...)
  " Default options
  let options = {}
  let window = 'right'

  let args = copy(a:000)

  " Options to wrap
  if len(args) && type(args[0]) == s:TYPE.dict
    let options = copy(args[0])
    call remove(args, 0)
  endif

  " Preview window
  if len(args) && type(args[0]) == s:TYPE.string
    if args[0] !~# '^\(up\|down\|left\|right\)'
      throw 'invalid preview window: '.args[0]
    endif
    let window = args[0]
    call remove(args, 0)
  endif

  let preview = printf(' --preview-window %s --preview "%s"\ %s\ {}',
        \ window,
        \ shellescape(s:bin.preview), window =~ 'up\|down' ? '-v' : '')
  if len(args)
    let preview .= ' --bind '.shellescape(join(map(args, 'v:val.":toggle-preview"'), ','))
  endif
  let options.options = get(options, 'options', '').preview
  return options
endfunction

function! s:remove_layout(opts)
  for key in s:layout_keys
    if has_key(a:opts, key)
      call remove(a:opts, key)
    endif
  endfor
  return a:opts
endfunction

" Deprecated: use fzf#wrap instead
function! fzf#vim#wrap(opts)
  return fzf#wrap(a:opts)
endfunction

" Deprecated
function! fzf#vim#layout(...)
  return (a:0 && a:1) ? {} : copy(get(g:, 'fzf_layout', g:fzf#vim#default_layout))
endfunction

function! s:wrap(name, opts, bang)
  " fzf#wrap does not append --expect if sink or sink* is found
  let opts = copy(a:opts)
  if get(opts, 'options', '') !~ '--expect' && has_key(opts, 'sink*')
    let Sink = remove(opts, 'sink*')
    let wrapped = fzf#wrap(a:name, opts, a:bang)
    let wrapped['sink*'] = Sink
  else
    let wrapped = fzf#wrap(a:name, opts, a:bang)
  endif
  return wrapped
endfunction

function! s:strip(str)
  return substitute(a:str, '^\s*\|\s*$', '', 'g')
endfunction

function! s:chomp(str)
  return substitute(a:str, '\n*$', '', 'g')
endfunction

function! s:escape(path)
  return escape(a:path, ' $%#''"\')
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

function! s:get_color(attr, ...)
  let gui = has('termguicolors') && &termguicolors
  let fam = gui ? 'gui' : 'cterm'
  let pat = gui ? '^#[a-f0-9]\+' : '^[0-9]\+$'
  for group in a:000
    let code = synIDattr(synIDtrans(hlID(group)), a:attr, fam)
    if code =~? pat
      return code
    endif
  endfor
  return ''
endfunction

let s:ansi = {'black': 30, 'red': 31, 'green': 32, 'yellow': 33, 'blue': 34, 'magenta': 35, 'cyan': 36}

function! s:csi(color, fg)
  let prefix = a:fg ? '38;' : '48;'
  if a:color[0] == '#'
    return prefix.'2;'.join(map([a:color[1:2], a:color[3:4], a:color[5:6]], 'str2nr(v:val, 16)'), ';')
  endif
  return prefix.'5;'.a:color
endfunction

function! s:ansi(str, group, default, ...)
  let fg = s:get_color('fg', a:group)
  let bg = s:get_color('bg', a:group)
  let color = s:csi(empty(fg) ? s:ansi[a:default] : fg, 1) .
        \ (empty(bg) ? '' : s:csi(bg, 0))
  return printf("\x1b[%s%sm%s\x1b[m", color, a:0 ? ';1' : '', a:str)
endfunction

for s:color_name in keys(s:ansi)
  execute "function! s:".s:color_name."(str, ...)\n"
        \ "  return s:ansi(a:str, get(a:, 1, ''), '".s:color_name."')\n"
        \ "endfunction"
endfor

function! s:buflisted()
  return filter(range(1, bufnr('$')), 'buflisted(v:val) && getbufvar(v:val, "&filetype") != "qf"')
endfunction

function! s:fzf(name, opts, extra)
  let [extra, bang] = [{}, 0]
  if len(a:extra) <= 1
    let first = get(a:extra, 0, 0)
    if type(first) == s:TYPE.dict
      let extra = first
    else
      let bang = first
    endif
  elseif len(a:extra) == 2
    let [extra, bang] = a:extra
  else
    throw 'invalid number of arguments'
  endif

  let eopts  = has_key(extra, 'options') ? remove(extra, 'options') : ''
  let merged = extend(copy(a:opts), extra)
  let merged.options = join(filter([get(merged, 'options', ''), eopts], '!empty(v:val)'))
  return fzf#run(s:wrap(a:name, merged, bang))
endfunction

let s:default_action = {
  \ 'ctrl-t': 'tab split',
  \ 'ctrl-x': 'split',
  \ 'ctrl-v': 'vsplit' }

function! s:open(cmd, target)
  if stridx('edit', a:cmd) == 0 && fnamemodify(a:target, ':p') ==# expand('%:p')
    return
  endif
  execute a:cmd s:escape(a:target)
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

function! fzf#vim#_uniq(list)
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
function! s:shortpath()
  let short = pathshorten(fnamemodify(getcwd(), ':~:.'))
  return empty(short) ? '~/' : short . (short =~ '/$' ? '' : '/')
endfunction

function! fzf#vim#files(dir, ...)
  let args = {'options': '-m '.get(g:, 'fzf_files_options', '')}
  if !empty(a:dir)
    if !isdirectory(expand(a:dir))
      return s:warn('Invalid directory')
    endif
    let dir = substitute(a:dir, '/*$', '/', '')
    let args.dir = dir
    let args.options .= ' --prompt '.shellescape(dir)
  else
    let args.options .= ' --prompt '.shellescape(s:shortpath())
  endif

  return s:fzf('files', args, a:000)
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
  if !empty(cmd) && stridx('edit', cmd) < 0
    execute 'silent' cmd
  endif

  let keys = split(a:lines[1], '\t')
  execute 'buffer' keys[0]
  execute keys[2]
  normal! ^zz
endfunction

function! fzf#vim#_lines(all)
  let cur = []
  let rest = []
  let buf = bufnr('')
  let longest_name = 0
  let display_bufnames = &columns > 100
  if display_bufnames
    let bufnames = {}
    for b in s:buflisted()
      let bufnames[b] = pathshorten(fnamemodify(bufname(b), ":~:."))
      let longest_name = max([longest_name, len(bufnames[b])])
    endfor
  endif
  let len_bufnames = min([15, longest_name])
  for b in s:buflisted()
    let lines = getbufline(b, 1, "$")
    if empty(lines)
      let path = fnamemodify(bufname(b), ':p')
      let lines = filereadable(path) ? readfile(path) : []
    endif
    if display_bufnames
      let bufname = bufnames[b]
      if len(bufname) > len_bufnames + 1
        let bufname = '…' . bufname[-(len_bufnames+1):]
      endif
      let bufname = printf(s:green("%".len_bufnames."s", "Directory"), bufname)
    else
      let bufname = ''
    endif
    call extend(b == buf ? cur : rest,
    \ filter(
    \   map(lines,
    \       '(!a:all && empty(v:val)) ? "" : printf(s:blue("%2d\t", "TabLine")."%s".s:yellow("\t%4d ", "LineNr")."\t%s", b, bufname, v:key + 1, v:val)'),
    \   'a:all || !empty(v:val)'))
  endfor
  return [display_bufnames, extend(cur, rest)]
endfunction

function! fzf#vim#lines(...)
  let [display_bufnames, lines] = fzf#vim#_lines(1)
  let nth = display_bufnames ? 3 : 2
  let [query, args] = (a:0 && type(a:1) == type('')) ?
        \ [a:1, a:000[1:]] : ['', a:000]
  return s:fzf('lines', {
  \ 'source':  lines,
  \ 'sink*':   s:function('s:line_handler'),
  \ 'options': '+m --tiebreak=index --prompt "Lines> " --ansi --extended --nth='.nth.'.. --reverse --tabstop=1'.s:q(query)
  \}, args)
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

  execute split(a:lines[1], '\t')[0]
  normal! ^zz
endfunction

function! s:buffer_lines()
  return map(getline(1, "$"),
    \ 'printf(s:yellow(" %4d ", "LineNr")."\t%s", v:key + 1, v:val)')
endfunction

function! fzf#vim#buffer_lines(...)
  let [query, args] = (a:0 && type(a:1) == type('')) ?
        \ [a:1, a:000[1:]] : ['', a:000]
  return s:fzf('blines', {
  \ 'source':  s:buffer_lines(),
  \ 'sink*':   s:function('s:buffer_line_handler'),
  \ 'options': '+m --tiebreak=index --prompt "BLines> " --ansi --extended --nth=2.. --reverse --tabstop=1'.s:q(query)
  \}, args)
endfunction

" ------------------------------------------------------------------
" Colors
" ------------------------------------------------------------------
function! fzf#vim#colors(...)
  return s:fzf('colors', {
  \ 'source':  fzf#vim#_uniq(map(split(globpath(&rtp, "colors/*.vim"), "\n"),
  \               "substitute(fnamemodify(v:val, ':t'), '\\..\\{-}$', '', '')")),
  \ 'sink':    'colo',
  \ 'options': '+m --prompt="Colors> "'
  \}, a:000)
endfunction

" ------------------------------------------------------------------
" Locate
" ------------------------------------------------------------------
function! fzf#vim#locate(query, ...)
  return s:fzf('locate', {
  \ 'source':  'locate '.a:query,
  \ 'options': '-m --prompt "Locate> "'
  \}, a:000)
endfunction

" ------------------------------------------------------------------
" History[:/]
" ------------------------------------------------------------------
function! s:all_files()
  return extend(
  \ filter(reverse(copy(v:oldfiles)), "filereadable(expand(v:val))"),
  \ filter(map(s:buflisted(), 'bufname(v:val)'), '!empty(v:val)'))
endfunction

function! s:history_source(type)
  let max  = histnr(a:type)
  let fmt  = ' %'.len(string(max)).'d '
  let list = filter(map(range(1, max), 'histget(a:type, - v:val)'), '!empty(v:val)')
  return extend([' :: Press '.s:magenta('CTRL-E', 'Special').' to edit'],
    \ map(list, 's:yellow(printf(fmt, len(list) - v:key), "Number")." ".v:val'))
endfunction

nnoremap <plug>(-fzf-vim-do) :execute g:__fzf_command<cr>

function! s:history_sink(type, lines)
  if len(a:lines) < 2
    return
  endif

  let key  = a:lines[0]
  let item = matchstr(a:lines[1], ' *[0-9]\+ *\zs.*')
  if key == 'ctrl-e'
    call histadd(a:type, item)
    redraw
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
  return s:fzf('history-command', {
  \ 'source':  s:history_source(':'),
  \ 'sink*':   s:function('s:cmd_history_sink'),
  \ 'options': '+m --ansi --prompt="Hist:> " --header-lines=1 --expect=ctrl-e --tiebreak=index'}, a:000)
endfunction

function! s:search_history_sink(lines)
  call s:history_sink('/', a:lines)
endfunction

function! fzf#vim#search_history(...)
  return s:fzf('history-search', {
  \ 'source':  s:history_source('/'),
  \ 'sink*':   s:function('s:search_history_sink'),
  \ 'options': '+m --ansi --prompt="Hist/> " --header-lines=1 --expect=ctrl-e --tiebreak=index'}, a:000)
endfunction

function! fzf#vim#history(...)
  return s:fzf('history-files', {
  \ 'source':  reverse(s:all_files()),
  \ 'options': '-m --prompt "Hist> "'
  \}, a:000)
endfunction

" ------------------------------------------------------------------
" GFiles[?]
" ------------------------------------------------------------------

" helper function to get the git root. Uses vim-fugitive if available for EXTRA SPEED!
function! s:get_git_root()
  if exists('*fugitive#repo')
    try
      return fugitive#repo().tree()
    catch
    endtry
  endif
  let root = split(system('git rev-parse --show-toplevel'), '\n')[0]
  return v:shell_error ? '' : root
endfunction

function! fzf#vim#gitfiles(args, ...)
  let root = s:get_git_root()
  if empty(root)
    return s:warn('Not in git repo')
  endif
  if a:args != '?'
    return s:fzf('gfiles', {
    \ 'source':  'git ls-files '.a:args,
    \ 'dir':     root,
    \ 'options': '-m --prompt "GitFiles> "'
    \}, a:000)
  endif

  " Here be dragons!
  " We're trying to access the common sink function that fzf#wrap injects to
  " the options dictionary.
  let wrapped = fzf#wrap({
  \ 'source':  'git -c color.status=always status --short --untracked-files=all',
  \ 'dir':     root,
  \ 'options': '--ansi --multi --nth 2..,.. --tiebreak=index --prompt "GitFiles?> " --preview ''sh -c "(git diff --color=always -- {-1} | sed 1,4d; cat {-1}) | head -500"'''
  \})
  call s:remove_layout(wrapped)
  let wrapped.common_sink = remove(wrapped, 'sink*')
  function! wrapped.newsink(lines)
    let lines = extend(a:lines[0:0], map(a:lines[1:], 'substitute(v:val[3:], ".* -> ", "", "")'))
    return self.common_sink(lines)
  endfunction
  let wrapped['sink*'] = remove(wrapped, 'newsink')
  return s:fzf('gfiles-diff', wrapped, a:000)
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
  let name = empty(name) ? '[No Name]' : fnamemodify(name, ":~:.")
  let flag = a:b == bufnr('')  ? s:blue('%', 'Conditional') :
          \ (a:b == bufnr('#') ? s:magenta('#', 'Special') : ' ')
  let modified = getbufvar(a:b, '&modified') ? s:red(' [+]', 'Exception') : ''
  let readonly = getbufvar(a:b, '&modifiable') ? '' : s:green(' [RO]', 'Constant')
  let extra = join(filter([modified, readonly], '!empty(v:val)'), '')
  return s:strip(printf("[%s] %s\t%s\t%s", s:yellow(a:b, 'Number'), flag, name, extra))
endfunction

function! s:sort_buffers(...)
  let [b1, b2] = map(copy(a:000), 'get(g:fzf#vim#buffers, v:val, v:val)')
  " Using minus between a float and a number in a sort function causes an error
  return b1 > b2 ? 1 : -1
endfunction

function! fzf#vim#buffers(...)
  let bufs = map(sort(s:buflisted(), 's:sort_buffers'), 's:format_buffer(v:val)')

  let [query, args] = (a:0 && type(a:1) == type('')) ?
        \ [a:1, a:000[1:]] : ['', a:000]
  return s:fzf('buffers', {
  \ 'source':  reverse(bufs),
  \ 'sink*':   s:function('s:bufopen'),
  \ 'options': '+m -x --tiebreak=index --header-lines=1 --ansi -d "\t" -n 2,1..2 --prompt="Buf> "'.s:q(query)
  \}, args)
endfunction

" ------------------------------------------------------------------
" Ag
" ------------------------------------------------------------------
function! s:ag_to_qf(line, with_column)
  let parts = split(a:line, ':')
  let text = join(parts[(a:with_column ? 3 : 2):], ':')
  let dict = {'filename': &acd ? fnamemodify(parts[0], ':p') : parts[0], 'lnum': parts[1], 'text': text}
  if a:with_column
    let dict.col = parts[2]
  endif
  return dict
endfunction

function! s:ag_handler(lines, with_column)
  if len(a:lines) < 2
    return
  endif

  let cmd = get(get(g:, 'fzf_action', s:default_action), a:lines[0], 'e')
  let list = map(filter(a:lines[1:], 'len(v:val)'), 's:ag_to_qf(v:val, a:with_column)')
  if empty(list)
    return
  endif

  let first = list[0]
  try
    call s:open(cmd, first.filename)
    execute first.lnum
    if a:with_column
      execute 'normal!' first.col.'|'
    endif
    normal! zz
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
  if type(a:query) != s:TYPE.string
    return s:warn('Invalid query argument')
  endif
  let query = empty(a:query) ? '^(?=.)' : a:query
  let args = copy(a:000)
  let ag_opts = len(args) > 1 && type(args[0]) == s:TYPE.string ? remove(args, 0) : ''
  let command = ag_opts . ' ' . shellescape(query)
  return call('fzf#vim#ag_raw', insert(args, command, 0))
endfunction

" ag command suffix, [options]
function! fzf#vim#ag_raw(command_suffix, ...)
  return call('fzf#vim#grep', extend(['ag --nogroup --column --color '.a:command_suffix, 1], a:000))
endfunction

" command, with_column, [options]
function! fzf#vim#grep(grep_command, with_column, ...)
  let words = []
  for word in split(a:grep_command)
    if word !~# '^[a-z]'
      break
    endif
    call add(words, word)
  endfor
  let words   = empty(words) ? ['grep'] : words
  let name    = join(words, '-')
  let capname = join(map(words, 'toupper(v:val[0]).v:val[1:]'), '')
  let textcol = a:with_column ? '4..' : '3..'
  let opts = {
  \ 'source':  a:grep_command,
  \ 'column':  a:with_column,
  \ 'options': '--ansi --delimiter : --nth '.textcol.',.. --prompt "'.capname.'> " '.
  \            '--multi --bind alt-a:select-all,alt-d:deselect-all '.
  \            '--color hl:68,hl+:110'
  \}
  function! opts.sink(lines)
    return s:ag_handler(a:lines, self.column)
  endfunction
  let opts['sink*'] = remove(opts, 'sink')
  return s:fzf(name, opts, a:000)
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
  return ' --query '.shellescape(a:query)
endfunction

" query, [[tag commands], options]
function! fzf#vim#buffer_tags(query, ...)
  let args = copy(a:000)
  let tag_cmds = (len(args) > 1 && type(args[0]) != type({})) ? remove(args, 0) : [
    \ printf('ctags -f - --sort=no --excmd=number --language-force=%s %s 2>/dev/null', &filetype, expand('%:S')),
    \ printf('ctags -f - --sort=no --excmd=number %s 2>/dev/null', expand('%:S'))]
  if type(tag_cmds) != type([])
    let tag_cmds = [tag_cmds]
  endif
  try
    return s:fzf('btags', {
    \ 'source':  s:btags_source(tag_cmds),
    \ 'sink*':   s:function('s:btags_sink'),
    \ 'options': '--reverse -m -d "\t" --with-nth 1,4.. -n 1 --prompt "BTags> "'.s:q(a:query)}, args)
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
  try
    let [magic, &magic, wrapscan, &wrapscan, acd, &acd] = [&magic, 0, &wrapscan, 1, &acd, 0]
    for line in a:lines[1:]
      try
        let parts   = split(line, '\t\zs')
        let excmd   = matchstr(join(parts[2:-2], '')[:-2], '^.*\ze;"\t')
        let base    = fnamemodify(parts[-1], ':h')
        let relpath = parts[1][:-2]
        let abspath = relpath =~ '^/' ? relpath : join([base, relpath], '/')
        call s:open(cmd, abspath)
        execute excmd
        call add(qfl, {'filename': expand('%'), 'lnum': line('.'), 'text': getline('.')})
      catch /^Vim:Interrupt$/
        break
      catch
        call s:warn(v:exception)
      endtry
    endfor
  finally
    let [&magic, &wrapscan, &acd] = [magic, wrapscan, acd]
  endtry
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
    call inputsave()
    echohl WarningMsg
    let gen = input('tags not found. Generate? (y/N) ')
    echohl None
    call inputrestore()
    redraw
    if gen =~? '^y'
      call s:warn('Preparing tags')
      call system(get(g:, 'fzf_tags_command', 'ctags -R'))
      if empty(tagfiles())
        return s:warn('Failed to create tags')
      endif
    else
      return s:warn('No tags found')
    endif
  endif

  let tagfiles = tagfiles()
  let v2_limit = 1024 * 1024 * 200
  for tagfile in tagfiles
    let v2_limit -= getfsize(tagfile)
    if v2_limit < 0
      break
    endif
  endfor
  let opts = v2_limit < 0 ? '--algo=v1 ' : ''

  return s:fzf('tags', {
  \ 'source':  shellescape(s:bin.tags).' '.join(map(tagfiles, 'shellescape(fnamemodify(v:val, ":p"))')),
  \ 'sink*':   s:function('s:tags_sink'),
  \ 'options': opts.'--nth 1..2 --with-nth ..-2 -m --tiebreak=begin --prompt "Tags> "'.s:q(a:query)}, a:000)
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
  return s:fzf('snippets', {
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
        \ '\=s:nbs.s:yellow(submatch(1), "Function").s:nbs', '')
endfunction

function! s:command_sink(lines)
  if len(a:lines) < 2
    return
  endif
  let cmd = matchstr(a:lines[1], s:nbs.'\zs\S*\ze'.s:nbs)
  if empty(a:lines[0])
    call feedkeys(':'.cmd.(a:lines[1][0] == '!' ? '' : ' '))
  else
    execute cmd
  endif
endfunction

function! s:format_excmd(ex)
  let match = matchlist(a:ex, '^|:\(\S\+\)|\s*\S*\(.*\)')
  return printf('   '.s:blue('%-38s', 'Statement').'%s', s:nbs.match[1].s:nbs, s:strip(match[2]))
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
  return s:fzf('commands', {
  \ 'source':  extend(extend(list[0:0], map(list[1:], 's:format_cmd(v:val)')), s:excmds()),
  \ 'sink*':   s:function('s:command_sink'),
  \ 'options': '--ansi --expect '.get(g:, 'fzf_commands_expect', 'ctrl-x').
  \            ' --tiebreak=index --header-lines 1 -x --prompt "Commands> " -n2,3,2..3 -d'.s:nbs}, a:000)
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
  return s:fzf('marks', {
  \ 'source':  extend(list[0:0], map(list[1:], 's:format_mark(v:val)')),
  \ 'sink*':   s:function('s:mark_sink'),
  \ 'options': '+m -x --ansi --tiebreak=index --header-lines 1 --tiebreak=begin --prompt "Marks> "'}, a:000)
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
  let sorted = sort(split(globpath(&runtimepath, '**/doc/tags'), '\n'))
  let tags = exists('*uniq') ? uniq(sorted) : fzf#vim#_uniq(sorted)

  return s:fzf('helptags', {
  \ 'source':  "grep -H '.*' ".join(map(tags, 'shellescape(v:val)')).
    \ "| perl -ne '/(.*?):(.*?)\t(.*?)\t/; printf(qq(".s:green('%-40s', 'Label')."\t%s\t%s\n), $2, $3, $1)' | sort",
  \ 'sink':    s:function('s:helptag_sink'),
  \ 'options': '--ansi +m --tiebreak=begin --with-nth ..-2'}, a:000)
endfunction

" ------------------------------------------------------------------
" File types
" ------------------------------------------------------------------
function! fzf#vim#filetypes(...)
  return s:fzf('filetypes', {
  \ 'source':  sort(map(split(globpath(&rtp, 'syntax/*.vim'), '\n'),
  \            'fnamemodify(v:val, ":t:r")')),
  \ 'sink':    'setf',
  \ 'options': '+m --prompt="File types> "'
  \}, a:000)
endfunction

" ------------------------------------------------------------------
" Windows
" ------------------------------------------------------------------
function! s:format_win(tab, win, buf)
  let modified = getbufvar(a:buf, '&modified')
  let name = bufname(a:buf)
  let name = empty(name) ? '[No Name]' : name
  let active = tabpagewinnr(a:tab) == a:win
  return (active? s:blue('> ', 'Operator') : '  ') . name . (modified? s:red(' [+]', 'Exception') : '')
endfunction

function! s:windows_sink(line)
  let list = matchlist(a:line, '^ *\([0-9]\+\) *\([0-9]\+\)')
  call s:jump(list[1], list[2])
endfunction

function! fzf#vim#windows(...)
  let lines = []
  for t in range(1, tabpagenr('$'))
    let buffers = tabpagebuflist(t)
    for w in range(1, len(buffers))
      call add(lines,
        \ printf('%s %s  %s',
            \ s:yellow(printf('%3d', t), 'Number'),
            \ s:cyan(printf('%3d', w), 'String'),
            \ s:format_win(t, w, buffers[w-1])))
    endfor
  endfor
  return s:fzf('windows', {
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
  let s:git_root = s:get_git_root()
  if empty(s:git_root)
    return s:warn('Not in git repository')
  endif

  let source = 'git log '.get(g:, 'fzf_commits_log_options', '--graph --color=always --format="%C(auto)%h%d %s %C(green)%cr"')
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
  let expect_keys = join(keys(get(g:, 'fzf_action', s:default_action)), ',')
  let options = {
  \ 'source':  source,
  \ 'sink*':   s:function('s:commits_sink'),
  \ 'options': '--ansi --multi --tiebreak=index --reverse '.
  \   '--inline-info --prompt "'.command.'> " --bind=ctrl-s:toggle-sort '.
  \   '--expect='.expect_keys
  \ }

  if a:buffer_local
    let options.options .= ',ctrl-d --header ":: Press '.s:magenta('CTRL-S', 'Special').' to toggle sort, '.s:magenta('CTRL-D', 'Special').' to diff"'
  else
    let options.options .=        ' --header ":: Press '.s:magenta('CTRL-S', 'Special').' to toggle sort"'
  endif

  return s:fzf(a:buffer_local ? 'bcommits' : 'commits', options, a:args)
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
        \ substitute(a:str, '<[^ >]\+>', s:yellow('\0', 'Special'), 'g'),
        \ '<Plug>', s:blue('<Plug>', 'SpecialKey'), 'g')
endfunction

function! s:key_sink(line)
  let key = matchstr(a:line, '^\S*')
  redraw
  call feedkeys(s:map_gv.s:map_cnt.s:map_reg, 'n')
  call feedkeys(s:map_op.
        \ substitute(key, '<[^ >]\+>', '\=eval("\"\\".submatch(0)."\"")', 'g'))
endfunction

function! fzf#vim#maps(mode, ...)
  let s:map_gv  = a:mode == 'x' ? 'gv' : ''
  let s:map_cnt = v:count == 0 ? '' : v:count
  let s:map_reg = empty(v:register) ? '' : ('"'.v:register)
  let s:map_op  = a:mode == 'o' ? v:operator : ''

  redir => cout
  silent execute 'verbose' a:mode.'map'
  redir END
  let list = []
  let curr = ''
  for line in split(cout, "\n")
    if line =~ "^\t"
      let src = '  '.join(reverse(reverse(split(split(line)[-1], '/'))[0:2]), '/')
      call add(list, printf('%s %s', curr, s:green(src, 'Comment')))
      let curr = ''
    else
      let curr = line[3:]
    endif
  endfor
  if !empty(curr)
    call add(list, curr)
  endif
  let aligned = s:align_pairs(list)
  let sorted  = sort(aligned)
  let colored = map(sorted, 's:highlight_keys(v:val)')
  let pcolor  = a:mode == 'x' ? 9 : a:mode == 'o' ? 10 : 12
  return s:fzf('maps', {
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
  let ve = &ve
  set ve=
  execute 'normal!' ((s:eol || empty(chars)) ? '' : 'h').del.(s:eol ? 'a': 'i').data
  let &ve = ve
  if mode() =~ 't'
    call feedkeys('a', 'n')
  else
    execute "normal! \<esc>la"
  endif
endfunction

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

