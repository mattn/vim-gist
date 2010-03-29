"=============================================================================
" File: gist.vim
" Author: Yasuhiro Matsumoto <mattn.jp@gmail.com>
" Last Change: 29-Mar-2010.
" Version: 3.5
" WebPage: http://github.com/mattn/gist-vim/tree/master
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
"   :Gist -a
"     post whole text to gist with anonymous.
"
"   :Gist -m
"     post multi buffer to gist.
"
"   :Gist -e
"     edit the gist. (shoud be work on gist buffer)
"     you can update the gist with :w command on gist buffer.
"
"   :Gist -d
"     delete the gist. (should be work on gist buffer)
"     password authentication is needed.
"
"   :Gist -e foo.js
"     edit the gist with name 'foo.js'. (shoud be work on gist buffer)
"
"   :Gist XXXXX
"     edit gist XXXXX.
"
"   :Gist -c XXXXX.
"     get gist XXXXX and put to clipboard.
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
"   * if set g:gist_clip_command, gist.vim will copy the gist code
"       with option '-c'.
"
"     # mac
"     let g:gist_clip_command = 'pbcopy'
"
"     # linux
"     let g:gist_clip_command = 'xclip -selection clipboard'
"
"     # others(cygwin?)
"     let g:gist_clip_command = 'putclip'
"
"   * if you want to detect filetype from gist's filename...
"
"     # detect filetype if vim failed auto-detection.
"     let g:gist_detect_filetype = 1
"
"     # detect filetype always.
"     let g:gist_detect_filetype = 2
"
"   * if you want to open browser after the post...
"
"     let g:gist_open_browser_after_post = 1
"
"   * if you want to change the browser...
"
"     let g:gist_browser_command = 'w3m %URL%'
"
"       or
"
"     let g:gist_browser_command = 'opera %URL% &'
"
"     on windows, should work with your setting.
"
" Thanks:
"   MATSUU Takuto:
"     removed carriage return
"     gist_browser_command enhancement
"     edit support
"
" GetLatestVimScripts: 2423 1 :AutoInstall: gist.vim
" script type: plugin

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

if !exists('g:gist_open_browser_after_post')
  let g:gist_open_browser_after_post = 0
endif

if !exists('g:gist_put_url_to_clipboard_after_post')
  let g:gist_put_url_to_clipboard_after_post = 1
endif

if !exists('g:gist_browser_command')
  if has('win32')
    let g:gist_browser_command = "!start rundll32 url.dll,FileProtocolHandler %URL%"
  elseif has('mac')
    let g:gist_browser_command = "open %URL%"
  elseif executable('xdg-open')
    let g:gist_browser_command = "xdg-open %URL%"
  else
    let g:gist_browser_command = "firefox %URL% &"
  endif
endif

if !exists('g:gist_detect_filetype')
  let g:gist_detect_filetype = 0
endif

if !exists('g:gist_show_privates')
  let g:gist_show_privates = 0
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
  let winnum = bufwinnr(bufnr('gist:'.a:gistls))
  if winnum != -1
    if winnum != bufwinnr('%')
      exe "normal \<c-w>".winnum."w"
    endif
    setlocal modifiable
  else
    exec 'silent split gist:'.a:gistls
  endif

  if g:gist_show_privates
    let password = inputsecret('Password:')
    if len(password) == 0
      echo 'Canceled'
      return
    endif
    echon "Login to gist... "
    let cookie = s:GistGetSessionID(a:user, password)
    if len(cookie) == 0
      echo 'Failed'
      return
    endif
    silent %d _
    let quote = &shellxquote == '"' ?  "'" : '"'
    exec 'silent r! curl -i -b '.quote.substitute(cookie,'%','\\%','g').quote.' '.url
  else
    silent %d _
    exec 'silent r! curl -s '.url
  endif

  silent normal! ggdd
  silent! %s/>/>\r/g
  silent! %s/</\r</g
  silent! %g/<pre/,/<\/pre/join!
  silent! %g/<span class="date"/,/<\/span/join
  silent! %g/^<span class="date"/s/> */>/g
  silent! %v/^\(gist:\|<pre>\|<span class="date">\)/d _
  silent! %s/<div[^>]*>/\r  /g
  silent! %s/<\/pre>/\r/g
  silent! %g/^gist:/,/<span class="date"/join
  silent! %s/<[^>]\+>//g
  silent! %s/\r//g
  silent! %s/&nbsp;/ /g
  silent! %s/&quot;/"/g
  silent! %s/&amp;/\&/g
  silent! %s/&gt;/>/g
  silent! %s/&lt;/</g
  silent! %s/&#\(\d\d\);/\=nr2char(submatch(1))/g
  silent! %g/^gist: /s/ //g

  setlocal buftype=nofile bufhidden=hide noswapfile
  setlocal nomodified
  syntax match SpecialKey /^gist:/he=e-1
  exec 'nnoremap <silent> <buffer> <cr> :call <SID>GistListAction()<cr>'

  cal cursor(1,1)
  setlocal foldmethod=expr
  setlocal foldexpr=getline(v:lnum)=~'^gist:'?'>1':'='
  setlocal foldtext=getline(v:foldstart)
