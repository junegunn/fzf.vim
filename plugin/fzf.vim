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

let g:fzf#vim#default_layout = {'down': '~40%'}

function! s:w(bang)
  return a:bang ? {} : copy(get(g:, 'fzf_layout', g:fzf#vim#default_layout))
endfunction

command! -bang -nargs=? -complete=dir Files call fzf#vim#files(<q-args>, s:w(<bang>0))
command! -bang Buffers                      call fzf#vim#buffers(s:w(<bang>0))
command! -bang Lines                        call fzf#vim#lines(s:w(<bang>0))
command! -bang BLines                       call fzf#vim#buffer_lines(s:w(<bang>0))
command! -bang Colors                       call fzf#vim#colors(s:w(<bang>0))
command! -bang -nargs=1 Locate              call fzf#vim#locate(<q-args>, s:w(<bang>0))
command! -bang -nargs=* Ag                  call fzf#vim#ag(<q-args>, s:w(<bang>0))
command! -bang Tags                         call fzf#vim#tags(s:w(<bang>0))
command! -bang BTags                        call fzf#vim#buffer_tags(s:w(<bang>0))
command! -bang Snippets                     call fzf#vim#snippets(s:w(<bang>0))
command! -bang Commands                     call fzf#vim#commands(s:w(<bang>0))
command! -bang Marks                        call fzf#vim#marks(s:w(<bang>0))
command! -bang Helptags                     call fzf#vim#helptags(s:w(<bang>0))
command! -bang Windows                      call fzf#vim#windows(s:w(<bang>0))

function! s:history(arg, bang)
  let bang = a:bang || a:arg[len(a:arg)-1] == '!'
  let ext = s:w(bang)
  if a:arg[0] == ':'
    call fzf#vim#command_history(ext)
  elseif a:arg[0] == '/'
    call fzf#vim#search_history(ext)
  else
    call fzf#vim#history(ext)
  endif
endfunction
command! -bang -nargs=* History call s:history(<q-args>, <bang>0)

function! fzf#complete(...)
  return call('fzf#vim#complete', a:000)
endfunction

inoremap <expr> <plug>(fzf-complete-word)        fzf#vim#complete#word()
inoremap <expr> <plug>(fzf-complete-path)        fzf#vim#complete#path()
inoremap <expr> <plug>(fzf-complete-file)        fzf#vim#complete#file()
inoremap <expr> <plug>(fzf-complete-file-ag)     fzf#vim#complete#file_ag()
inoremap <expr> <plug>(fzf-complete-line)        fzf#vim#complete#line()
inoremap <expr> <plug>(fzf-complete-buffer-line) fzf#vim#complete#buffer_line()

let &cpo = s:cpo_save
unlet s:cpo_save

