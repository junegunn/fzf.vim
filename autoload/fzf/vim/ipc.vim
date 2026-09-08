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

" Channels in flight, keyed by fifo path, so concurrent fzf runs do not clash
let s:channels = {}

function! fzf#vim#ipc#start(Callback)
  if !exists('*job_start') && !exists('*jobstart')
    call s:warn('job_start/jobstart function not supported')
    return ''
  endif

  if !executable('mkfifo')
    call s:warn('mkfifo is not available')
    return ''
  endif

  let fifo = tempname()
  call system('mkfifo '.shellescape(fifo))
  if v:shell_error
    if !exists('s:mkfifo_failed')
      let s:mkfifo_failed = 1
      call s:warn('Failed to create fifo')
    endif
    return ''
  endif

  let s:channels[fifo] = { 'fifo': fifo, 'callback': a:Callback }
  call fzf#vim#ipc#restart(fifo)
  if !s:running(s:channels[fifo].job)
    call fzf#vim#ipc#stop(fifo)
    return ''
  endif

  return fifo
endfunction

" Nvim hands over everything one read produced, which can be several messages
" as well as the trailing empty element. Vim's out_cb passes one line at a
" time, so deliver line by line and both behave the same.
function! s:deliver(Callback, lines)
  for line in a:lines
    if !empty(line)
      call call(a:Callback, [line])
    endif
  endfor
endfunction

" The reader is gone, so leaving the channel registered would block the next
" write on a fifo nothing reads
function! s:drop(fifo)
  if has_key(s:channels, a:fifo)
    call delete(remove(s:channels, a:fifo).fifo)
  endif
endfunction

function! fzf#vim#ipc#restart(fifo)
  if !has_key(s:channels, a:fifo)
    throw 'fzf#vim#ipc not started'
  endif

  let chan = s:channels[a:fifo]
  let Callback = chan.callback
  let fifo = a:fifo
  if exists('*job_start')
    let chan.job = job_start(
          \ ['cat', fifo],
          \ {'out_cb': { _, msg -> has_key(s:channels, fifo) ? call(Callback, [msg]) : '' },
          \  'exit_cb': { _, status -> status == 0 && has_key(s:channels, fifo) ? fzf#vim#ipc#restart(fifo) : s:drop(fifo) }}
          \ )
  else
    let chan.job = jobstart(
          \ ['cat', fifo],
          \ {'stdout_buffered': 1,
          \  'on_stdout': { j, msg, e -> has_key(s:channels, fifo) ? s:deliver(Callback, msg) : '' },
          \  'on_exit': { j, status, e -> status == 0 && has_key(s:channels, fifo) ? fzf#vim#ipc#restart(fifo) : s:drop(fifo) }}
          \ )
  endif
endfunction

" Whether the job handle refers to a live job. Nvim returns -1 or 0 instead of
" a handle when it cannot start one
function! s:running(job)
  if exists('*job_status')
    return job_status(a:job) ==# 'run'
  endif
  return a:job > 0
endfunction

function! fzf#vim#ipc#stop(fifo)
  if !has_key(s:channels, a:fifo)
    return
  endif

  " Drop it first, so the exit handler does not restart the job
  let chan = remove(s:channels, a:fifo)
  " Never throw from here, this runs as part of fzf's exit handling
  try
    if exists('*job_stop')
      call job_stop(chan.job)
    else
      call jobstop(chan.job)
      call jobwait([chan.job])
    endif
  catch
  endtry

  call delete(chan.fifo)
endfunction