endfunction

function! s:GistGetFileName(gistid)
  let url = 'http://gist.github.com/'.a:gistid
  let res = system('curl -s '.url)
  let res = substitute(res, '^.*<a href="/raw/[^"]\+/\([^"]\+\)".*$', '\1', '')
  if res =~ '/'
    return ''
  else
    return res
  endif
endfunction

function! s:GistDetectFiletype(gistid)
  let url = 'http://gist.github.com/'.a:gistid
  let mx = '^.*<div class="data syntax type-\([^"]\+\)">.*$'
  let res = system('curl -s '.url)
  let res = substitute(matchstr(res, mx), mx, '\1', '')
  let res = substitute(res, '.*\(\.[^\.]\+\)$', '\1', '')
  let res = substitute(res, '-', '', 'g')
  " TODO: more filetype detection that is specified in html.
  if res == 'bat' | let res = 'dosbatch' | endif
  if res == 'as' | let res = 'actionscript' | endif
  if res == 'bash' | let res = 'sh' | endif
  if res == 'cl' | let res = 'lisp' | endif
  if res == 'rb' | let res = 'ruby' | endif

  if res =~ '^\.'
    silent! exec "doau BufRead *".res
  else
    silent! exec "setlocal ft=".tolower(res)
  endif
endfunction

function! s:GistWrite(fname)
  if a:fname == expand("%:p")
    Gist -e
  else
    exe "w".(v:cmdbang ? "!" : "")." ".fnameescape(v:cmdarg)." ".fnameescape(a:fname)
  endif
endfunction

function! s:GistGet(user, token, gistid, clipboard)
  let url = 'http://gist.github.com/'.a:gistid.'.txt'
  let winnum = bufwinnr(bufnr('gist:'.a:gistid))
  if winnum != -1
    if winnum != bufwinnr('%')
      exe "normal \<c-w>".winnum."w"
    endif
    setlocal modifiable
  else
    exec 'silent split gist:'.a:gistid
  endif
  filetype detect
  silent %d _
  exec 'silent 0r! curl -s '.url
  normal! Gd_
  setlocal buftype=acwrite bufhidden=delete noswapfile
  setlocal nomodified
  doau StdinReadPost <buffer>
  if (&ft == '' && g:gist_detect_filetype == 1) || g:gist_detect_filetype == 2
    call s:GistDetectFiletype(a:gistid)
  endif
  if a:clipboard
    if exists('g:gist_clip_command')
      exec 'silent w !'.g:gist_clip_command
    else
      normal! gg"+yG
    endif
  endif
  normal! gg
  au! BufWriteCmd <buffer> call s:GistWrite(expand("<amatch>"))
endfunction

function! s:GistListAction()
  let line = getline('.')
  let mx = '^gist:\(\w\+\).*'
  if line =~# mx
    let gistid = substitute(line, mx, '\1', '')
    call s:GistGet(g:github_user, g:github_token, gistid, 0)
  endif
endfunction

