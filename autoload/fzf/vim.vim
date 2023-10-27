" Copyright (c) 2023 Junegunn Choi
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

function! s:conf(name, default)
  let conf = get(g:, 'fzf_vim', {})
  return get(conf, a:name, get(g:, 'fzf_' . a:name, a:default))
endfunction

let s:winpath = {}
function! s:winpath(path)
  if has_key(s:winpath, a:path)
    return s:winpath[a:path]
  endif

  let winpath = split(system('for %A in ("'.a:path.'") do @echo %~sA'), "\n")[0]
  let s:winpath[a:path] = winpath

  return winpath
endfunction

let s:warned = 0
function! s:bash()
  if exists('s:bash')
    return s:bash
  endif

  let custom_bash = s:conf('preview_bash', '')
  let git_bash = 'C:\Program Files\Git\bin\bash.exe'
  let candidates = filter(s:is_win ? [custom_bash, 'bash', git_bash] : [custom_bash, 'bash'], 'len(v:val)')

  let found = filter(map(copy(candidates), 'exepath(v:val)'), 'len(v:val)')
  if empty(found)
    if !s:warned
      call s:warn(printf('Preview window not supported (%s not found)', join(candidates, ', ')))
      let s:warned = 1
    endif
    let s:bash = ''
    return s:bash
  endif

  let s:bash = found[0]

  " Make 8.3 filename via cmd.exe
  if s:is_win
    let s:bash = s:winpath(s:bash)
  endif

  return s:bash
endfunction

