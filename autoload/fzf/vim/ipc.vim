" Copyright (c) 2024 Junegunn Choi
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

function! s:warn(message)
  echohl WarningMsg
  echom a:message
  echohl None
  return 0
endfunction

function! fzf#vim#ipc#start(Callback)
  if !exists('*job_start') && !exists('*jobstart')
    call s:warn('job_start/jobstart function not supported')
    return ''
  endif

  if !executable('mkfifo')
    call s:warn('mkfifo is not available')
    return ''
  endif

  call fzf#vim#ipc#stop()

  let g:fzf_ipc = { 'fifo': tempname(), 'callback': a:Callback }
  if !filereadable(g:fzf_ipc.fifo)
    call system('mkfifo '..shellescape(g:fzf_ipc.fifo))
    if v:shell_error
      call s:warn('Failed to create fifo')
    endif
  endif

  call fzf#vim#ipc#restart()

  return g:fzf_ipc.fifo
endfunction

function! fzf#vim#ipc#restart()
  if !exists('g:fzf_ipc')
    throw 'fzf#vim#ipc not started'
  endif

  let Callback = g:fzf_ipc.callback
  if exists('*job_start')
    let g:fzf_ipc.job = job_start(
          \ ['cat', g:fzf_ipc.fifo],
          \ {'out_cb': { _, msg -> call(Callback, [msg]) },
          \  'exit_cb': { _, status -> status == 0 ? fzf#vim#ipc#restart() : '' }}
          \ )
  else
    let eof = ['']
    let g:fzf_ipc.job = jobstart(
          \ ['cat', g:fzf_ipc.fifo],
          \ {'stdout_buffered': 1,
          \  'on_stdout': { j, msg, e -> msg != eof ? call(Callback, msg) : '' },
          \  'on_exit': { j, status, e -> status == 0 ? fzf#vim#ipc#restart() : '' }}
          \ )
  endif
endfunction

function! fzf#vim#ipc#stop()
  if !exists('g:fzf_ipc')
    return
  endif

  let job = g:fzf_ipc.job
  if exists('*job_stop')
    call job_stop(job)
  else
    call jobstop(job)
    call jobwait([job])
  endif

  call delete(g:fzf_ipc.fifo)
  unlet g:fzf_ipc
endfunction