function! s:GistUpdate(user, token, content, gistid, gistnm)
  if len(a:gistnm) == 0
    let name = s:GistGetFileName(a:gistid)
  else
    let name = a:gistnm
  endif
  let namemx = '^[^.]\+\(.\+\)$'
  let ext = ''
  if name =~ namemx
    let ext = substitute(name, namemx, '\1', '')
  endif
  let query = [
    \ '_method=put',
    \ 'file_ext[gistfile1%s]=%s',
    \ 'file_name[gistfile1%s]=%s',
    \ 'file_contents[gistfile1%s]=%s',
    \ 'login=%s',
    \ 'token=%s',
    \ ]
  let squery = printf(join(query, '&'),
    \ s:encodeURIComponent(ext), s:encodeURIComponent(ext),
    \ s:encodeURIComponent(ext), s:encodeURIComponent(name),
    \ s:encodeURIComponent(ext), s:encodeURIComponent(a:content),
    \ s:encodeURIComponent(a:user),
    \ s:encodeURIComponent(a:token))
  unlet query

  let file = tempname()
  exec 'redir! > '.file
  silent echo squery
  redir END
  echon " Updating it to gist... "
  let quote = &shellxquote == '"' ?  "'" : '"'
  let url = 'http://gist.github.com/gists/'.a:gistid
  let res = system('curl -i -d @'.quote.file.quote.' '.url)
  call delete(file)
  let res = matchstr(split(res, '\(\r\?\n\|\r\n\?\)'), '^Location: ')
  let res = substitute(res, '^.*: ', '', '')
  if len(res) > 0 && res =~ '^\(http\|https\):\/\/gist\.github\.com\/'
    setlocal nomodified
    echo 'Done: '.res
  else
    echoerr 'Edit failed'
  endif
  return res
endfunction

function! s:GistGetSessionID(user, password)
  let query = [
    \ 'login=%s',
    \ 'password=%s',
    \ ]
  let squery = printf(join(query, '&'),
    \ s:encodeURIComponent(a:user),
    \ s:encodeURIComponent(a:password))
  unlet query

  let file = tempname()
  exec 'redir! > '.file
  silent echo squery
  redir END
  let quote = &shellxquote == '"' ?  "'" : '"'
  let url = 'https://gist.github.com/session'
  let res = system('curl -i -d @'.quote.file.quote.' '.url)
  call delete(file)
  let loc = matchstr(split(res, '\(\r\?\n\|\r\n\?\)'), '^Location: ')
  let loc = substitute(res, '^.*: ', '', '')
  if len(loc)
    let res = matchstr(split(res, '\(\r\?\n\|\r\n\?\)'), '^Set-Cookie: ')
    let res = substitute(res, '^.*: \([^;]\+\).*$', '\1', '')
  else
    let res = ''
  endif
  return res
endfunction

function! s:GistDelete(user, token, gistid)
  let password = inputsecret('Password:')
  if len(password) == 0
    echo 'Canceled'
    return
  endif
  echon "Login to gist... "
  let cookie = s:GistGetSessionID(a:user, password)
  if len(cookie) == 0
    echo 'Failed'
    return
  endif
  echon " Deleting gist... "
  let quote = &shellxquote == '"' ?  "'" : '"'
  let url = 'http://gist.github.com/delete/'.a:gistid
  let res = system('curl -i -b '.quote.substitute(cookie,'%','\\%','g').quote.' '.url)
  let res = matchstr(split(res, '\(\r\?\n\|\r\n\?\)'), '^Location: ')
  let res = substitute(res, '^.*: ', '', '')
  if len(res) > 0 && res != 'http://gist.github.com/gists'
    echo 'Done: '
  else
    echoerr 'Delete failed'
  endif
endfunction


