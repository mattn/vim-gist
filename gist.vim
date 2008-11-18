"=============================================================================
" File: gist.vim
" Author: Yasuhiro Matsumoto <mattn.jp@gmail.com>
" Last Change: 18-Nov-2008. Jan 2008
" Version: 1.0
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
"     edit gist XXXXX.
"
"   :Gist -l
"     list gists from mine.
"
"   :Gist -l mattn
"     list gists from mattn.
"
"   :Gist -la
"     list gists from all.
"
" Tips:
"   if set g:gist_clip_command, gist.vim will copy the gist code.
"
"   # mac
"   let g:gist_clip_command = 'pbcopy'
"
"   # linux
"   let g:gist_clip_command = 'xclip -selection clipboard'
"
"   # others(cygwin?)
"   let g:gist_clip_command = 'putclip'
"
" GetLatestVimScripts: 2423 1 :AutoInstall: gist.vim

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

function! s:nr2hex(nr)
  let n = a:nr
  let r = ""
  while n
    let r = '0123456789ABCDEF'[n % 16] . r
    let n = n / 16
  endwhile
  return r
endfunction

function! s:encodeURIComponent(instr)
  let instr = iconv(a:instr, &enc, "utf-8")
  let len = strlen(instr)
  let i = 0
  let outstr = ''
  while i < len
    let ch = instr[i]
    if ch =~# '[0-9A-Za-z-._~!''()*]'
      let outstr = outstr . ch
    elseif ch == ' '
      let outstr = outstr . '+'
    else
      let outstr = outstr . '%' . substitute('0' . s:nr2hex(char2nr(ch)), '^.*\(..\)$', '\1', '')
    endif
    let i = i + 1
  endwhile
  return outstr
endfunction

function! s:GistList(user, token, gistls)
  if a:gistls == '-all'
    let url = 'http://gist.github.com/gists'
  else
    let url = 'http://gist.github.com/'.a:gistls
  endif
  exec 'silent split gist:'.a:gistls
  exec 'silent 0r! curl -s '.url
  silent! %s/>/>\r/g
  silent! %s/</\r</g
  silent! %g/<pre/,/<\/pre/join!
  silent! %v/^\(gist:\|<pre>\)/d _
  silent! %s/<div[^>]*>/\r  /g
  silent! %s/<\/pre>/\r/g
  silent! %s/<[^>]\+>//g
  silent! %s/\r//g
  silent! %s/&nbsp;/ /g
  silent! %s/&quot;/"/g
  silent! %s/&amp;/\&/g
  silent! %s/&gt;/>/g
  silent! %s/&lt;/</g
  silent! %s/&#\(\d\d\);/\=nr2char(submatch(1))/g
  setlocal nomodified
  syntax match SpecialKey /^gist: /he=e-2
  exec 'nnoremap <silent> <buffer> <cr> :call <SID>GistListAction()<cr>'
  normal! gg
endfunction

function! s:GistGet(user, token, gistid)
  let url = 'http://gist.github.com/'.a:gistid.'.txt'
  exec 'silent split gist:'.a:gistid
  exec 'silent 0r! curl -s '.url
  setlocal nomodified
  normal! gg
  if exists('g:gist_clip_command')
    exec 'silent w !'.g:gist_clip_command
  endif
endfunction

function! s:GistListAction()
  let line = getline('.')
  let mx = '^gist: \(\w\+\)$'
  if line =~# mx
    let gistid = substitute(line, mx, '\1', '')
    call s:GistGet(g:github_user, g:github_token, gistid)
  endif
endfunction

function! s:GistPut(user, token, content, private)
  let ext = expand('%:e')
  let ext = len(ext) ? '.'.ext : ''
  let name = expand('%:t')
  let query = [
    \ 'file_ext[gistfile1]=%s',
    \ 'file_name[gistfile1]=%s',
    \ 'file_contents[gistfile1]=%s',
    \ 'login=%s',
    \ 'token=%s',
    \ ]
  if len(a:private)
    call add(query, 'private=on')
  endif
  let squery = printf(join(query, '&'),
    \ s:encodeURIComponent(ext),
    \ s:encodeURIComponent(name),
    \ s:encodeURIComponent(a:content),
    \ s:encodeURIComponent(a:user),
    \ s:encodeURIComponent(a:token))
  unlet query

  let file = tempname()
  exec 'redir! > '.file 
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
endfunction

function! Gist(line1, line2, ...)
  if !exists('g:github_user')
    let g:github_user = substitute(system('git config --global github.user'), "\n", '', '')
  endif
  if !exists('g:github_token')
    let g:github_token = substitute(system('git config --global github.token'), "\n", '', '')
  endif

  let opt = (a:0 > 0) ? substitute(a:1, ' ', '', 'g') : ''
  let private = ''
  let gistid = ''
  let gistls = ''
  let listmx = '^\(-l\|--list\)\s*\([^\s]\+\)\?$'
  if opt =~ '^\(-la\|--listall\)'
    let gistls = '-all'
  elseif opt =~ listmx
    let gistls = substitute(opt, listmx, '\2', '')
    if len(gistls) == 0
      let gistls = g:github_user
    endif
  elseif opt =~ '-p\|--private'
    let private = 'on'
  elseif opt =~ '^\w\+$'
    let gistid = opt
  elseif len(opt) > 0
    echoerr 'Invalid arguments'
    return
  endif

  if len(gistls) > 0
    call s:GistList(g:github_user, g:github_token, gistls)
  elseif len(gistid) > 0
    call s:GistGet(g:github_user, g:github_token, gistid)
  else
    let content = join(getline(a:line1, a:line2), "\n")
    call s:GistPut(g:github_user, g:github_token, content, private)
  endif
endfunction

command! -nargs=? -range=% Gist :call Gist(<line1>, <line2>, <f-args>)
