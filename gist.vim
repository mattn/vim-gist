"=============================================================================
" File: gist.vim
" Author: Yasuhiro Matsumoto <mattn.jp@gmail.com>
" Last Change: Wed, 08 Oct 2008
" Version: 0.1
" Usage:
"   :Gist
"     post whole text to gist.
"
"   :'<,'>Gist
"     post selected text to gist.

if &cp || (exists('g:loaded_gist_vim') && g:loaded_gist_vim)
  finish
endif

if !executable("grep")
  echoerr "Gist: require 'grep' command"
  finish
endif
if !executable("curl")
  echoerr "Gist: require 'curl' command"
  finish
endif

function! s:encodeURIComponent(str)
  let to_enc = 'utf8'
  let t = ''
  let s = iconv(a:str, &enc, to_enc)
  let save_enc = &enc
  let &enc = to_enc
  let i = 0
  let c = s:strpart2(s, i, 1)
  while c != ''
    if c =~# '[0-9A-Za-z-._~!''()*]'
      let t = t . c
    elseif c =~# '[:cntrl:]'
    else
      let n = strlen(c)
      let j = 0
      while j < n
        let t = t . printf('%%%02X', char2nr(strpart(c, j, 1)))
        let j = j + 1
      endwhile
    endif
    let i = i + 1
    let c = s:strpart2(s, i, 1)
  endwhile
  let &enc = save_enc
  let t = iconv(t, to_enc, &enc)
  return t
endfunction

function! s:strpart2(src, start, ...)
  let len = exists('a:1') ? a:1 : 0
  let pat = ''
  let pat = pat . '^.\{' . a:start . '}\zs.'
  let pat = pat . (len > 0 ? '\{' . len . '}' : '*' ) . '\ze'
  return matchstr(a:src, pat)
endfunction

function! Gist(line1, line2)
  let user = substitute(system("git config --global github.user"), "\n", "", "")
  let token = substitute(system("git config --global github.token"), "\n", "", "")
  let private = "on"
  let query = printf(join([
        \ "file_ext[gistfile1]=%s",
        \ "file_name[gistfile1]=%s",
        \ "file_contents[gistfile1]=%s",
        \ "login=%s",
        \ "token=%s",
        \ "private=%s",
        \ ], "&"),
        \ s:encodeURIComponent(""),
        \ s:encodeURIComponent("test"),
        \ s:encodeURIComponent(join(getline(a:line1, a:line2), "\n")),
        \ s:encodeURIComponent(user),
        \ s:encodeURIComponent(token),
        \ s:encodeURIComponent(private))

  let file = tempname()
  exec 'redir! > ' . file 
  silent echo query
  redir END
  echon " Posting it to gist... "
  silent! put! =query
  let quote = &shellxquote == '"' ?  "'" : '"'
  let url = "http://gist.github.com/gists"
  let res = system("curl -i -d @".quote.file.quote." ".url)
  call delete(file)
  let res = matchstr(split(res, "\n"), "^Location: ")
  let res = substitute(res, "^.*: ", "", "")
  echo "done: ".res
endfunction

command! -range=% Gist :call Gist(<line1>, <line2>)