" GistPost function:
"   Post new gist to github
"
"   if there is an embedded gist url or gist id in your file,
"   it will just update it.
"                                                   -- by c9s
"
"   embedded gist url format:
"
"       Gist: http://gist.github.com/123123
"
"   embedded gist id format:
"
"       GistID: 123123
"
function! s:GistPost(user, token, content, private)

  " find GistID: in content , then we should just update
  for l in split( a:content , "\n" )
    if l =~ '\<GistID:'
      let gistid = matchstr( l , '\(GistID:\s*\)\@<=[0-9]\+')

      if strlen(gistid) == 0
        echohl WarningMsg | echo "GistID error" | echohl None
        return
      endif
      echo "Found GistID: " . gistid

      cal s:GistUpdate( a:user , a:token ,  a:content , gistid , '' )
      return
    elseif l =~ '\<Gist:'
      let gistid = matchstr( l , '\(Gist:\s*http://gist.github.com/\)\@<=[0-9]\+')

      if strlen(gistid) == 0
        echohl WarningMsg | echo "GistID error" | echohl None
        return
      endif
      echo "Found GistID: " . gistid

      cal s:GistUpdate( a:user , a:token ,  a:content , gistid , '' )
      return
    endif
  endfor

  let ext = expand('%:e')
  let ext = len(ext) ? '.'.ext : ''
  let name = expand('%:t')

  let query = [
    \ 'file_ext[gistfile1]=%s',
    \ 'file_name[gistfile1]=%s',
    \ 'file_contents[gistfile1]=%s',
    \ ]

  if len(a:user) > 0 && len(a:token) > 0
    call add(query, 'login=%s')
    call add(query, 'token=%s')
  else
    call add(query, '%.0s%.0s')
  endif

  if a:private
    call add(query, 'action_button=private')
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
  let res = matchstr(split(res, '\(\r\?\n\|\r\n\?\)'), '^Location: ')
  let res = substitute(res, '^.*: ', '', '')
  if len(res) > 0 && res =~ '^\(http\|https\):\/\/gist\.github\.com\/'
    echo 'Done: '.res
  else
    echoerr 'Post failed'
  endif
  return res
endfunction

function! s:GistPostBuffers(user, token, private)
  let bufnrs = range(1, last_buffer_nr())
  let bn = bufnr('%')
  let query = []
  if len(a:user) > 0 && len(a:token) > 0
    call add(query, 'login=%s')
    call add(query, 'token=%s')
  else
    call add(query, '%.0s%.0s')
  endif
  if a:private
    call add(query, 'action_button=private')
  endif
  let squery = printf(join(query, "&"),
    \ s:encodeURIComponent(a:user),
    \ s:encodeURIComponent(a:token)) . '&'

  let query = [
    \ 'file_ext[gistfile]=%s',
    \ 'file_name[gistfile]=%s',
    \ 'file_contents[gistfile]=%s',
    \ ]
  let format = join(query, "&") . '&'

  let index = 1
  for bufnr in bufnrs
    if buflisted(bufnr) == 0 || bufwinnr(bufnr) == -1
      continue
    endif
    echo "Creating gist content".index."... "
    silent! exec "buffer! ".bufnr
    let content = join(getline(1, line('$')), "\n")
    let ext = expand('%:e')
    let ext = len(ext) ? '.'.ext : ''
    let name = expand('%:t')
    let squery .= printf(substitute(format, 'gistfile', 'gistfile'.index, 'g'),
      \ s:encodeURIComponent(ext),
      \ s:encodeURIComponent(name),
      \ s:encodeURIComponent(content))
    let index = index + 1
  endfor
  silent! exec "buffer! ".bn

  let file = tempname()
  exec 'redir! > '.file
  silent echo squery
  redir END
  echo "Posting it to gist... "
  let quote = &shellxquote == '"' ?  "'" : '"'
  let url = 'http://gist.github.com/gists'
  let res = system('curl -i -d @'.quote.file.quote.' '.url)
  call delete(file)
  let res = matchstr(split(res, '\(\r\?\n\|\r\n\?\)'), '^Location: ')
  let res = substitute(res, '^.*: ', '', '')
  if len(res) > 0 && res =~ '^\(http\|https\):\/\/gist\.github\.com\/'
    echo 'Done: '.res
  else
    echoerr 'Post failed'
  endif
  return res
endfunction

