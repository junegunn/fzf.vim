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
  return escape(a:path, ' %#''"\')
endfunction

function! s:ansi(str, col, bold)
  return printf("\x1b[%s%sm%s\x1b[m", a:col, a:bold ? ';1' : '', a:str)
endfunction

for [s:c, s:a] in items({'red': 31, 'green': 32, 'yellow': 33, 'blue': 34, 'magenta': 35, 'cyan': 36})
  execute "function! s:".s:c."(str, ...)\n"
        \ "  return s:ansi(a:str, ".s:a.", get(a:, 1, 0))\n"
        \ "endfunction"
endfor

function! s:buflisted()
  return filter(range(1, bufnr('$')), 'buflisted(v:val)')
endfunction

function! s:fzf(opts, extra)
  return fzf#run(extend(a:opts, get(a:extra, 0, {})))
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
      execute cmd s:escape(item)
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

function! s:warn(message)
  echohl WarningMsg
  echom a:message
  echohl None
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
  let args = {
  \ 'sink*':   function('s:common_sink'),
  \ 'options': '-m'.s:expect()
  \}

  if !empty(a:dir)
    if !isdirectory(expand(a:dir))
      call s:warn('Invalid directory')
      return
    endif
    let dir = substitute(a:dir, '/*$', '/', '')
    let args.dir = dir
    let args.options .= ' --prompt '.shellescape(dir)
  else
    let args.options .= ' --prompt '.shellescape(pathshorten(getcwd())).'/'
  endif

  call s:fzf(args, a:000)
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

function! fzf#vim#_lines()
  let cur = []
  let rest = []
  let buf = bufnr('')
  for b in s:buflisted()
    call extend(b == buf ? cur : rest,
    \ map(getbufline(b, 1, "$"),
    \ 'printf("[%s]\t%s:\t%s", s:blue(b), s:yellow(v:key + 1), v:val)'))
  endfor
  return extend(cur, rest)
endfunction

function! fzf#vim#lines(...)
  call s:fzf({
  \ 'source':  fzf#vim#_lines(),
  \ 'sink*':   function('s:line_handler'),
  \ 'options': '+m --tiebreak=index --prompt "Lines> " --ansi --extended --nth=3..'.s:expect()
  \}, a:000)
endfunction

" ------------------------------------------------------------------
" BLines
" ------------------------------------------------------------------
function! s:buffer_line_handler(lines)
  if len(a:lines) < 2
    return
  endif
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
  call s:fzf({
  \ 'source':  s:buffer_lines(),
  \ 'sink*':   function('s:buffer_line_handler'),
  \ 'options': '+m --tiebreak=index --prompt "BLines> " --ansi --extended --nth=2..'.s:expect()
  \}, a:000)
endfunction

" ------------------------------------------------------------------
" Colors
" ------------------------------------------------------------------
function! fzf#vim#colors(...)
  call s:fzf({
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
  call s:fzf({
  \ 'source':  'locate '.a:query,
  \ 'sink*':   function('s:common_sink'),
  \ 'options': '-m --prompt "Locate> "' . s:expect()
  \}, a:000)
endfunction

" ------------------------------------------------------------------
" History[:/]
" ------------------------------------------------------------------
function! s:all_files()
  return extend(
  \ filter(reverse(copy(v:oldfiles)),
  \        "v:val !~ 'fugitive:\\|__Tagbar__\\|NERD_tree\\|^/tmp/\\|.git/'"),
  \ filter(map(s:buflisted(), 'bufname(v:val)'), '!empty(v:val)'))
endfunction

function! s:history_source(type)
  let max  = histnr(a:type)
  let fmt  = '%'.len(string(max)).'d'
  let list = filter(map(range(1, max), 'histget(a:type, - v:val)'), '!empty(v:val)')
  return extend([' :: Press CTRL-E to edit'],
    \ map(list, 's:yellow(printf(fmt, len(list) - v:key)).": ".v:val'))
endfunction

nnoremap <plug>(-fzf-vim-do) :execute g:__fzf_command<cr>

function! s:history_sink(type, lines)
  if empty(a:lines)
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
  call s:fzf({
  \ 'source':  s:history_source(':'),
  \ 'sink*':   function('s:cmd_history_sink'),
  \ 'options': '+m --ansi --prompt="Hist:> " --header-lines=1 --expect=ctrl-e --tiebreak=index'}, a:000)
endfunction

function! s:search_history_sink(lines)
  call s:history_sink('/', a:lines)
endfunction

function! fzf#vim#search_history(...)
  call s:fzf({
  \ 'source':  s:history_source('/'),
  \ 'sink*':   function('s:search_history_sink'),
  \ 'options': '+m --ansi --prompt="Hist/> " --header-lines=1 --expect=ctrl-e --tiebreak=index'}, a:000)
endfunction

function! fzf#vim#history(...)
  call s:fzf({
  \ 'source':  reverse(s:all_files()),
  \ 'sink*':   function('s:common_sink'),
  \ 'options': '--prompt "Hist> " -m' . s:expect(),
  \}, a:000)
endfunction

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
  let name = empty(name) ? '[No Name]' : name
  let flag = a:b == bufnr('')  ? s:blue('%') :
          \ (a:b == bufnr('#') ? s:magenta('#') : ' ')
  let modified = getbufvar(a:b, '&modified') ? s:red(' [+]') : ''
  let readonly = getbufvar(a:b, '&modifiable') ? '' : s:green(' [RO]')
  let extra = join(filter([modified, readonly], '!empty(v:val)'), '')
  return s:strip(printf("[%s] %s\t%s\t%s", s:yellow(a:b), flag, name, extra))
endfunction

function! fzf#vim#buffers(...)
  let bufs = map(s:buflisted(), 's:format_buffer(v:val)')
  call s:fzf({
  \ 'source':  reverse(bufs),
  \ 'sink*':   function('s:bufopen'),
  \ 'options': '+m -x --tiebreak=index --ansi -d "\t" -n 2,1..2 --prompt="Buf> "'.s:expect(),
  \}, a:000)
endfunction

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

function! fzf#vim#ag(query, ...)
  call s:fzf({
  \ 'source':  printf('ag --nogroup --column --color "%s"',
  \                   escape(empty(a:query) ? '^(?=.)' : a:query, '"\')),
  \ 'sink*':    function('s:ag_handler'),
  \ 'options': '--ansi --delimiter : --nth 4.. --prompt "Ag> " '.
  \            '--multi --bind ctrl-a:select-all,ctrl-d:deselect-all '.
  \            '--color hl:68,hl+:110'.s:expect()}, a:000)
endfunction

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
  normal! zz
endfunction

function! fzf#vim#buffer_tags(...)
  try
    call s:fzf({
    \ 'source':  s:btags_source(),
    \ 'options': '+m -d "\t" --with-nth 1,4.. -n 1 --prompt "BTags> "'.s:expect(),
    \ 'sink*':   function('s:btags_sink')}, a:000)
  catch
    call s:warn(v:exception)
  endtry
endfunction

" ------------------------------------------------------------------
" Tags
" ------------------------------------------------------------------
function! s:tags_sink(lines)
  if len(a:lines) < 2
    return
  endif
  let cmd = get(get(g:, 'fzf_action', s:default_action), a:lines[0], 'e')
  let parts = split(a:lines[1], '\t\zs')
  let excmd = matchstr(join(parts[2:], ''), '^.*\ze;"\t')
  execute cmd s:escape(parts[1][:-2])
  let [magic, &magic] = [&magic, 0]
  execute excmd
  let &magic = magic
  normal! zz
endfunction

function! fzf#vim#tags(...)
  if empty(tagfiles())
    call s:warn('Preparing tags')
    call system('ctags -R')
  endif

  let tagfile = tagfiles()[0]
  call s:fzf({
  \ 'source':  'cat '.shellescape(tagfile).
  \            '| grep -v "^!" | perl -pe "s/^(.*?)\t(.*?)\t/\x1b[33m\1\x1b[m\t\x1b[34m\2\x1b[m\t/"',
  \ 'dir':     fnamemodify(tagfile, ':h'),
  \ 'options': '--ansi +m --tiebreak=begin --prompt "Tags> "'.s:expect(),
  \ 'sink*':   function('s:tags_sink')}, a:000)
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
  call s:fzf({
  \ 'source':  colored,
  \ 'options': '--ansi --tiebreak=index +m -n 1 -d "\t"',
  \ 'sink':    function('s:inject_snippet')}, a:000)
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
  call s:fzf({
  \ 'source':  extend(extend(list[0:0], map(list[1:], 's:format_cmd(v:val)')), s:excmds()),
  \ 'sink':    function('s:command_sink'),
  \ 'options': '--ansi --tiebreak=index --header-lines 1 -x --prompt "Commands> " -n2 -d'.s:nbs}, a:000)
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
  call s:fzf({
  \ 'source':  extend(list[0:0], map(list[1:], 's:format_mark(v:val)')),
  \ 'sink*':   function('s:mark_sink'),
  \ 'options': '+m -x --ansi --tiebreak=index --header-lines 1 --tiebreak=begin --prompt "Marks> "'.s:expect()}, a:000)
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
  let tags = split(globpath(&runtimepath, '**/doc/tags'), '\n')

  call s:fzf({
  \ 'source':  "grep -H '.*' ".join(map(tags, 'shellescape(v:val)')).
    \ "| perl -ne '/(.*?):(.*?)\t(.*?)\t/; printf(qq(\x1b[33m%-40s\x1b[m\t%s\t%s\n), $2, $3, $1)' | sort",
  \ 'sink':    function('s:helptag_sink'),
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
  execute 'normal!' list[1].'gt'
  execute list[2].'wincmd w'
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
  call s:fzf({
  \ 'source':  extend(['Tab Win    Name'], lines),
  \ 'sink':    function('s:windows_sink'),
  \ 'options': '+m --ansi --tiebreak=begin --header-lines=1'}, a:000)
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
  let opts['sink*'] = function('s:complete_insert')
  let s:reducer = s:pluck(opts, 'reducer', function('s:first_line'))
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
  execute 'normal!' (s:eol ? '' : 'h').del.(s:eol ? 'a': 'i').data
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

  let prefix = s:pluck(s:opts, 'prefix', '\k*$')
  let s:query = col('.') == 1 ? '' :
        \ matchstr(getline('.')[0 : col('.')-2], prefix)
  let s:opts = s:eval(s:opts, 'source', s:query)
  let s:opts = s:eval(s:opts, 'options', s:query)

  call feedkeys("\<Plug>(-fzf-complete-trigger)")
  return ''
endfunction

" ------------------------------------------------------------------
let &cpo = s:cpo_save
unlet s:cpo_save