function! s:escape_for_bash(path)
  if !s:is_win
    return fzf#shellescape(a:path)
  endif

  if !exists('s:is_linux_like_bash')
    call system(s:bash . ' -c "ls /mnt/[A-Za-z]"')
    let s:is_linux_like_bash = v:shell_error == 0
  endif

  let path = substitute(a:path, '\', '/', 'g')
  if s:is_linux_like_bash
    let path = substitute(path, '^\([A-Z]\):', '/mnt/\L\1', '')
  endif

  return escape(path, ' ')
endfunction

let s:min_version = '0.23.0'
let s:is_win = has('win32') || has('win64')
let s:is_wsl_bash = s:is_win && (exepath('bash') =~? 'Windows[/\\]system32[/\\]bash.exe$')
let s:layout_keys = ['window', 'up', 'down', 'left', 'right']
let s:bin_dir = expand('<sfile>:p:h:h:h').'/bin/'
let s:bin = {
\ 'preview': s:bin_dir.'preview.sh',
\ 'tags':    s:bin_dir.'tags.pl' }
let s:TYPE = {'bool': type(0), 'dict': type({}), 'funcref': type(function('call')), 'string': type(''), 'list': type([])}

let s:wide = 120
let s:checked = 0

function! s:check_requirements()
  if s:checked
    return
  endif

  if !exists('*fzf#run')
    throw "fzf#run function not found. You also need Vim plugin from the main fzf repository (i.e. junegunn/fzf *and* junegunn/fzf.vim)"
  endif
  if !exists('*fzf#exec')
    throw "fzf#exec function not found. You need to upgrade Vim plugin from the main fzf repository ('junegunn/fzf')"
  endif
  let s:checked = !empty(fzf#exec(s:min_version))
endfunction

function! s:extend_opts(dict, eopts, prepend)
  if empty(a:eopts)
    return
  endif
  if has_key(a:dict, 'options')
    if type(a:dict.options) == s:TYPE.list && type(a:eopts) == s:TYPE.list
      if a:prepend
        let a:dict.options = extend(copy(a:eopts), a:dict.options)
      else
        call extend(a:dict.options, a:eopts)
      endif
    else
      let all_opts = a:prepend ? [a:eopts, a:dict.options] : [a:dict.options, a:eopts]
      let a:dict.options = join(map(all_opts, 'type(v:val) == s:TYPE.list ? join(map(copy(v:val), "fzf#shellescape(v:val)")) : v:val'))
    endif
  else
    let a:dict.options = a:eopts
  endif
endfunction

function! s:merge_opts(dict, eopts)
  return s:extend_opts(a:dict, a:eopts, 0)
endfunction

function! s:prepend_opts(dict, eopts)
  return s:extend_opts(a:dict, a:eopts, 1)
endfunction

" [spec to wrap], [preview window expression], [toggle-preview keys...]
function! fzf#vim#with_preview(...)
  " Default spec
  let spec = {}
  let window = ''

  let args = copy(a:000)

  " Spec to wrap
  if len(args) && type(args[0]) == s:TYPE.dict
    let spec = copy(args[0])
    call remove(args, 0)
  endif

  if !executable(s:bash())
    return spec
  endif

  " Placeholder expression (TODO/TBD: undocumented)
  let placeholder = get(spec, 'placeholder', '{}')

  " g:fzf_preview_window
  if empty(args)
    let preview_args = s:conf('preview_window', ['', 'ctrl-/'])
    if empty(preview_args)
      let args = ['hidden']
    else
      " For backward-compatiblity
      let args = type(preview_args) == type('') ? [preview_args] : copy(preview_args)
    endif
  endif

  if len(args) && type(args[0]) == s:TYPE.string
    if len(args[0]) && args[0] !~# '^\(up\|down\|left\|right\|hidden\)'
      throw 'invalid preview window: '.args[0]
    endif
    let window = args[0]
    call remove(args, 0)
  endif

  let preview = []
  if len(window)
    let preview += ['--preview-window', window]
  endif
  if s:is_win
    if empty($MSWINHOME)
      let $MSWINHOME = $HOME
    endif
    if s:is_wsl_bash && $WSLENV !~# '[:]\?MSWINHOME\(\/[^:]*\)\?\(:\|$\)'
      let $WSLENV = 'MSWINHOME/u:'.$WSLENV
    endif
  endif
  let preview_cmd = s:bash() . ' ' . s:escape_for_bash(s:bin.preview)
  if len(placeholder)
    let preview += ['--preview', preview_cmd.' '.placeholder]
  end
  if &ambiwidth ==# 'double'
    let preview += ['--no-unicode']
  end

  if len(args)
    call extend(preview, ['--bind', join(map(args, 'v:val.":toggle-preview"'), ',')])
  endif
  call s:merge_opts(spec, preview)
  return spec
endfunction

function! s:remove_layout(opts)
  for key in s:layout_keys
    if has_key(a:opts, key)
      call remove(a:opts, key)
    endif
  endfor
  return a:opts
endfunction

function! s:reverse_list(opts)
  let tokens = map(split($FZF_DEFAULT_OPTS, '[^a-z-]'), 'substitute(v:val, "^--", "", "")')
  if index(tokens, 'reverse') < 0
    return extend(['--layout=reverse-list'], a:opts)
  endif
  return a:opts
endfunction

function! s:wrap(name, opts, bang)
  " fzf#wrap does not append --expect if sink or sink* is found
  let opts = copy(a:opts)
  let options = ''
  if has_key(opts, 'options')
    let options = type(opts.options) == s:TYPE.list ? join(opts.options) : opts.options
  endif
  if options !~ '--expect' && has_key(opts, 'sink*')
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

function! s:rstrip(str)
  return substitute(a:str, '\s*$', '', 'g')
endfunction

function! s:chomp(str)
  return substitute(a:str, '\n*$', '', 'g')
endfunction

function! s:escape(path)
  let path = fnameescape(a:path)
  return s:is_win ? escape(path, '$') : path
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
  let color = (empty(fg) ? s:ansi[a:default] : s:csi(fg, 1)) .
        \ (empty(bg) ? '' : ';'.s:csi(bg, 0))
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
  call s:check_requirements()

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

  let extra  = copy(extra)
  let eopts  = has_key(extra, 'options') ? remove(extra, 'options') : ''
  let merged = extend(copy(a:opts), extra)
  call s:merge_opts(merged, eopts)
  return fzf#run(s:wrap(a:name, merged, bang))
endfunction

let s:default_action = {
  \ 'ctrl-t': 'tab split',
  \ 'ctrl-x': 'split',
  \ 'ctrl-v': 'vsplit' }

function! s:execute_silent(cmd)
  silent keepjumps keepalt execute a:cmd
endfunction

" [key, [filename, [stay_on_edit: 0]]]
function! s:action_for(key, ...)
  let Cmd = get(get(g:, 'fzf_action', s:default_action), a:key, '')
  let cmd = type(Cmd) == s:TYPE.string ? Cmd : ''

  " See If the command is the default action that opens the selected file in
  " the current window. i.e. :edit
  let edit = stridx('edit', cmd) == 0 " empty, e, ed, ..

  " If no extra argument is given, we just execute the command and ignore
  " errors. e.g. E471: Argument required: tab drop
  if !a:0
    if !edit
      normal! m'
      silent! call s:execute_silent(cmd)
    endif
  else
    " For the default edit action, we don't execute the action if the
    " selected file is already opened in the current window, or we are
    " instructed to stay on the current buffer.
    let stay = edit && (a:0 > 1 && a:2 || fnamemodify(a:1, ':p') ==# expand('%:p'))
    if !stay
      normal! m'
      call s:execute_silent((len(cmd) ? cmd : 'edit').' '.s:escape(a:1))
    endif
  endif
endfunction

function! s:open(target)
  if fnamemodify(a:target, ':p') ==# expand('%:p')
    return
  endif
  execute 'edit' s:escape(a:target)
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

function! s:fill_quickfix(name, list)
  if len(a:list) > 1
    let Handler = s:conf('listproc_'.a:name, s:conf('listproc', function('fzf#vim#listproc#quickfix')))
    call call(Handler, [a:list], {})
    return 1
  endif
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
  let short = fnamemodify(getcwd(), ':~:.')
  if !has('win32unix')
    let short = pathshorten(short)
  endif
  let slash = (s:is_win && !&shellslash) ? '\' : '/'
  return empty(short) ? '~'.slash : short . (short =~ escape(slash, '\').'$' ? '' : slash)
endfunction

function! fzf#vim#files(dir, ...)
  let args = {}
  if !empty(a:dir)
    if !isdirectory(expand(a:dir))
      return s:warn('Invalid directory')
    endif
    let slash = (s:is_win && !&shellslash) ? '\\' : '/'
    let dir = substitute(a:dir, '[/\\]*$', slash, '')
    let args.dir = dir
  else
    let dir = s:shortpath()
  endif

  let args.options = ['-m', '--prompt', strwidth(dir) < &columns / 2 - 20 ? dir : '> ']
  call s:merge_opts(args, s:conf('files_options', []))
  return s:fzf('files', args, a:000)
endfunction

" ------------------------------------------------------------------
" Lines
" ------------------------------------------------------------------
function! s:line_handler(lines)
  if len(a:lines) < 2
    return
  endif

  let qfl = []
  for line in a:lines[1:]
    let chunks = split(line, "\t", 1)
    call add(qfl, {'bufnr': str2nr(chunks[0]), 'lnum': str2nr(chunks[2]), 'text': join(chunks[3:], "\t")})
  endfor

  call s:action_for(a:lines[0])
  if !s:fill_quickfix('lines', qfl)
    let chunks = split(a:lines[1], '\t')
    execute 'buffer' chunks[0]
    execute chunks[2]
  endif
  normal! ^zvzz
endfunction

function! fzf#vim#_lines(all)
  let cur = []
  let rest = []
  let buf = bufnr('')
  let longest_name = 0
  let display_bufnames = &columns > s:wide
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
        let bufname = '…' . bufname[-len_bufnames+1:]
      endif
      let bufname = printf(s:green("%".len_bufnames."s", "Directory"), bufname)
    else
      let bufname = ''
    endif
    let linefmt = s:blue("%2d\t", "TabLine")."%s".s:yellow("\t%4d ", "LineNr")."\t%s"
    call extend(b == buf ? cur : rest,
    \ filter(
    \   map(lines,
    \       '(!a:all && empty(v:val)) ? "" : printf(linefmt, b, bufname, v:key + 1, v:val)'),
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
  \ 'options': s:reverse_list(['--tiebreak=index', '--prompt', 'Lines> ', '--ansi', '--extended', '--nth='.nth.'..', '--tabstop=1', '--query', query, '--multi'])
  \}, args)
endfunction

" ------------------------------------------------------------------
" BLines
" ------------------------------------------------------------------
function! s:buffer_line_handler(lines)
  if len(a:lines) < 2
    return
  endif
  let qfl = []
  for line in a:lines[1:]
    let chunks = split(line, "\t", 1)
    let ln = chunks[0]
    let ltxt = join(chunks[1:], "\t")
    call add(qfl, {'filename': expand('%'), 'lnum': str2nr(ln), 'text': ltxt})
  endfor
  call s:action_for(a:lines[0])
  if !s:fill_quickfix('blines', qfl)
    execute split(a:lines[1], '\t')[0]
  endif
  normal! ^zvzz
endfunction

function! s:buffer_lines(query)
  let linefmt = s:yellow(" %4d ", "LineNr")."\t%s"
  let fmtexpr = 'printf(linefmt, v:key + 1, v:val)'
  let lines = getline(1, '$')
  if empty(a:query)
    return map(lines, fmtexpr)
  end
  return filter(map(lines, 'v:val =~ a:query ? '.fmtexpr.' : ""'), 'len(v:val)')
endfunction

function! fzf#vim#buffer_lines(...)
  let [query, args] = (a:0 && type(a:1) == type('')) ?
        \ [a:1, a:000[1:]] : ['', a:000]
  return s:fzf('blines', {
  \ 'source':  s:buffer_lines(query),
  \ 'sink*':   s:function('s:buffer_line_handler'),
  \ 'options': s:reverse_list(['+m', '--tiebreak=index', '--multi', '--prompt', 'BLines> ', '--ansi', '--extended', '--nth=2..', '--tabstop=1'])
  \}, args)
endfunction

" ------------------------------------------------------------------
" Colors
" ------------------------------------------------------------------
function! fzf#vim#colors(...)
  let colors = split(globpath(&rtp, "colors/*.vim"), "\n")
  if has('packages')
    let colors += split(globpath(&packpath, "pack/*/opt/*/colors/*.vim"), "\n")
  endif
  return s:fzf('colors', {
  \ 'source':  fzf#vim#_uniq(map(colors, "substitute(fnamemodify(v:val, ':t'), '\\..\\{-}$', '', '')")),
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
function! fzf#vim#_recent_files()
  return fzf#vim#_uniq(map(
    \ filter([expand('%')], 'len(v:val)')
    \   + filter(map(fzf#vim#_buflisted_sorted(), 'bufname(v:val)'), 'len(v:val)')
    \   + filter(copy(v:oldfiles), "filereadable(fnamemodify(v:val, ':p'))"),
    \ 'fnamemodify(v:val, ":~:.")'))
endfunction

function! s:history_source(type)
  let max = histnr(a:type)
  if max <= 0
    return ['No entries']
  endif
  let fmt = s:yellow(' %'.len(string(max)).'d ', 'Number')
  let list = filter(map(range(1, max), 'histget(a:type, - v:val)'), '!empty(v:val)')
  return extend([' :: Press '.s:magenta('CTRL-E', 'Special').' to edit'],
    \ map(list, 'printf(fmt, len(list) - v:key)." ".v:val'))
endfunction

nnoremap <plug>(-fzf-vim-do) :execute g:__fzf_command<cr>
nnoremap <plug>(-fzf-/) /
nnoremap <plug>(-fzf-:) :

function! s:history_sink(type, lines)
  if len(a:lines) < 2
    return
  endif

  let prefix = "\<plug>(-fzf-".a:type.')'
  let key  = a:lines[0]
  let item = matchstr(a:lines[1], ' *[0-9]\+ *\zs.*')
  if key == 'ctrl-e'
    call histadd(a:type, item)
    redraw
    call feedkeys(a:type."\<up>", 'n')
  else
    if a:type == ':'
      call histadd(a:type, item)
    endif
    let g:__fzf_command = "normal ".prefix.item."\<cr>"
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
  \ 'source':  fzf#vim#_recent_files(),
  \ 'options': ['-m', '--header-lines', !empty(expand('%')), '--prompt', 'Hist> ']
  \}, a:000)
endfunction

" ------------------------------------------------------------------
" GFiles[?]
" ------------------------------------------------------------------

function! s:get_git_root(dir)
  let dir = len(a:dir) ? a:dir : substitute(split(expand('%:p:h'), '[/\\]\.git\([/\\]\|$\)')[0], '^fugitive://', '', '')
  let root = systemlist('git -C ' . fzf#shellescape(dir) . ' rev-parse --show-toplevel')[0]
  return v:shell_error ? '' : (len(a:dir) ? fnamemodify(a:dir, ':p') : root)
endfunction

function! s:version_requirement(val, min)
  for idx in range(0, len(a:min) - 1)
    let v = get(a:val, idx, 0)
    if     v < a:min[idx] | return 0
    elseif v > a:min[idx] | return 1
    endif
  endfor
  return 1
endfunction

function! s:git_version_requirement(...)
  if !exists('s:git_version')
    let s:git_version = map(split(split(system('git --version'))[2], '\.'), 'str2nr(v:val)')
  endif
  return s:version_requirement(s:git_version, a:000)
endfunction

function! fzf#vim#gitfiles(args, ...)
  let dir = get(get(a:, 1, {}), 'dir', '')
  let root = s:get_git_root(dir)
  if empty(root)
    return s:warn('Not in git repo')
  endif
  let prefix = 'git -C ' . fzf#shellescape(root) . ' '
  if a:args != '?'
    let source = prefix . 'ls-files -z ' . a:args
    if s:git_version_requirement(2, 31)
      let source .= ' --deduplicate'
    endif
    return s:fzf('gfiles', {
    \ 'source':  source,
    \ 'dir':     root,
    \ 'options': '-m --read0 --prompt "GitFiles> "'
    \}, a:000)
  endif

  " Here be dragons!
  " We're trying to access the common sink function that fzf#wrap injects to
  " the options dictionary.
  let bar = s:is_win ? '^|' : '|'
  let diff_prefix = 'git -C ' . s:escape_for_bash(root) . ' '
  let preview = printf(
    \ s:bash() . ' -c "if [[ {1} =~ M ]]; then %s; else %s {-1}; fi"',
    \ executable('delta')
      \ ? diff_prefix . 'diff -- {-1} ' . bar . ' delta --width $FZF_PREVIEW_COLUMNS --file-style=omit ' . bar . ' sed 1d'
      \ : diff_prefix . 'diff --color=always -- {-1} ' . bar . ' sed 1,4d',
    \ s:escape_for_bash(s:bin.preview))
  let wrapped = fzf#wrap({
  \ 'source':  prefix . '-c color.status=always status --short --untracked-files=all',
  \ 'dir':     root,
  \ 'options': ['--ansi', '--multi', '--nth', '2..,..', '--tiebreak=index', '--prompt', 'GitFiles?> ', '--preview', preview]
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
  execute a:t.'tabnext'
  execute a:w.'wincmd w'
endfunction

function! s:bufopen(lines)
  if len(a:lines) < 2
    return
  endif
  let b = matchstr(a:lines[1], '\[\zs[0-9]*\ze\]')
  if empty(a:lines[0]) && s:conf('buffers_jump', 0)
    let [t, w] = s:find_open_window(b)
    if t
      call s:jump(t, w)
      return
    endif
  endif
  call s:action_for(a:lines[0])
  execute 'buffer' b
endfunction

function! fzf#vim#_format_buffer(b)
  let name = bufname(a:b)
  let line = exists('*getbufinfo') ? getbufinfo(a:b)[0]['lnum'] : 0
  let fullname = empty(name) ? '' : fnamemodify(name, ":p:~:.")
  let dispname = empty(name) ? '[No Name]' : name
  let flag = a:b == bufnr('')  ? s:blue('%', 'Conditional') :
          \ (a:b == bufnr('#') ? s:magenta('#', 'Special') : ' ')
  let modified = getbufvar(a:b, '&modified') ? s:red(' [+]', 'Exception') : ''
  let readonly = getbufvar(a:b, '&modifiable') ? '' : s:green(' [RO]', 'Constant')
  let extra = join(filter([modified, readonly], '!empty(v:val)'), '')
  let target = empty(name) ? '' : (line == 0 ? fullname : fullname.':'.line)
  return s:rstrip(printf("%s\t%d\t[%s] %s\t%s\t%s", target, line, s:yellow(a:b, 'Number'), flag, dispname, extra))
endfunction

function! s:sort_buffers(...)
  let [b1, b2] = map(copy(a:000), 'get(g:fzf#vim#buffers, v:val, v:val)')
  " Using minus between a float and a number in a sort function causes an error
  return b1 < b2 ? 1 : -1
endfunction

function! fzf#vim#_buflisted_sorted()
  return sort(s:buflisted(), 's:sort_buffers')
endfunction

" [query (string)], [bufnrs (list)], [spec (dict)], [fullscreen (bool)]
function! fzf#vim#buffers(...)
  let [query, args] = (a:0 && type(a:1) == type('')) ?
        \ [a:1, a:000[1:]] : ['', a:000]
  if len(args) && type(args[0]) == s:TYPE.list
    let [buffers; args] = args
  else
    let buffers = s:buflisted()
  endif
  let sorted = sort(buffers, 's:sort_buffers')
  let header_lines = '--header-lines=' . (bufnr('') == get(sorted, 0, 0) ? 1 : 0)
  let tabstop = len(max(sorted)) >= 4 ? 9 : 8
  return s:fzf('buffers', {
  \ 'source':  map(sorted, 'fzf#vim#_format_buffer(v:val)'),
  \ 'sink*':   s:function('s:bufopen'),
  \ 'options': ['+m', '-x', '--tiebreak=index', header_lines, '--ansi', '-d', '\t', '--with-nth', '3..', '-n', '2,1..2', '--prompt', 'Buf> ', '--query', query, '--preview-window', '+{2}-/2', '--tabstop', tabstop]
  \}, args)
endfunction

" ------------------------------------------------------------------
" Ag / Rg
" ------------------------------------------------------------------
function! s:ag_to_qf(line)
  let parts = matchlist(a:line, '\(.\{-}\)\s*:\s*\(\d\+\)\%(\s*:\s*\(\d\+\)\)\?\%(\s*:\(.*\)\)\?')
  let dict = {'filename': &acd ? fnamemodify(parts[1], ':p') : parts[1], 'lnum': parts[2], 'text': parts[4]}
  if len(parts[3])
    let dict.col = parts[3]
  endif
  return dict
endfunction

function! s:ag_handler(name, lines)
  if len(a:lines) < 2
    return
  endif

  let list = map(filter(a:lines[1:], 'len(v:val)'), 's:ag_to_qf(v:val)')
  if empty(list)
    return
  endif

  call s:action_for(a:lines[0], list[0].filename, len(list) > 1)
  if s:fill_quickfix(a:name, list)
    return
  endif

  " Single item selected
  let first = list[0]
  try
    execute first.lnum
    if has_key(first, 'col')
      call cursor(0, first.col)
    endif
    normal! zvzz
  catch
  endtry
endfunction

" query, [ag options], [spec (dict)], [fullscreen (bool)]
function! fzf#vim#ag(query, ...)
  if type(a:query) != s:TYPE.string
    return s:warn('Invalid query argument')
  endif
  let query = empty(a:query) ? '^(?=.)' : a:query
  let args = copy(a:000)
  let ag_opts = len(args) > 1 && type(args[0]) == s:TYPE.string ? remove(args, 0) : ''
  let command = ag_opts . ' -- ' . fzf#shellescape(query)
  return call('fzf#vim#ag_raw', insert(args, command, 0))
endfunction

" ag command suffix, [spec (dict)], [fullscreen (bool)]
function! fzf#vim#ag_raw(command_suffix, ...)
  if !executable('ag')
    return s:warn('ag is not found')
  endif
  return call('fzf#vim#grep', extend(['ag --nogroup --column --color '.a:command_suffix, 1], a:000))
endfunction

" command (string), [spec (dict)], [fullscreen (bool)]
function! fzf#vim#grep(grep_command, ...)
  let args = copy(a:000)
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
  let opts = {
  \ 'options': ['--ansi', '--prompt', capname.'> ',
  \             '--multi', '--bind', 'alt-a:select-all,alt-d:deselect-all',
  \             '--delimiter', ':', '--preview-window', '+{2}-/2']
  \}
  if len(args) && type(args[0]) == s:TYPE.bool
    call remove(args, 0)
  endif

  function! opts.sink(lines) closure
    return s:ag_handler(get(opts, 'name', name), a:lines)
  endfunction
  let opts['sink*'] = remove(opts, 'sink')
  try
    let prev_default_command = $FZF_DEFAULT_COMMAND
    let $FZF_DEFAULT_COMMAND = a:grep_command
    return s:fzf(name, opts, args)
  finally
    let $FZF_DEFAULT_COMMAND = prev_default_command
  endtry
endfunction


" command_prefix (string), initial_query (string), [spec (dict)], [fullscreen (bool)]
function! fzf#vim#grep2(command_prefix, query, ...)
  let args = copy(a:000)
  let words = []
  for word in split(a:command_prefix)
    if word !~# '^[a-z]'
      break
    endif
    call add(words, word)
  endfor
  let words = empty(words) ? ['grep'] : words
  let name = join(words, '-')
  let opts = {
  \ 'source': ':',
  \ 'options': ['--ansi', '--prompt', toupper(name).'> ', '--query', a:query,
  \             '--disabled',
  \             '--bind', 'start:reload:'.a:command_prefix.' '.fzf#shellescape(a:query),
  \             '--bind', 'change:reload:'.a:command_prefix.' {q} || :',
  \             '--multi', '--bind', 'alt-a:select-all,alt-d:deselect-all',
  \             '--delimiter', ':', '--preview-window', '+{2}-/2']
  \}
  if len(args) && type(args[0]) == s:TYPE.bool
    call remove(args, 0)
  endif
  function! opts.sink(lines) closure
    return s:ag_handler(name, a:lines)
  endfunction
  let opts['sink*'] = remove(opts, 'sink')
  return s:fzf(name, opts, args)
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
    if !v:shell_error && len(lines)
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
  call s:action_for(a:lines[0])
  let qfl = []
  for line in a:lines[1:]
    call s:execute_silent(split(line, "\t")[2])
    call add(qfl, {'filename': expand('%'), 'lnum': line('.'), 'text': getline('.')})
  endfor

  if len(qfl) > 1
    " Go back to the original position
    normal! g`'
    " Because 'listproc' will use 'cfirst' to go to the first item in the list
    call s:fill_quickfix('btags', qfl)
  else
    normal! zvzz
  endif
endfunction

" query, [tag commands], [spec (dict)], [fullscreen (bool)]
function! fzf#vim#buffer_tags(query, ...)
  let args = copy(a:000)
  let escaped = fzf#shellescape(expand('%'))
  let null = s:is_win ? 'nul' : '/dev/null'
  let sort = has('unix') && !has('win32unix') && executable('sort') ? '| sort -s -k 5' : ''
  let tag_cmds = (len(args) > 1 && type(args[0]) != type({})) ? remove(args, 0) : [
    \ printf('ctags -f - --sort=yes --excmd=number --language-force=%s %s 2> %s %s', get({ 'cpp': 'c++' }, &filetype, &filetype), escaped, null, sort),
    \ printf('ctags -f - --sort=yes --excmd=number %s 2> %s %s', escaped, null, sort)]
  if type(tag_cmds) != type([])
    let tag_cmds = [tag_cmds]
  endif
  try
    return s:fzf('btags', {
    \ 'source':  s:btags_source(tag_cmds),
    \ 'sink*':   s:function('s:btags_sink'),
    \ 'options': s:reverse_list(['-m', '-d', '\t', '--with-nth', '1,4..', '-n', '1', '--prompt', 'BTags> ', '--query', a:query, '--preview-window', '+{3}-/2'])}, args)
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

  " Remember the current position
  let buf = bufnr()
  let view = winsaveview()

  let qfl = []
  let [key; list] = a:lines

  try
    let [magic, &magic, wrapscan, &wrapscan, acd, &acd] = [&magic, 0, &wrapscan, 1, &acd, 0]
    for line in list
      try
        let parts   = split(line, '\t\zs')
        let excmd   = matchstr(join(parts[2:-2], '')[:-2], '^.\{-}\ze;\?"\t')
        let base    = fnamemodify(parts[-1], ':h')
        let relpath = parts[1][:-2]
        let abspath = relpath =~ (s:is_win ? '^[A-Z]:\' : '^/') ? relpath : join([base, relpath], '/')

        if len(list) == 1
          call s:action_for(key, expand(abspath, 1))
        else
          call s:open(expand(abspath, 1))
        endif
        call s:execute_silent(excmd)
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
    " Go back to the original position. Because 'listproc' will use 'cfirst'
    " to go to the first item in the list.
    call s:execute_silent('b '.buf)
    call winrestview(view)

    " However, if a non-default action is triggered, we need to open the first
    " entry using the action, to be as backward compatible as possible.
    call s:action_for(key, qfl[0].filename, 1)

    call s:fill_quickfix('tags', qfl)
  else
    normal! ^zvzz
  endif
endfunction

function! fzf#vim#tags(query, ...)
  if !executable('perl')
    return s:warn('Tags command requires perl')
  endif
  if empty(tagfiles())
    call inputsave()
    echohl WarningMsg
    let gen = input('tags not found. Generate? (y/N) ')
    echohl None
    call inputrestore()
    redraw
    if gen =~? '^y'
      call s:warn('Preparing tags')
      call system(s:conf('tags_command', 'ctags -R'.(s:is_win ? ' --output-format=e-ctags' : '')))
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
  let opts = v2_limit < 0 ? ['--algo=v1'] : []

  return s:fzf('tags', {
  \ 'source':  'perl '.fzf#shellescape(s:bin.tags).' '.join(map(tagfiles, 'fzf#shellescape(fnamemodify(v:val, ":p"))')),
  \ 'sink*':   s:function('s:tags_sink'),
  \ 'options': extend(opts, ['--nth', '1..2', '-m', '-d', '\t', '--tiebreak=begin', '--prompt', 'Tags> ', '--query', a:query])}, a:000)
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
  \ 'options': '--ansi --tiebreak=index +m -n 1,.. -d "\t"',
  \ 'sink':    s:function('s:inject_snippet')}, a:000)
endfunction

" ------------------------------------------------------------------
" Commands
" ------------------------------------------------------------------
let s:nbs = nr2char(0xa0)

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
    call feedkeys(':'.cmd.(a:lines[1][0] == '!' ? '' : ' '), 'n')
  else
    call feedkeys(':'.cmd."\<cr>", 'n')
  endif
endfunction

let s:fmt_excmd = '   '.s:blue('%-38s', 'Statement').'%s'

function! s:format_excmd(ex)
  let match = matchlist(a:ex, '^|:\(\S\+\)|\s*\S*\(.*\)')
  return printf(s:fmt_excmd, s:nbs.match[1].s:nbs, s:strip(match[2]))
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
  \ 'options': '--ansi --expect '.s:conf('commands_expect', 'ctrl-x').
  \            ' --tiebreak=index --header-lines 1 -x --prompt "Commands> " -n2,3,2..3 -d'.s:nbs}, a:000)
endfunction

" ------------------------------------------------------------------
" Changes
" ------------------------------------------------------------------

function! s:format_change(bufnr, offset, item)
  return printf("%3d  %s  %4d  %3d  %s", a:bufnr, s:yellow(printf('%6s', a:offset)), a:item.lnum, a:item.col, getbufline(a:bufnr, a:item.lnum)[0])
endfunction

function! s:changes_sink(lines)
  if len(a:lines) < 2
    return
  endif

  call s:action_for(a:lines[0])
  let [b, o, l, c] = split(a:lines[1])[0:3]

  if o == '-'
    execute 'buffer' b
    call cursor(l, c)
  elseif o[0] == '+'
    execute 'normal!' o[1:].'g,'
  else
    execute 'normal!' o.'g;'
  endif
endfunction

function! s:format_change_offset(current, index, cursor)
  if !a:current
    return '-'
  endif

  let offset = a:index - a:cursor + 1
  if offset < 0
    return '+'.-offset
  endif
  return offset
endfunction

function! fzf#vim#changes(...)
  let all_changes = ["buf  offset  line  col  text"]
  let cursor = 0
  for bufnr in fzf#vim#_buflisted_sorted()
    let [changes, position_or_length] = getchangelist(bufnr)
    let current = bufnr() == bufnr
    if current
      let cursor = len(changes) - position_or_length
    endif
    let all_changes += map(reverse(changes), { idx, val -> s:format_change(bufnr, s:format_change_offset(current, idx, cursor), val) })
  endfor

  return s:fzf('changes', {
  \ 'source':  all_changes,
  \ 'sink*':   s:function('s:changes_sink'),
  \ 'options': printf('+m -x --ansi --tiebreak=index --header-lines=1 --cycle --scroll-off 999 --sync --bind start:pos:%d --prompt "Changes> "', cursor)}, a:000)
endfunction

" ------------------------------------------------------------------
" Marks
" ------------------------------------------------------------------
function! s:format_mark(line)
  return substitute(a:line, '\S', '\=s:yellow(submatch(0), "Number")', '')
endfunction

function! s:mark_sink(lines)
  if len(a:lines) < 2
    return
  endif
  call s:action_for(a:lines[0])
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
" Jumps
" ------------------------------------------------------------------
function! s:jump_format(line)
  return substitute(a:line, '[0-9]\+', '\=s:yellow(submatch(0), "Number")', '')
endfunction

function! s:jump_sink(lines)
  if len(a:lines) < 2
    return
  endif
  call s:action_for(a:lines[0])
  let idx = index(s:jumplist, a:lines[1])
  if idx == -1
    return
  endif
  let current = match(s:jumplist, '\v^\s*\>')
  let delta = idx - current
  if delta < 0
    execute 'normal! ' . -delta . "\<C-O>"
  else
    execute 'normal! ' . delta . "\<C-I>"
  endif
endfunction

function! fzf#vim#jumps(...)
  redir => cout
  silent jumps
  redir END
  let s:jumplist = split(cout, '\n')
  let current = -match(s:jumplist, '\v^\s*\>')
  return s:fzf('jumps', {
  \ 'source'  : extend(s:jumplist[0:0], map(s:jumplist[1:], 's:jump_format(v:val)')),
  \ 'sink*'   : s:function('s:jump_sink'),
  \ 'options' : '+m -x --ansi --tiebreak=index --cycle --scroll-off 999 --sync --bind start:pos:'.current.' --tac --header-lines 1 --tiebreak=begin --prompt "Jumps> "',
  \ }, a:000)
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
  if !executable('perl')
    return s:warn('Helptags command requires perl')
  endif
  let sorted = sort(split(globpath(&runtimepath, 'doc/tags', 1), '\n'))
  let tags = exists('*uniq') ? uniq(sorted) : fzf#vim#_uniq(sorted)

  if exists('s:helptags_script')
    silent! call delete(s:helptags_script)
  endif
  let s:helptags_script = tempname()

  call writefile(['use Fatal qw(open close); for my $filename (@ARGV) { open(my $file,q(<),$filename); while (<$file>) { /(.*?)\t(.*?)\t(.*)/; push @lines, sprintf(qq('.s:green('%-40s', 'Label').'\t%s\t%s\t%s\n), $1, $2, $filename, $3); } close($file); } print for sort @lines;'], s:helptags_script)
  return s:fzf('helptags', {
  \ 'source': 'perl '.fzf#shellescape(s:helptags_script).' '.join(map(tags, 'fzf#shellescape(v:val)')),
  \ 'sink':    s:function('s:helptag_sink'),
  \ 'options': ['--ansi', '+m', '--tiebreak=begin', '--with-nth', '..3']}, a:000)
endfunction

" ------------------------------------------------------------------
" File types
" ------------------------------------------------------------------
function! fzf#vim#filetypes(...)
  return s:fzf('filetypes', {
  \ 'source':  fzf#vim#_uniq(sort(map(split(globpath(&rtp, 'syntax/*.vim'), '\n'),
  \            'fnamemodify(v:val, ":t:r")'))),
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
  let name = empty(name) ? s:nbs.s:nbs.'[No Name]' : ' '.s:nbs.name
  let active = tabpagewinnr(a:tab) == a:win
  return (active? s:blue('>', 'Operator') : ' ') . name . s:nbs . (modified? s:red(' [+]', 'Exception') : '')
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
  \ 'source':  extend(['Tab Win     Name'], lines),
  \ 'sink':    s:function('s:windows_sink'),
  \ 'options': '+m --ansi --tiebreak=begin --header-lines=1 -d'.s:nbs}, a:000)
endfunction

" ------------------------------------------------------------------
" Commits / BCommits
" ------------------------------------------------------------------
function! s:yank_to_register(data)
  let @" = a:data
  silent! let @* = a:data
  silent! let @+ = a:data
endfunction

function! s:commits_sink(lines)
  if len(a:lines) < 2
    return
  endif

  let pat = '[0-9a-f]\{7,40}'

  if a:lines[0] == 'ctrl-y'
    let hashes = join(filter(map(a:lines[1:], 'matchstr(v:val, pat)'), 'len(v:val)'))
    return s:yank_to_register(hashes)
  end

  let diff = a:lines[0] == 'ctrl-d'
  let Cmd = get(get(g:, 'fzf_action', s:default_action), a:lines[0], '')
  let cmd = type(Cmd) == s:TYPE.string ? Cmd : ''

  let buf = bufnr('')
  for idx in range(1, len(a:lines) - 1)
    let sha = matchstr(a:lines[idx], pat)
    if !empty(sha)
      if diff
        if idx > 1
          execute 'tab sb' buf
        endif
        execute 'Gdiff' sha
      else
        " Since fugitive buffers are unlisted, we can't keep using 'e'
        let c = empty(cmd) ? (idx == 1 ? 'edit' : 'tab split') : cmd
        execute c FugitiveFind(sha)
      endif
    endif
  endfor
endfunction

function! s:commits(range, buffer_local, args)
  let s:git_root = s:get_git_root('')
  if empty(s:git_root)
    return s:warn('Not in git repository')
  endif

  let prefix = 'git -C ' . fzf#shellescape(s:git_root) . ' '
  let source = prefix . 'log '.s:conf('commits_log_options', '--color=always '.fzf#shellescape('--format=%C(auto)%h%d %s %C(green)%cr'))
  let current = expand('%:p')
  let managed = 0
  if !empty(current)
    call system(prefix . 'show '.fzf#shellescape(current).' 2> '.(s:is_win ? 'nul' : '/dev/null'))
    let managed = !v:shell_error
  endif

  let args = copy(a:args)
  let log_opts = len(args) && type(args[0]) == type('') ? remove(args, 0) : ''

  if len(a:range) || a:buffer_local
    if !managed
      return s:warn('The current buffer is not in the working tree')
    endif
    let source .= len(a:range)
      \ ? join([printf(' -L %d,%d:%s --no-patch', a:range[0], a:range[1], fzf#shellescape(current)), log_opts])
      \ : join([' --follow', log_opts, fzf#shellescape(current)])
    let command = 'BCommits'
  else
    let source .= join([' --graph', log_opts])
    let command = 'Commits'
  endif

  let expect_keys = join(keys(get(g:, 'fzf_action', s:default_action)), ',')
  let options = {
  \ 'source':  source,
  \ 'sink*':   s:function('s:commits_sink'),
  \ 'options': s:reverse_list(['--ansi', '--multi', '--tiebreak=index',
  \   '--inline-info', '--prompt', command.'> ', '--bind=ctrl-s:toggle-sort',
  \   '--header', ':: Press '.s:magenta('CTRL-S', 'Special').' to toggle sort, '.s:magenta('CTRL-Y', 'Special').' to yank commit hashes',
  \   '--expect=ctrl-y,'.expect_keys])
  \ }

  if a:buffer_local
    let options.options[-2] .= ', '.s:magenta('CTRL-D', 'Special').' to diff'
    let options.options[-1] .= ',ctrl-d'
  endif

  if !s:is_win && &columns > s:wide
    let suffix = executable('delta') ? '| delta --width $FZF_PREVIEW_COLUMNS' : ''
    let orderfile = tempname()
    call writefile([current[len(s:git_root)+1:]], orderfile)
    call extend(options.options,
    \ ['--preview', 'echo {} | grep -o "[a-f0-9]\{7,\}" | head -1 | xargs ' . prefix . 'show -O'.fzf#shellescape(orderfile).' --format=format: --color=always ' . suffix])
  endif

  return s:fzf(a:buffer_local ? 'bcommits' : 'commits', options, args)
endfunction

" Heuristically determine if the user specified a range
function! s:given_range(line1, line2)
  " 1. From visual mode
  "   :'<,'>Commits
  " 2. From command-line
  "   :10,20Commits
  if a:line1 == line("'<") && a:line2 == line("'>") ||
        \ (a:line1 != 1 || a:line2 != line('$'))
    return [a:line1, a:line2]
  endif

  return []
endfunction

" [git-log-args], [spec (dict)], [fullscreen (bool)]
function! fzf#vim#commits(...) range
  if exists('b:fzf_winview')
    call winrestview(b:fzf_winview)
    unlet b:fzf_winview
  endif
  return s:commits(s:given_range(a:firstline, a:lastline), 0, a:000)
endfunction

" [git-log-args], [spec (dict)], [fullscreen (bool)]
function! fzf#vim#buffer_commits(...) range
  if exists('b:fzf_winview')
    call winrestview(b:fzf_winview)
    unlet b:fzf_winview
  endif
  return s:commits(s:given_range(a:firstline, a:lastline), 1, a:000)
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
      let src = "\t".substitute(matchstr(line, '/\zs[^/\\]*\ze$'), ' [^ ]* ', ':', '')
      call add(list, printf('%s %s', curr, s:green(src, 'Comment')))
      let curr = ''
    else
      if !empty(curr)
        call add(list, curr)
      endif
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
  call s:prepend_opts(opts, ['+m', '-q', s:query])
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
  elseif has('nvim')
    execute "normal! \<esc>la"
  else
    call feedkeys("\<Plug>(-fzf-complete-finish)")
  endif
endfunction

nnoremap <silent> <Plug>(-fzf-complete-finish) a
inoremap <silent> <Plug>(-fzf-complete-finish) <c-o>l

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
    let s:opts = fzf#wrap()
  elseif type(a:1) == s:TYPE.dict
    let s:opts = copy(a:1)
  elseif type(a:1) == s:TYPE.string
    let s:opts = extend({'source': a:1}, get(a:000, 1, fzf#wrap()))
  else
    echoerr 'Invalid argument: '.string(a:000)
    return ''
  endif
  for s in ['sink', 'sink*']
    if has_key(s:opts, s)
      call remove(s:opts, s)
    endif
  endfor

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
    call s:merge_opts(s:opts, remove(s:opts, 'extra_options'))
  endif
  if has_key(s:opts, 'options')
    if type(s:opts.options) == s:TYPE.list
      call add(s:opts.options, '--no-expect')
    else
      let s:opts.options .= ' --no-expect'
    endif
  endif

  call feedkeys("\<Plug>(-fzf-complete-trigger)")
  return ''
endfunction

" ------------------------------------------------------------------
let &cpo = s:cpo_save
unlet s:cpo_save
