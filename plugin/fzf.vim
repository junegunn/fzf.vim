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

let s:default_height = '40%'
let s:fzf_go = expand('<sfile>:h:h').'/bin/fzf'
let s:fzf_tmux = expand('<sfile>:h:h').'/bin/fzf-tmux'

let s:cpo_save = &cpo
set cpo&vim

" fzf plugin

function! s:fzf_exec()
  if !exists('s:exec')
    if executable(s:fzf_go)
      let s:exec = s:fzf_go
    elseif executable('fzf')
      let s:exec = 'fzf'
    else
      redraw
      throw 'fzf executable not found'
    endif
  endif
  return s:exec
endfunction

function! s:tmux_enabled()
  if exists('s:tmux')
    return s:tmux
  endif

  let s:tmux = 0
  if exists('$TMUX') && executable(s:fzf_tmux)
    let output = system('tmux -V')
    let s:tmux = !v:shell_error && output >= 'tmux 1.7'
  endif
  return s:tmux
endfunction

function! s:shellesc(arg)
  return '"'.substitute(a:arg, '"', '\\"', 'g').'"'
endfunction

function! s:escape(path)
  return escape(a:path, ' %#''"\')
endfunction

" Upgrade legacy options
function! s:upgrade(dict)
  let copy = copy(a:dict)
  if has_key(copy, 'tmux')
    let copy.down = remove(copy, 'tmux')
  endif
  if has_key(copy, 'tmux_height')
    let copy.down = remove(copy, 'tmux_height')
  endif
  if has_key(copy, 'tmux_width')
    let copy.right = remove(copy, 'tmux_width')
  endif
  return copy
endfunction

function! s:error(msg)
  echohl ErrorMsg
  echom a:msg
  echohl None
endfunction

function! s:warn(msg)
  echohl WarningMsg
  echom a:msg
  echohl None
endfunction

function! fzf#run(...) abort
try
  let oshell = &shell
  set shell=sh
  if has('nvim') && bufexists('term://*:FZF')
    call s:warn('FZF is already running!')
    return []
  endif
  let dict   = exists('a:1') ? s:upgrade(a:1) : {}
  let temps  = { 'result': tempname() }
  let optstr = get(dict, 'options', '')
  try
    let fzf_exec = s:fzf_exec()
  catch
    throw v:exception
  endtry

  if has_key(dict, 'source')
    let source = dict.source
    let type = type(source)
    if type == 1
      let prefix = source.'|'
    elseif type == 3
      let temps.input = tempname()
      call writefile(source, temps.input)
      let prefix = 'cat '.s:shellesc(temps.input).'|'
    else
      throw 'Invalid source type'
    endif
  else
    let prefix = ''
  endif
  let tmux = !has('nvim') && s:tmux_enabled() && s:splittable(dict)
  let command = prefix.(tmux ? s:fzf_tmux(dict) : fzf_exec).' '.optstr.' > '.temps.result

  if has('nvim')
    return s:execute_term(dict, command, temps)
  endif

  let ret = tmux ? s:execute_tmux(dict, command, temps) : s:execute(dict, command, temps)
  call s:popd(dict, ret)
  return ret
finally
  let &shell = oshell
endtry
endfunction

function! s:present(dict, ...)
  for key in a:000
    if !empty(get(a:dict, key, ''))
      return 1
    endif
  endfor
  return 0
endfunction

function! s:fzf_tmux(dict)
  let size = ''
  for o in ['up', 'down', 'left', 'right']
    if s:present(a:dict, o)
      let spec = a:dict[o]
      if (o == 'up' || o == 'down') && spec[0] == '~'
        let size = '-'.o[0].s:calc_size(&lines, spec[1:], a:dict)
      else
        " Legacy boolean option
        let size = '-'.o[0].(spec == 1 ? '' : spec)
      endif
      break
    endif
  endfor
  return printf('LINES=%d COLUMNS=%d %s %s %s --',
    \ &lines, &columns, s:fzf_tmux, size, (has_key(a:dict, 'source') ? '' : '-'))
endfunction

function! s:splittable(dict)
  return s:present(a:dict, 'up', 'down', 'left', 'right')
endfunction

function! s:pushd(dict)
  if s:present(a:dict, 'dir')
    let cwd = getcwd()
    if get(a:dict, 'prev_dir', '') ==# cwd
      return 1
    endif
    let a:dict.prev_dir = cwd
    execute 'chdir' s:escape(a:dict.dir)
    let a:dict.dir = getcwd()
    return 1
  endif
  return 0
endfunction

function! s:popd(dict, lines)
  " Since anything can be done in the sink function, there is no telling that
  " the change of the working directory was made by &autochdir setting.
  "
  " We use the following heuristic to determine whether to restore CWD:
  " - Always restore the current directory when &autochdir is disabled.
  "   FIXME This makes it impossible to change directory from inside the sink
  "   function when &autochdir is not used.
  " - In case of an error or an interrupt, a:lines will be empty.
  "   And it will be an array of a single empty string when fzf was finished
  "   without a match. In these cases, we presume that the change of the
  "   directory is not expected and should be undone.
  if has_key(a:dict, 'prev_dir') &&
        \ (!&autochdir || (empty(a:lines) || len(a:lines) == 1 && empty(a:lines[0])))
    execute 'chdir' s:escape(remove(a:dict, 'prev_dir'))
  endif
endfunction

function! s:exit_handler(code, command, ...)
  if a:code == 130
    return 0
  elseif a:code > 1
    call s:error('Error running ' . a:command)
    if !empty(a:000)
      sleep
    endif
    return 0
  endif
  return 1
endfunction

function! s:execute(dict, command, temps) abort
  call s:pushd(a:dict)
  silent! !clear 2> /dev/null
  let command = escape(substitute(a:command, '\n', '\\n', 'g'), '%#')
  execute 'silent !'.command
  redraw!
  return s:exit_handler(v:shell_error, command) ? s:callback(a:dict, a:temps) : []
endfunction

function! s:execute_tmux(dict, command, temps) abort
  let command = a:command
  if s:pushd(a:dict)
    " -c '#{pane_current_path}' is only available on tmux 1.9 or above
    let command = 'cd '.s:escape(a:dict.dir).' && '.command
  endif

  call system(command)
  redraw!
  return s:exit_handler(v:shell_error, command) ? s:callback(a:dict, a:temps) : []
endfunction

function! s:calc_size(max, val, dict)
  if a:val =~ '%$'
    let size = a:max * str2nr(a:val[:-2]) / 100
  else
    let size = min([a:max, str2nr(a:val)])
  endif

  let srcsz = -1
  if type(get(a:dict, 'source', 0)) == type([])
    let srcsz = len(a:dict.source)
  endif

  let opts = get(a:dict, 'options', '').$FZF_DEFAULT_OPTS
  let margin = stridx(opts, '--inline-info') > stridx(opts, '--no-inline-info') ? 1 : 2
  return srcsz >= 0 ? min([srcsz + margin, size]) : size
endfunction

function! s:getpos()
  return {'tab': tabpagenr(), 'win': winnr(), 'cnt': winnr('$')}
endfunction

function! s:split(dict)
  let directions = {
  \ 'up':    ['topleft', 'resize', &lines],
  \ 'down':  ['botright', 'resize', &lines],
  \ 'left':  ['vertical topleft', 'vertical resize', &columns],
  \ 'right': ['vertical botright', 'vertical resize', &columns] }
  let s:ppos = s:getpos()
  try
    for [dir, triple] in items(directions)
      let val = get(a:dict, dir, '')
      if !empty(val)
        let [cmd, resz, max] = triple
        if (dir == 'up' || dir == 'down') && val[0] == '~'
          let sz = s:calc_size(max, val[1:], a:dict)
        else
          let sz = s:calc_size(max, val, {})
        endif
        execute cmd sz.'new'
        execute resz sz
        return
      endif
    endfor
    if s:present(a:dict, 'window')
      execute a:dict.window
    else
      tabnew
    endif
  finally
    setlocal winfixwidth winfixheight buftype=nofile bufhidden=wipe nobuflisted
  endtry
endfunction

function! s:execute_term(dict, command, temps) abort
  call s:split(a:dict)

  let fzf = { 'buf': bufnr('%'), 'dict': a:dict, 'temps': a:temps, 'name': 'FZF' }
  let s:command = a:command
  function! fzf.on_exit(id, code)
    let pos = s:getpos()
    let inplace = pos == s:ppos " {'window': 'enew'}
    if !inplace
      if bufnr('') == self.buf
        " We use close instead of bd! since Vim does not close the split when
        " there's no other listed buffer (nvim +'set nobuflisted')
        close
      endif
      if pos.tab == s:ppos.tab
        wincmd p
      endif
    endif

    if !s:exit_handler(a:code, s:command, 1)
      return
    endif

    call s:pushd(self.dict)
    let ret = []
    try
      let ret = s:callback(self.dict, self.temps)

      if inplace && bufnr('') == self.buf
        execute "normal! \<c-^>"
        " No other listed buffer
        if bufnr('') == self.buf
          bd!
        endif
      endif
    finally
      call s:popd(self.dict, ret)
    endtry
  endfunction

  call s:pushd(a:dict)
  call termopen(a:command, fzf)
  call s:popd(a:dict, [])
  setlocal nospell
  setf fzf
  startinsert
  return []
endfunction

function! s:callback(dict, temps) abort
let lines = []
try
  if filereadable(a:temps.result)
    let lines = readfile(a:temps.result)
    if has_key(a:dict, 'sink')
      for line in lines
        if type(a:dict.sink) == 2
          call a:dict.sink(line)
        else
          execute a:dict.sink s:escape(line)
        endif
      endfor
    endif
    if has_key(a:dict, 'sink*')
      call a:dict['sink*'](lines)
    endif
  endif

  for tf in values(a:temps)
    silent! call delete(tf)
  endfor
catch
  if stridx(v:exception, ':E325:') < 0
    echoerr v:exception
  endif
finally
  return lines
endtry
endfunction

let s:default_action = {
  \ 'ctrl-m': 'e',
  \ 'ctrl-t': 'tab split',
  \ 'ctrl-x': 'split',
  \ 'ctrl-v': 'vsplit' }

function! s:cmd_callback(lines) abort
  if empty(a:lines)
    return
  endif
  let key = remove(a:lines, 0)
  let cmd = get(s:action, key, 'e')
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

function! s:cmd(bang, ...) abort
  let s:action = get(g:, 'fzf_action', s:default_action)
  let args = extend(['--expect='.join(keys(s:action), ',')], a:000)
  let opts = {}
  if len(args) > 0 && isdirectory(expand(args[-1]))
    let opts.dir = substitute(remove(args, -1), '\\\(["'']\)', '\1', 'g')
  endif
  if !a:bang
    let opts.down = get(g:, 'fzf_height', get(g:, 'fzf_tmux_height', s:default_height))
  endif
  call fzf#run(extend({'options': join(args), 'sink*': function('<sid>cmd_callback')}, opts))
endfunction

command! -nargs=* -complete=dir -bang FZF call s:cmd(<bang>0, <f-args>)


" fzf.vim plugin

let g:fzf#vim#default_layout = {'down': '~40%'}

function! s:defs(commands)
  let prefix = get(g:, 'fzf_command_prefix', '')
  if prefix =~# '^[^A-Z]'
    echoerr 'g:fzf_command_prefix must start with an uppercase letter'
    return
  endif
  for command in a:commands
    execute substitute(command, '\ze\C[A-Z]', prefix, '')
  endfor
endfunction

call s:defs([
\'command!      -bang -nargs=? -complete=dir Files  call fzf#vim#files(<q-args>, <bang>0)',
\'command!      -bang -nargs=? GitFiles             call fzf#vim#gitfiles(<q-args>, <bang>0)',
\'command!      -bang -nargs=? GFiles               call fzf#vim#gitfiles(<q-args>, <bang>0)',
\'command! -bar -bang Buffers                       call fzf#vim#buffers(<bang>0)',
\'command!      -bang -nargs=* Lines                call fzf#vim#lines(<q-args>, <bang>0)',
\'command!      -bang -nargs=* BLines               call fzf#vim#buffer_lines(<q-args>, <bang>0)',
\'command! -bar -bang Colors                        call fzf#vim#colors(<bang>0)',
\'command!      -bang -nargs=+ -complete=dir Locate call fzf#vim#locate(<q-args>, <bang>0)',
\'command!      -bang -nargs=* Ag                   call fzf#vim#ag(<q-args>, <bang>0)',
\'command!      -bang -nargs=* Tags                 call fzf#vim#tags(<q-args>, <bang>0)',
\'command!      -bang -nargs=* BTags                call fzf#vim#buffer_tags(<q-args>, <bang>0)',
\'command! -bar -bang Snippets                      call fzf#vim#snippets(<bang>0)',
\'command! -bar -bang Commands                      call fzf#vim#commands(<bang>0)',
\'command! -bar -bang Marks                         call fzf#vim#marks(<bang>0)',
\'command! -bar -bang Helptags                      call fzf#vim#helptags(<bang>0)',
\'command! -bar -bang Windows                       call fzf#vim#windows(<bang>0)',
\'command! -bar -bang Commits                       call fzf#vim#commits(<bang>0)',
\'command! -bar -bang BCommits                      call fzf#vim#buffer_commits(<bang>0)',
\'command! -bar -bang Maps                          call fzf#vim#maps("n", <bang>0)',
\'command! -bar -bang Filetypes                     call fzf#vim#filetypes(<bang>0)',
\'command!      -bang -nargs=* History              call s:history(<q-args>, <bang>0)'])

function! s:history(arg, bang)
  let bang = a:bang || a:arg[len(a:arg)-1] == '!'
  if a:arg[0] == ':'
    call fzf#vim#command_history(bang)
  elseif a:arg[0] == '/'
    call fzf#vim#search_history(bang)
  else
    call fzf#vim#history(bang)
  endif
endfunction

function! fzf#complete(...)
  return call('fzf#vim#complete', a:000)
endfunction

if has('nvim') && get(g:, 'fzf_nvim_statusline', 1)
  function! s:fzf_restore_colors()
    if exists('#User#FzfStatusLine')
      doautocmd User FzfStatusLine
    else
      if $TERM !~ "256color"
        highlight default fzf1 ctermfg=1 ctermbg=8 guifg=#E12672 guibg=#565656
        highlight default fzf2 ctermfg=2 ctermbg=8 guifg=#BCDDBD guibg=#565656
        highlight default fzf3 ctermfg=7 ctermbg=8 guifg=#D9D9D9 guibg=#565656
      else
        highlight default fzf1 ctermfg=161 ctermbg=238 guifg=#E12672 guibg=#565656
        highlight default fzf2 ctermfg=151 ctermbg=238 guifg=#BCDDBD guibg=#565656
        highlight default fzf3 ctermfg=252 ctermbg=238 guifg=#D9D9D9 guibg=#565656
      endif
      setlocal statusline=%#fzf1#\ >\ %#fzf2#fz%#fzf3#f
    endif
  endfunction

  function! s:fzf_nvim_term()
    if get(w:, 'airline_active', 0)
      let w:airline_disabled = 1
      autocmd BufWinLeave <buffer> let w:airline_disabled = 0
    endif
    autocmd WinEnter,ColorScheme <buffer> call s:fzf_restore_colors()

    setlocal nospell
    call s:fzf_restore_colors()
  endfunction

  augroup _fzf_statusline
    autocmd!
    autocmd FileType fzf call s:fzf_nvim_term()
  augroup END
endif

let g:fzf#vim#buffers = {}
augroup fzf_buffers
  autocmd!
  if exists('*reltimefloat')
    autocmd BufWinEnter,WinEnter * let g:fzf#vim#buffers[bufnr('')] = reltimefloat(reltime())
  else
    autocmd BufWinEnter,WinEnter * let g:fzf#vim#buffers[bufnr('')] = localtime()
  endif
  autocmd BufDelete * silent! call remove(g:fzf#vim#buffers, expand('<abuf>'))
augroup END

inoremap <expr> <plug>(fzf-complete-word)        fzf#vim#complete#word()
inoremap <expr> <plug>(fzf-complete-path)        fzf#vim#complete#path("find . -path '*/\.*' -prune -o -print \| sed '1d;s:^..::'")
inoremap <expr> <plug>(fzf-complete-file)        fzf#vim#complete#path("find . -path '*/\.*' -prune -o -type f -print -o -type l -print \| sed 's:^..::'")
inoremap <expr> <plug>(fzf-complete-file-ag)     fzf#vim#complete#path("ag -l -g ''")
inoremap <expr> <plug>(fzf-complete-line)        fzf#vim#complete#line()
inoremap <expr> <plug>(fzf-complete-buffer-line) fzf#vim#complete#buffer_line()

nnoremap <silent> <plug>(fzf-maps-n) :<c-u>call fzf#vim#maps('n', 0)<cr>
inoremap <silent> <plug>(fzf-maps-i) <c-o>:call fzf#vim#maps('i', 0)<cr>
xnoremap <silent> <plug>(fzf-maps-x) :<c-u>call fzf#vim#maps('x', 0)<cr>
onoremap <silent> <plug>(fzf-maps-o) <c-c>:<c-u>call fzf#vim#maps('o', 0)<cr>

let &cpo = s:cpo_save
unlet s:cpo_save

