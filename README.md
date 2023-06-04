fzf :heart: vim
===============

Things you can do with [fzf][fzf] and Vim.

Rationale
---------

[fzf][fzf] itself is not a Vim plugin, and the official repository only
provides the [basic wrapper function][run] for Vim. It's up to the users to
write their own Vim commands with it. However, I've learned that many users of
fzf are not familiar with Vimscript and are looking for the "default"
implementation of the features they can find in the alternative Vim plugins.

This repository is a bundle of fzf-based commands and mappings extracted from
my [.vimrc][vimrc] to address such needs. They are *not* designed to be
flexible or configurable, and there's no guarantee of backward-compatibility.

Why you should use fzf on Vim
-----------------------------

Because you can and you love fzf.

fzf runs asynchronously and can be orders of magnitude faster than similar Vim
plugins. However, the benefit may not be noticeable if the size of the input
is small, which is the case for many of the commands provided here.
Nevertheless I wrote them anyway since it's really easy to implement custom
selector with fzf.

Installation
------------

fzf.vim depends on the basic Vim plugin of [the main fzf
repository][fzf-main], which means you need to **set up both "fzf" and
"fzf.vim" on Vim**. To learn more about fzf/Vim integration, see
[README-VIM][README-VIM].

[fzf-main]: https://github.com/junegunn/fzf
[README-VIM]: https://github.com/junegunn/fzf/blob/master/README-VIM.md

### Using [vim-plug](https://github.com/junegunn/vim-plug)

```vim
Plug 'junegunn/fzf', { 'do': { -> fzf#install() } }
Plug 'junegunn/fzf.vim'
```

`fzf#install()` makes sure that you have the latest binary, but it's optional,
so you can omit it if you use a plugin manager that doesn't support hooks.

### Dependencies