function! Gist(line1, line2, ...)
  if !exists('g:github_user')
    let g:github_user = substitute(system('git config --global github.user'), "\n", '', '')
    if strlen(g:github_user) == 0
      let g:github_user = $GITHUB_USER
    end
  endif
  if !exists('g:github_token')
    let g:github_token = substitute(system('git config --global github.token'), "\n", '', '')
    if strlen(g:github_token) == 0
      let g:github_token = $GITHUB_TOKEN
    end
  endif
  if strlen(g:github_user) == 0 || strlen(g:github_token) == 0
    echoerr "You have no setting for github."
    echohl WarningMsg
    echo "git config --global github.user  your-name"
    echo "git config --global github.token your-token"
    echo "or set g:github_user and g:github_token in your vimrc"
    echo "or set shell env vars GITHUB_USER and GITHUB_TOKEN"
    echohl None
    return 0
  end

  let bufname = bufname("%")
  let user = g:github_user
  let token = g:github_token
  let gistid = ''
  let gistls = ''
  let gistnm = ''
  let private = 0
  let multibuffer = 0
  let clipboard = 0
  let deletepost = 0
  let editpost = 0
  let listmx = '^\(-l\|--list\)\s*\([^\s]\+\)\?$'
  let bufnamemx = '^gist:\([0-9a-f]\+\)$'

  let args = (a:0 > 0) ? split(a:1, ' ') : []
  for arg in args
    if arg =~ '^\(-la\|--listall\)$'
      let gistls = '-all'
    elseif arg =~ '^\(-l\|--list\)$'
      if g:gist_show_privates
        let gistls = 'mine'
      else
        let gistls = g:github_user
      endif
    elseif arg =~ '^\(-m\|--multibuffer\)$'
      let multibuffer = 1
    elseif arg =~ '^\(-p\|--private\)$'
      let private = 1
    elseif arg =~ '^\(-a\|--anonymous\)$'
      let user = ''
      let token = ''
    elseif arg =~ '^\(-c\|--clipboard\)$'
      let clipboard = 1
    elseif arg =~ '^\(-d\|--delete\)$' && bufname =~ bufnamemx
      let deletepost = 1
      let gistid = substitute(bufname, bufnamemx, '\1', '')
    elseif arg =~ '^\(-e\|--edit\)$' && bufname =~ bufnamemx
      let editpost = 1
      let gistid = substitute(bufname, bufnamemx, '\1', '')
    elseif len(gistnm) == 0
      if editpost == 1 || deletepost == 1
        let gistnm = arg
      elseif len(gistls) > 0
        let gistls = arg
      else
        let gistid = arg
      endif
    elseif len(arg) > 0
      echoerr 'Invalid arguments'
      unlet args
      return 0
    endif
  endfor
  unlet args
  "echo "gistid=".gistid
  "echo "gistls=".gistls
  "echo "gistnm=".gistnm
  "echo "private=".private
  "echo "clipboard=".clipboard
  "echo "editpost=".editpost
  "echo "deletepost=".deletepost

  if len(gistls) > 0
    call s:GistList(user, token, gistls)
  elseif len(gistid) > 0 && editpost == 0 && deletepost == 0
    call s:GistGet(user, token, gistid, clipboard)
  else
    if multibuffer == 1
      let url = s:GistPostBuffers(user, token, private)
    else
      let content = join(getline(a:line1, a:line2), "\n")
      if editpost == 1
        let url = s:GistUpdate(user, token, content, gistid, gistnm)
      elseif deletepost == 1
        let url = s:GistDelete(user, token, gistid)
      else
        let url = s:GistPost(user, token, content, private)
      endif
      if len(url) > 0 && g:gist_open_browser_after_post
        let cmd = substitute(g:gist_browser_command, '%URL%', url, 'g')
        if cmd =~ '^!'
          silent! exec cmd
        else
          call system(cmd)
        endif
      endif
    endif
    if g:gist_put_url_to_clipboard_after_post == 1
      if has('unix') && !has('xterm_clipboard')
        let @" = url
      else
        let @+ = url
      endif
    endif
  endif
  return 1
endfunction

command! -nargs=? -range=% Gist :call Gist(<line1>, <line2>, <f-args>)
" vim:set et:
