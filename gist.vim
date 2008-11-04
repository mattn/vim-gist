"=============================================================================
" File: gist.vim
" Author: Yasuhiro Matsumoto <mattn.jp@gmail.com>
" Last Change: Wed, 08 Oct 2008
" Version: 0.1
" GetLatestVimScripts: 2423 1 :AutoInstall: gist.vim
" Usage:
"
"   :Gist
"     post whole text to gist.
"
"   :'<,'>Gist
"     post selected text to gist.
"
"   :Gist -p
"     post whole text to gist with private.
"
"   :Gist XXXXX
"     edit gist XXXXX
"

if &cp || (exists('g:loaded_gist_vim') && g:loaded_gist_vim)
  finish
endif
let g:loaded_gist_vim = 1

if (!exists('g:github_user') || !exists('g:github_token')) && !executable('git')
  echoerr "Gist: require 'git' command"
  finish
endif

if !executable('curl')
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

function! Gist(line1, line2, ...)
  let opt = (a:0 > 0) ? substitute(a:1, ' ', '', 'g') : ''
  let private = ''
  let gistid = ''
  if opt =~ '-p\|--private'
    let private = 'on'
  elseif opt =~ '^\w\+$'
    let gistid = opt
  elseif len(opt) > 0
    echoerr 'Invalid arguments'
    return
  endif
  if len(gistid) > 0
    let url = 'http://gist.github.com/'.gistid.'.txt'
    exec 'silent split gist:'gistid
    exec ':0r! curl -s ' url
    setlocal nomodified
    normal! gg
  else
    if !exists('g:github_user')
      let g:github_user = substitute(system('git config --global github.user'), "\n", '', '')
    endif
    if !exists('g:github_token')
      let g:github_token = substitute(system('git config --global github.token'), "\n", '', '')
    endif
    let user = g:github_user
    let token = g:github_token
    let ext = expand('%:e')
    let ext = len(ext) ? '.'.ext : ''
    let name = bufname('%')
    let query = [
      \ 'file_ext[gistfile1]=%s',
      \ 'file_name[gistfile1]=%s',
      \ 'file_contents[gistfile1]=%s',
      \ 'login=%s',
      \ 'token=%s',
      \ ]
    if len(private)
      call add(query, 'private=on')
    endif
    let squery = printf(join(query, '&'),
      \ s:encodeURIComponent(ext),
      \ s:encodeURIComponent(name),
      \ s:encodeURIComponent(join(getline(a:line1, a:line2), "\n")),
      \ s:encodeURIComponent(user),
      \ s:encodeURIComponent(token))
    unlet query

    let file = tempname()
    exec 'redir! > ' . file 
    silent echo squery
    redir END
    echon " Posting it to gist... "
    let quote = &shellxquote == '"' ?  "'" : '"'
    let url = 'http://gist.github.com/gists'
    let res = system('curl -i -d @'.quote.file.quote.' '.url)
    call delete(file)
    let res = matchstr(split(res, "\n"), '^Location: ')
    let res = substitute(res, '^.*: ', '', '')
    echo 'done: '.res
  endif
endfunction

command! -nargs=? -range=% Gist :call Gist(<line1>, <line2>, <f-args>)