- [fzf][fzf-main] 0.41.1 or above
- For syntax-highlighted preview, install [bat](https://github.com/sharkdp/bat)
- If [delta](https://github.com/dandavison/delta) is available, `GF?`,
  `Commits` and `BCommits` will use it to format `git diff` output.
- `Ag` requires [The Silver Searcher (ag)][ag]
- `Rg` requires [ripgrep (rg)][rg]
- `Tags` and `Helptags` require Perl

Commands
--------

| Command                | List                                                                                  |
| ---                    | ---                                                                                   |
| `:Files [PATH]`        | Files (runs `$FZF_DEFAULT_COMMAND` if defined)                                        |
| `:GFiles [OPTS]`       | Git files (`git ls-files`)                                                            |
| `:GFiles?`             | Git files (`git status`)                                                              |
| `:Buffers`             | Open buffers                                                                          |
| `:Colors`              | Color schemes                                                                         |
| `:Ag [PATTERN]`        | [ag][ag] search result (`ALT-A` to select all, `ALT-D` to deselect all)               |
| `:Rg [PATTERN]`        | [rg][rg] search result (`ALT-A` to select all, `ALT-D` to deselect all)               |
| `:RG [PATTERN]`        | [rg][rg] search result; relaunch ripgrep on every keystroke                           |
| `:Lines [QUERY]`       | Lines in loaded buffers                                                               |
| `:BLines [QUERY]`      | Lines in the current buffer                                                           |
| `:Tags [QUERY]`        | Tags in the project (`ctags -R`)                                                      |
| `:BTags [QUERY]`       | Tags in the current buffer                                                            |
| `:Marks`               | Marks                                                                                 |
| `:Jumps`               | Jumps                                                                                 |
| `:Windows`             | Windows                                                                               |
| `:Locate PATTERN`      | `locate` command output                                                               |
| `:History`             | `v:oldfiles` and open buffers                                                         |
| `:History:`            | Command history                                                                       |
| `:History/`            | Search history                                                                        |
| `:Snippets`            | Snippets ([UltiSnips][us])                                                            |
| `:Commits [LOG_OPTS]`  | Git commits (requires [fugitive.vim][f])                                              |
| `:BCommits [LOG_OPTS]` | Git commits for the current buffer; visual-select lines to track changes in the range |
| `:Commands`            | Commands                                                                              |
| `:Maps`                | Normal mode mappings                                                                  |
| `:Helptags`            | Help tags <sup id="a1">[1](#helptags)</sup>                                           |
| `:Filetypes`           | File types

- Most commands support `CTRL-T` / `CTRL-X` / `CTRL-V` key
  bindings to open in a new tab, a new split, or in a new vertical split
- Bang-versions of the commands (e.g. `Ag!`) will open fzf in fullscreen
- You can set `g:fzf_command_prefix` to give the same prefix to the commands
    - e.g. `let g:fzf_command_prefix = 'Fzf'` and you have `FzfFiles`, etc.

(<a name="helptags">1</a>: `Helptags` will shadow the command of the same name
from [pathogen][pat]. But its functionality is still available via `call
pathogen#helptags()`. [↩](#a1))

[pat]: https://github.com/tpope/vim-pathogen
[f]:   https://github.com/tpope/vim-fugitive

Customization
-------------

### Global options

Every command in fzf.vim internally calls `fzf#wrap` function of the main
repository which supports a set of global option variables. So please read
through [README-VIM][README-VIM] to learn more about them.

#### Preview window

Some commands will show the preview window on the right. You can customize the
behavior with `g:fzf_preview_window`. Here are some examples:

```vim
" This is the default option:
"   - Preview window on the right with 50% width
"   - CTRL-/ will toggle preview window.
" - Note that this array is passed as arguments to fzf#vim#with_preview function.
" - To learn more about preview window options, see `--preview-window` section of `man fzf`.
let g:fzf_preview_window = ['right,50%', 'ctrl-/']

" Preview window is hidden by default. You can toggle it with ctrl-/.
" It will show on the right with 50% width, but if the width is smaller
" than 70 columns, it will show above the candidate list
let g:fzf_preview_window = ['hidden,right,50%,<70(up,40%)', 'ctrl-/']

" Empty value to disable preview window altogether
let g:fzf_preview_window = []

" fzf.vim needs bash to display the preview window.
" On Windows, fzf.vim will first see if bash is in $PATH, then if
" Git bash (C:\Program Files\Git\bin\bash.exe) is available.
" If you want it to use a different bash, set this variable.
" let g:fzf_preview_bash = 'C:\Git\bin\bash.exe'
```

### Command-local options

A few commands in fzf.vim can be customized with global option variables shown
below.

```vim
" [Buffers] Jump to the existing window if possible
let g:fzf_buffers_jump = 1

" [[B]Commits] Customize the options used by 'git log':
let g:fzf_commits_log_options = '--graph --color=always --format="%C(auto)%h%d %s %C(black)%C(bold)%cr"'

" [Tags] Command to generate tags file
let g:fzf_tags_command = 'ctags -R'

" [Commands] --expect expression for directly executing the command
let g:fzf_commands_expect = 'alt-enter,ctrl-x'
```

### Advanced customization

#### Vim functions

Each command in fzf.vim is backed by a Vim function. You can override
a command or define a variation of it by calling its corresponding function.

| Command   | Vim function                                                           |
| ---       | ---                                                                    |
| `Files`   | `fzf#vim#files(dir, [spec dict], [fullscreen bool])`                   |
| `GFiles`  | `fzf#vim#gitfiles(git_options, [spec dict], [fullscreen bool])`        |
| `GFiles?` | `fzf#vim#gitfiles('?', [spec dict], [fullscreen bool])`                |
| `Buffers` | `fzf#vim#buffers([spec dict], [fullscreen bool])`                      |
| `Colors`  | `fzf#vim#colors([spec dict], [fullscreen bool])`                       |
| `Rg`      | `fzf#vim#grep(command, [spec dict], [fullscreen bool])`                |
| `RG`      | `fzf#vim#grep2(command_prefix, query, [spec dict], [fullscreen bool])` |
| ...       | ...                                                                    |

(We can see that the last two optional arguments of each function are
identical. They are directly passed to `fzf#wrap` function. If you haven't
read [README-VIM][README-VIM] already, please read it before proceeding.)

#### Example: Customizing `Files` command

This is the default definition of `Files` command:

```vim
command! -bang -nargs=? -complete=dir Files call fzf#vim#files(<q-args>, <bang>0)
```

Let's say you want to a variation of it called `ProjectFiles` that only
searches inside `~/projects` directory. Then you can do it like this:

```vim
command! -bang ProjectFiles call fzf#vim#files('~/projects', <bang>0)
```

Or, if you want to override the command with different fzf options, just pass
a custom spec to the function.

```vim
command! -bang -nargs=? -complete=dir Files
    \ call fzf#vim#files(<q-args>, {'options': ['--layout=reverse', '--info=inline']}, <bang>0)
```

Want a preview window?

```vim
command! -bang -nargs=? -complete=dir Files
    \ call fzf#vim#files(<q-args>, {'options': ['--layout=reverse', '--info=inline', '--preview', 'cat {}']}, <bang>0)
```

It kind of works, but you probably want a nicer previewer program than `cat`.
fzf.vim ships [a versatile preview script](bin/preview.sh) you can readily
use. It internally executes [bat](https://github.com/sharkdp/bat) for syntax
highlighting, so make sure to install it.

```vim
command! -bang -nargs=? -complete=dir Files
    \ call fzf#vim#files(<q-args>, {'options': ['--layout=reverse', '--info=inline', '--preview', '~/.vim/plugged/fzf.vim/bin/preview.sh {}']}, <bang>0)
```

However, it's not ideal to hard-code the path to the script which can be
different in different circumstances. So in order to make it easier to set up
the previewer, fzf.vim provides `fzf#vim#with_preview` helper function.
Similarly to `fzf#wrap`, it takes a spec dictionary and returns a copy of it
with additional preview options.

```vim
command! -bang -nargs=? -complete=dir Files
    \ call fzf#vim#files(<q-args>, fzf#vim#with_preview({'options': ['--layout=reverse', '--info=inline']}), <bang>0)
```

You can just omit the spec argument if you only want the previewer.

```vim
command! -bang -nargs=? -complete=dir Files
    \ call fzf#vim#files(<q-args>, fzf#vim#with_preview(), <bang>0)
```

#### Example: `git grep` wrapper

The following example implements `GGrep` command that works similarly to
predefined `Ag` or `Rg` using `fzf#vim#grep`.

- We set the base directory to git root by setting `dir` attribute in spec
  dictionary.
- [The preview script](bin/preview.sh) supports `grep` format
  (`FILE_PATH:LINE_NO:...`), so we can just wrap the spec with
  `fzf#vim#with_preview` as before to enable previewer.

```vim
command! -bang -nargs=* GGrep
  \ call fzf#vim#grep(
  \   'git grep --line-number -- '.shellescape(<q-args>),
  \   fzf#vim#with_preview({'dir': systemlist('git rev-parse --show-toplevel')[0]}), <bang>0)
```

Mappings
--------

| Mapping                            | Description                               |
| ---                                | ---                                       |
| `<plug>(fzf-maps-n)`               | Normal mode mappings                      |
| `<plug>(fzf-maps-i)`               | Insert mode mappings                      |
| `<plug>(fzf-maps-x)`               | Visual mode mappings                      |
| `<plug>(fzf-maps-o)`               | Operator-pending mappings                 |
| `<plug>(fzf-complete-word)`        | `cat /usr/share/dict/words`               |
| `<plug>(fzf-complete-path)`        | Path completion using `find` (file + dir) |
| `<plug>(fzf-complete-file)`        | File completion using `find`              |
| `<plug>(fzf-complete-line)`        | Line completion (all open buffers)        |
| `<plug>(fzf-complete-buffer-line)` | Line completion (current buffer only)     |

```vim
" Mapping selecting mappings
nmap <leader><tab> <plug>(fzf-maps-n)
xmap <leader><tab> <plug>(fzf-maps-x)
omap <leader><tab> <plug>(fzf-maps-o)

" Insert mode completion
imap <c-x><c-k> <plug>(fzf-complete-word)
imap <c-x><c-f> <plug>(fzf-complete-path)
imap <c-x><c-l> <plug>(fzf-complete-line)
```

Completion functions
--------------------

| Function                                 | Description                           |
| ---                                      | ---                                   |
| `fzf#vim#complete#path(command, [spec])` | Path completion                       |
| `fzf#vim#complete#word([spec])`          | Word completion                       |
| `fzf#vim#complete#line([spec])`          | Line completion (all open buffers)    |
| `fzf#vim#complete#buffer_line([spec])`   | Line completion (current buffer only) |

```vim
" Path completion with custom source command
inoremap <expr> <c-x><c-f> fzf#vim#complete#path('fd')
inoremap <expr> <c-x><c-f> fzf#vim#complete#path('rg --files')

" Word completion with custom spec with popup layout option
inoremap <expr> <c-x><c-k> fzf#vim#complete#word({'window': { 'width': 0.2, 'height': 0.9, 'xoffset': 1 }})
```

Custom completion
-----------------

`fzf#vim#complete` is a helper function for creating custom fuzzy completion
using fzf. If the first parameter is a command string or a Vim list, it will
be used as the source.

```vim
" Replace the default dictionary completion with fzf-based fuzzy completion
inoremap <expr> <c-x><c-k> fzf#vim#complete('cat /usr/share/dict/words')
```

For advanced uses, you can pass an options dictionary to the function. The set
of options is pretty much identical to that for `fzf#run` only with the
following exceptions:

- `reducer` (funcref)
    - Reducer transforms the output lines of fzf into a single string value
- `prefix` (string or funcref; default: `\k*$`)
    - Regular expression pattern to extract the completion prefix
    - Or a function to extract completion prefix
- Both `source` and `options` can be given as funcrefs that take the
  completion prefix as the argument and return the final value
- `sink` or `sink*` are ignored

```vim
" Global line completion (not just open buffers. ripgrep required.)
inoremap <expr> <c-x><c-l> fzf#vim#complete(fzf#wrap({
  \ 'prefix': '^.*$',
  \ 'source': 'rg -n ^ --color always',
  \ 'options': '--ansi --delimiter : --nth 3..',
  \ 'reducer': { lines -> join(split(lines[0], ':\zs')[2:], '') }}))
```

### Reducer example

```vim
function! s:make_sentence(lines)
  return substitute(join(a:lines), '^.', '\=toupper(submatch(0))', '').'.'
endfunction

inoremap <expr> <c-x><c-s> fzf#vim#complete({
  \ 'source':  'cat /usr/share/dict/words',
  \ 'reducer': function('<sid>make_sentence'),
  \ 'options': '--multi --reverse --margin 15%,0',
  \ 'left':    20})
```

Status line of terminal buffer
------------------------------

When fzf starts in a terminal buffer (see [fzf/README-VIM.md][termbuf]), you
may want to customize the statusline of the containing buffer.

[termbuf]: https://github.com/junegunn/fzf/blob/master/README-VIM.md#fzf-inside-terminal-buffer

### Hide statusline

```vim
autocmd! FileType fzf set laststatus=0 noshowmode noruler
  \| autocmd BufLeave <buffer> set laststatus=2 showmode ruler
```

### Custom statusline

```vim
function! s:fzf_statusline()
  " Override statusline as you like
  highlight fzf1 ctermfg=161 ctermbg=251
  highlight fzf2 ctermfg=23 ctermbg=251
  highlight fzf3 ctermfg=237 ctermbg=251
  setlocal statusline=%#fzf1#\ >\ %#fzf2#fz%#fzf3#f
endfunction

autocmd! User FzfStatusLine call <SID>fzf_statusline()
```

License
-------

MIT

[fzf]:   https://github.com/junegunn/fzf
[run]:   https://github.com/junegunn/fzf/blob/master/README-VIM.md#fzfrun
[vimrc]: https://github.com/junegunn/dotfiles/blob/master/vimrc
[ag]:    https://github.com/ggreer/the_silver_searcher
[rg]:    https://github.com/BurntSushi/ripgrep
[us]:    https://github.com/SirVer/ultisnips
