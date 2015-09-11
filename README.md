fzf :heart: vim
===============

Things you can do with [fzf][fzf] and Vim.

Rationale
---------

[fzf][fzf] in itself is not a Vim plugin, and the official repository only
provides the [basic wrapper function][run] for Vim and it's up to the users to
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

fzf is an independent command-line program and thus requires an external
terminal emulator when on GVim. You may or may not like the experience. Also
note that fzf currently does not compile on Windows.

Installation
------------

Using [vim-plug](https://github.com/junegunn/vim-plug):

```vim
Plug 'junegunn/fzf', { 'dir': '~/.fzf', 'do': 'yes \| ./install' }
Plug 'junegunn/fzf.vim'
```

Commands
--------

| Command          | List                                                                      |
| ---              | ---                                                                       |
| `Files [PATH]`   | Files (similar to `:FZF`)                                                 |
| `Buffers`        | Open buffers                                                              |
| `Colors`         | Color schemes                                                             |
| `Ag [PATTERN]`   | [ag][ag] search result (`CTRL-A` to select all, `CTRL-D` to deselect all) |
| `Lines`          | Lines in loaded buffers                                                   |
| `BLines`         | Lines in the current buffer                                               |
| `Tags`           | Tags in the project (`ctags -R`)                                          |
| `BTags`          | Tags in the current buffer                                                |
| `Marks`          | Marks                                                                     |
| `Windows`        | Windows                                                                   |
| `Locate PATTERN` | `locate` command output                                                   |
| `History`        | `v:oldfiles` and open buffers                                             |
| `History:`       | Command history                                                           |
| `History/`       | Search history                                                            |
| `Snippets`       | Snippets ([UltiSnips][us])                                                |
| `Commands`       | Commands                                                                  |
| `Helptags`       | Help tags <sup id="a1">[1](#helptags)</sup>                               |

- Most commands support `CTRL-T` / `CTRL-X` / `CTRL-V` key
  bindings to open in a new tab, a new split, or in a new vertical split.
- Bang-versions of the commands (e.g. `Ag!`) will open fzf in fullscreen

(<a name="helptags">1</a>: `Helptags` will shadow the command of the same name
from [pathogen][pat]. But its functionality is still available via `call
pathogen#helptags()`. [↩](#a1))

[pat]: https://github.com/tpope/vim-pathogen

### Customization

```vim
" This is the default extra key bindings
let g:fzf_action = {
  \ 'ctrl-t': 'tab split',
  \ 'ctrl-x': 'split',
  \ 'ctrl-v': 'vsplit' }

" Default fzf layout
let g:fzf_layout = { 'down': '40%' }

" Advanced customization using autoload functions
autocmd VimEnter * command! Colors call fzf#vim#colors({'left': '15%'})
```

Mappings
--------

| Mapping                            | Description                               |
| ---                                | ---                                       |
| `<plug>(fzf-complete-word)`        | `cat /usr/share/dict/words`               |
| `<plug>(fzf-complete-path)`        | Path completion using `find` (file + dir) |
| `<plug>(fzf-complete-file)`        | File completion using `find`              |
| `<plug>(fzf-complete-file-ag)`     | File completion using `ag`                |
| `<plug>(fzf-complete-line)`        | Line completion (all open buffers)        |
| `<plug>(fzf-complete-buffer-line)` | Line completion (current buffer only)     |

### Usage

```vim
imap <c-x><c-k> <plug>(fzf-complete-word)
imap <c-x><c-f> <plug>(fzf-complete-path)
imap <c-x><c-j> <plug>(fzf-complete-file-ag)
imap <c-x><c-l> <plug>(fzf-complete-line)

" Advanced customization using autoload functions
inoremap <expr> <c-x><c-k> fzf#vim#complete#word({'left': '15%'})
```

### Completion helper

`fzf#complete` is a helper function for creating custom fuzzy completion using
fzf. If the first parameter is a command string or a Vim list, it will be used
as the source.

```vim
" Replace the default dictionary completion with fzf-based fuzzy completion
inoremap <expr> <c-x><c-k> fzf#complete('cat /usr/share/dict/words')
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
- `sink` or `sink*` are not allowed

#### Reducer example

```vim
function! s:make_sentence(lines)
  return substitute(join(a:lines), '^.', '\=toupper(submatch(0))', '').'.'
endfunction

inoremap <expr> <c-x><c-s> fzf#complete({
  \ 'source':  'cat /usr/share/dict/words',
  \ 'reducer': function('<sid>make_sentence'),
  \ 'options': '--multi --reverse --margin 15%,0',
  \ 'left':    20})
```

License
-------

MIT

[fzf]:   https://github.com/junegunn/fzf
[run]:   https://github.com/junegunn/fzf#usage-as-vim-plugin
[vimrc]: https://github.com/junegunn/dotfiles/blob/master/vimrc
[ag]:    https://github.com/ggreer/the_silver_searcher
[us]:    https://github.com/SirVer/ultisnips
