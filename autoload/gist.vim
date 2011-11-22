"=============================================================================
" File: gist.vim
" Author: Yasuhiro Matsumoto <mattn.jp@gmail.com>
" Last Change: 22-Nov-2011.
" Version: 5.7
" WebPage: http://github.com/mattn/gist-vim
" License: BSD
" Usage:
"
"   :Gist
"     post current buffer to gist, using default privicy option
"     (see g:gist_private)
"
"   :'<,'>Gist
"     post selected text to gist., using default privicy option
"     This applies to all permutations listed below (except multi)
"     (see g:gist_private)
"
"   :Gist -p
"     create a private gist
"
"   :Gist -P
"     create a public gist
"     (only relevant if you've set gists to be private by default)
"
"   :Gist -P
"     post whole text to gist as public
"     This is only relevant if you've set gists to be private by default
"   :Gist -a
"     create a gist anonymously
"
"   :Gist -m
"     create a gist with all open buffers
"
"   :Gist -e
"     edit the gist. (you need to have opend the gist buffer first)
"     you can update the gist with :w command on gist buffer
"
"   :Gist -d
"     delete the gist. (you need to have opend the gist buffer first)
"     password authentication is needed
"
"   :Gist -f
"     fork the gist. (you need to have opend the gist buffer first)
"     password authentication is needed
"
"   :Gist -e foo.js
"     edit the gist with name 'foo.js'. (you need to have opend the gist buffer first)
"
"   :Gist XXXXX
"     get gist XXXXX
"
"   :Gist -c XXXXX
"     get gist XXXXX and add to clipboard
"
"   :Gist -l
"     list your public gists
"
"   :Gist -l mattn
"     list gists from mattn
"
"   :Gist -la
"     list all your (public and private) gists
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
"     on windows, should work with original setting.
"
"   * if you want to show your private gists with ':Gist -l'
"
"     let g:gist_show_privates = 1
"
"   * if don't you want to copy URL of the post...
"
"     let g:gist_put_url_to_clipboard_after_post = 0
"
"     or if you want to copy URL and add linefeed at the last of URL,
"
"     let g:gist_put_url_to_clipboard_after_post = 2
"
"     default value is 1.
"

let s:save_cpo = &cpo
set cpo&vim

if !exists('g:gist_open_browser_after_post')
  let g:gist_open_browser_after_post = 0
endif

if !exists('g:gist_put_url_to_clipboard_after_post')
  let g:gist_put_url_to_clipboard_after_post = 1
endif

if !exists('g:gist_curl_options')
  let g:gist_curl_options = ""
endif

if !exists('g:gist_browser_command')
  if has('win32') || has('win64')
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

if !exists('g:gist_private')
  let g:gist_private = 0
endif

if !exists('g:gist_show_privates')
  let g:gist_show_privates = 0
endif

if !exists('g:gist_cookie_dir')
  let g:gist_cookie_dir = substitute(expand('<sfile>:p:h'), '[/\\]autoload$', '', '').'/cookies'
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

" Note: A colon in the file name has side effects on Windows due to NTFS Alternate Data Streams; avoid it. 
let s:bufprefix = 'gist' . (has('unix') ? ':' : '_')
function! s:GistList(user, token, gistls, page)
  if a:gistls == '-all'
    let url = 'https://gist.github.com/gists'
  elseif g:gist_show_privates && a:gistls == a:user
    let url = 'https://gist.github.com/mine'
  else
    let url = 'https://gist.github.com/'.a:gistls
  endif
  let winnum = bufwinnr(bufnr(s:bufprefix.a:gistls))
  if winnum != -1
    if winnum != bufwinnr('%')
      exe winnum 'wincmd w'
    endif
    setlocal modifiable
  else
    exec 'silent noautocmd split' s:bufprefix.a:gistls
  endif
  if a:page > 1
    let oldlines = getline(0, line('$'))
    let url = url . '?page=' . a:page
  endif

  setlocal foldmethod=manual
  let old_undolevels = &undolevels
  set undolevels=-1
  let oldlines = []
  if g:gist_show_privates
    redraw
    echon 'Login to gist... '
    silent %d _
    let res = s:GistGetPage(url, a:user, '', '-L')
    silent put =res.content
  else
    silent %d _
    exec 'silent r! curl -f -s' g:gist_curl_options url
  endif

  if v:shell_error != 0
    let &undolevels = old_undolevels
    bw!
    redraw
    echohl ErrorMsg | echomsg 'User not found' | echohl None
    return
  endif

  let oldgdefault = &gdefault
  let &gdefault = 0
  1delete _
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
  let &gdefault = oldgdefault

  call append(0, oldlines)
  $put='more...'
  let &undolevels = old_undolevels

  let b:user = a:user
  let b:token = a:token
  let b:gistls = a:gistls
  let b:page = a:page
  setlocal buftype=nofile bufhidden=hide noswapfile
  setlocal nomodified
  syntax match SpecialKey /^gist:/he=e-1
  nnoremap <silent> <buffer> <cr> :call <SID>GistListAction()<cr>

  cal cursor(1+len(oldlines),1)
  setlocal foldmethod=expr
  setlocal foldexpr=getline(v:lnum)=~'^\\(gist:\\\|more\\)'?'>1':'='
  setlocal foldtext=getline(v:foldstart)
  redraw
  noh
  echo ""
endfunction

function! s:GistGetFileName(gistid)
  let url = 'https://gist.github.com/'.a:gistid
  let res = system('curl -s '.g:gist_curl_options.' '.url)
  let res = matchstr(res, '^.*<a href="/raw/[^"]\+/\zs\([^"]\+\)\ze".*$')
  if res =~ '/'
    return ''
  else
    return res
  endif
endfunction

function! s:GistDetectFiletype(gistid)
  let url = 'https://gist.github.com/'.a:gistid
  let mx = '^.*<div class=".\{-}type-\zs\([^"]\+\)\ze">.*$'
  let res = system('curl -s '.g:gist_curl_options.' '.url)
  let res = matchstr(res, mx)
  let res = matchstr(res, '.*\zs\(\.[^\.]\+\)\ze$')
  let res = substitute(res, '-', '', 'g')
  if has_key(s:extmap, res)
    let res = s:extmap[res]
  else
    let res = ''
  endif

  if res =~ '^\.'
    silent! exec "doau BufRead *".res
  else
    silent! exec "setlocal ft=".tolower(res)
  endif
endfunction

function! s:GistWrite(fname)
  if substitute(a:fname, '\\', '/', 'g') == expand("%:p:gs@\\@/@")
    Gist -e
  else
    exe "w".(v:cmdbang ? "!" : "") fnameescape(v:cmdarg) fnameescape(a:fname)
    silent! exe "file" fnameescape(a:fname)
    silent! au! BufWriteCmd <buffer>
  endif
endfunction

function! s:GistGet(user, token, gistid, clipboard)
  let url = 'https://raw.github.com/gist/'.a:gistid
  let winnum = bufwinnr(bufnr(s:bufprefix.a:gistid))
  if winnum != -1
    if winnum != bufwinnr('%')
      exe winnum 'wincmd w'
    endif
    setlocal modifiable
  else
    exec 'silent noautocmd split' s:bufprefix.a:gistid
  endif
  let old_undolevels = &undolevels
  set undolevels=-1
  filetype detect
  silent %d _
  exec 'silent 0r! curl -f -s' g:gist_curl_options url
  if v:shell_error != 0
    let &undolevels = old_undolevels
    bw!
    redraw
    echohl ErrorMsg | echomsg 'Gist not found' | echohl None
    return
  endif
  $delete _
  let &undolevels = old_undolevels
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
      %yank +
    endif
  endif
  1
  au! BufWriteCmd <buffer> call s:GistWrite(expand("<amatch>"))
endfunction

function! s:GistListAction()
  let line = getline('.')
  let mx = '^gist:\zs\(\w\+\)\ze.*'
  if line =~# mx
    let gistid = matchstr(line, mx)
    call s:GistGet(g:github_user, g:github_token, gistid, 0)
    return
  endif
  if line =~# '^more\.\.\.$'
    delete
    call s:GistList(b:user, b:token, b:gistls, b:page+1)
    return
  endif
endfunction

function! s:GistUpdate(user, token, content, gistid, gistnm)
  if len(a:gistnm) == 0
    let name = s:GistGetFileName(a:gistid)
  else
    let name = a:gistnm
  endif
  let namemx = '^[^.]\+\zs\(.\+\)\ze$'
  let ext = ''
  if name =~ namemx
    let ext = matchstr(name, namemx)
  endif
  let query = [
    \ '_method=put',
    \ 'file_ext[gistfile1]=%s',
    \ 'file_name[gistfile1]=%s',
    \ 'file_contents[gistfile1]=%s',
    \ 'login=%s',
    \ 'token=%s',
    \ ]
  let squery = printf(join(query, '&'),
    \ s:encodeURIComponent(ext),
    \ s:encodeURIComponent(name),
    \ s:encodeURIComponent(a:content),
    \ s:encodeURIComponent(a:user),
    \ s:encodeURIComponent(a:token))
  unlet query

  let action = a:gistid
  if a:gistid !~ '^\d\+$'
    redraw
    echon 'Login to gist... '
    let res = s:GistGetPage('https://gist.github.com/'.a:gistid, a:user, '', '')
    if (!len(res))
      echohl ErrorMsg | echomsg 'Wrong password? no response received from github trying to update ' . a:gistid | echohl None
      return
    endif
    let mx = '^.*<form action="/gists/\zs\([^"]\+\)\ze".*$'
    let action = matchstr(res.content, mx)
    let mx = '^.* name="authenticity_token" type="hidden" value="\zs\([^"]\+\)\ze".*$'
    let token = matchstr(res.content, mx)
    unlet res
    let squery .= '&authenticity_token='.token
  endif

  let file = tempname()
  call writefile([squery], file)
  redraw
  echon 'Updating it to gist... '
  let quote = &shellxquote == '"' ?  "'" : '"'
  let url = 'https://gist.github.com/gists/'.action
  let res = system('curl -i '.g:gist_curl_options.' -d @'.quote.file.quote.' '.url)
  call delete(file)
  let headers = split(res, '\(\r\?\n\|\r\n\?\)')
  let loc = matchstr(headers, '^Location:')
  let loc = matchstr(loc, '^[^:]\+: \zs.*')
  if len(loc) > 0 && loc =~ '^\(http\|https\):\/\/gist\.github\.com\/'
    setlocal nomodified
    redraw
    echo 'Done: '.loc
  else
    let message = matchstr(headers, '^Status:')
    let message = matchstr(message, '^[^:]\+:\s*[0-9]\+\s*\zs\(.*\)')
    echohl ErrorMsg | echomsg 'Edit failed: '.message | echohl None
  endif
  return loc
endfunction

function! s:GistGetPage(url, user, param, opt)
  if !isdirectory(g:gist_cookie_dir)
    call mkdir(g:gist_cookie_dir, 'p')
  endif
  let cookie_file = g:gist_cookie_dir.'/github'

  if len(a:url) == 0
    call delete(cookie_file)
    return
  endif

  let quote = &shellxquote == '"' ?  "'" : '"'
  if !filereadable(cookie_file)
    let password = inputsecret('Password:')
    if len(password) == 0
      echo 'Canceled'
      return
    endif
    let url = 'https://gist.github.com/login?return_to=gist'
    let res = system('curl -f -L -s '.g:gist_curl_options.' -c '.quote.cookie_file.quote.' '.quote.url.quote)
    let token = matchstr(res, '^.* name="authenticity_token" type="hidden" value="\zs\([^"]\+\)\ze".*$')

    let query = [
      \ 'authenticity_token=%s',
      \ 'login=%s',
      \ 'password=%s',
      \ 'return_to=gist',
      \ 'commit=Log+in',
      \ ]
    let squery = printf(join(query, '&'),
      \ s:encodeURIComponent(token),
      \ s:encodeURIComponent(a:user),
      \ s:encodeURIComponent(password))
    unlet query

    let file = tempname()
    let command = 'curl -f -s '.g:gist_curl_options.' -i'
    let command .= ' -b '.quote.cookie_file.quote
    let command .= ' -c '.quote.cookie_file.quote
    let command .= ' '.quote.'https://gist.github.com/session'.quote
    let command .= ' -d @' . quote.file.quote
    call writefile([squery], file)
    let res = system(command)
    call delete(file)
    let headers = split(res, '\(\r\?\n\|\r\n\?\)')
    let loc = matchstr(headers, '^Location:')
    let loc = matchstr(loc, '^[^:]\+: \zs.*')
    if len(loc) == 0
      call delete(cookie_file)
      return ''
    endif
  endif
  let command = 'curl -f -s '.g:gist_curl_options.' -i '.a:opt
  if len(a:param)
    let command .= ' -d '.quote.a:param.quote
  endif
  let command .= ' -b '.quote.cookie_file.quote
  let command .= ' '.quote.a:url.quote
  let res = iconv(system(command), "utf-8", &encoding)
  let pos = stridx(res, "\r\n\r\n")
  if pos != -1
    let content = res[pos+4:]
  else
    let pos = stridx(res, "\n\n")
    let content = res[pos+2:]
  endif
  return {
  \ "header" : split(res[0:pos], '\r\?\n'),
  \ "content" : content
  \}
endfunction

function! s:GistDelete(user, token, gistid)
  redraw
  echon 'Deleting gist... '
  let res = s:GistGetPage('https://gist.github.com/'.a:gistid, a:user, '', '')
  if (!len(res)) 
    echohl ErrorMsg | echomsg 'Wrong password? no response received from github trying to delete ' . a:gistid | echohl None
    return
  endif
  let mx = '^.* name="authenticity_token" type="hidden" value="\zs\([^"]\+\)\ze".*$'
  let token = matchstr(res.content, mx)
  if len(token) > 0
    let res = s:GistGetPage('https://gist.github.com/delete/'.a:gistid, a:user, '_method=delete&authenticity_token='.token, '')
    if len(res.content) > 0
      redraw
      echo 'Done: '
    else
      let message = matchstr(res.headers, '^Status:')
      let message = matchstr(message, '^[^:]\+:\s*[0-9]\+\s*\zs\(.*\)')
      echohl ErrorMsg | echomsg 'Delete failed: '.message | echohl None
    endif
  else
    echohl ErrorMsg | echomsg 'Delete failed' | echohl None
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
"       Gist: https://gist.github.com/123123
"
"   embedded gist id format:
"
"       GistID: 123123
"
function! s:GistPost(user, token, content, private)

  " find GistID: in content, then we should just update
  for l in split(a:content, "\n")
    if l =~ '\<GistID:'
      let gistid = matchstr(l, 'GistID:\s*[0-9a-z]\+')

      if strlen(gistid) == 0
        echohl WarningMsg | echo "GistID error" | echohl None
        return
      endif
      echo "Found GistID: " . gistid

      cal s:GistUpdate(a:user, a:token,  a:content, gistid, '')
      return
    elseif l =~ '\<Gist:'
      let gistid = matchstr(l, 'Gist:\s*https://gist.github.com/[0-9a-z]\+')

      if strlen(gistid) == 0
        echohl WarningMsg | echo "GistID error" | echohl None
        return
      endif
      echo "Found GistID: " . gistid

      cal s:GistUpdate(a:user, a:token,  a:content, gistid, '')
      return
    endif
  endfor

  let ext = expand('%:e')
  if ext == ''
    for k in keys(s:extmap)
      if s:extmap[k] == &ft
        let ext = k
        break
      endif
    endfor
  else
    let ext = '.'.ext
  endif
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
  call writefile([squery], file)
  redraw
  echon 'Posting it to gist... '
  let quote = &shellxquote == '"' ?  "'" : '"'
  let url = 'https://gist.github.com/gists'
  let res = system('curl -f -i '.g:gist_curl_options.' -d @'.quote.file.quote.' '.url)
  call delete(file)
  let headers = split(res, '\(\r\?\n\|\r\n\?\)')
  let loc = matchstr(headers, '^Location:')
  let loc = matchstr(loc, '^[^:]\+: \zs.*')
  if len(loc) > 0 && loc =~ '^\(http\|https\):\/\/gist\.github\.com\/'
    redraw
    echo 'Done: '.loc
  else
    let message = matchstr(headers, '^Status:')
    let message = matchstr(message, '^[^:]\+:\s*[0-9]\+\s*\zs\(.*\)')
    echohl ErrorMsg | echomsg 'Post failed: '.message | echohl None
  endif
  return loc
endfunction

function! s:GistPostBuffers(user, token, private)
  let bufnrs = range(1, bufnr("$"))
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
    if !bufexists(bufnr) || buflisted(bufnr) == 0
      continue
    endif
    echo "Creating gist content".index."... "
    silent! exec "buffer!" bufnr
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
  silent! exec "buffer!" bn

  let file = tempname()
  call writefile([squery], file)
  echo "Posting it to gist... "
  let quote = &shellxquote == '"' ?  "'" : '"'
  let url = 'https://gist.github.com/gists'
  let res = system('curl -i '.g:gist_curl_options.' -d @'.quote.file.quote.' '.url)
  call delete(file)
  let headers = split(res, '\(\r\?\n\|\r\n\?\)')
  let loc = matchstr(headers, '^Location:')
  let loc = matchstr(loc, '^[^:]\+: \zs.*')
  if len(loc) > 0 && loc =~ '^\(http\|https\):\/\/gist\.github\.com\/'
    redraw
    echo 'Done: '.res
  else
    echohl ErrorMsg | echomsg 'Post failed' | echohl None
  endif
  return res
endfunction

function! gist#Gist(count, line1, line2, ...)
  redraw
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
    echohl ErrorMsg
    echomsg "You have no setting for github."
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
  let private = g:gist_private
  let multibuffer = 0
  let clipboard = 0
  let deletepost = 0
  let editpost = 0
  let listmx = '^\%(-l\|--list\)\s*\([^\s]\+\)\?$'
  let bufnamemx = '^' . s:bufprefix .'\zs\([0-9a-f]\+\)\ze$'

  let args = (a:0 > 0) ? split(a:1, ' ') : []
  for arg in args
    if arg =~ '^\(-la\|--listall\)$\C'
      let gistls = '-all'
    elseif arg =~ '^\(-l\|--list\)$\C'
      if g:gist_show_privates
        let gistls = 'mine'
      else
        let gistls = g:github_user
      endif
    elseif arg == '--abandon'
      call s:GistGetPage('', '', '', '')
      return
    elseif arg =~ '^\(-m\|--multibuffer\)$\C'
      let multibuffer = 1
    elseif arg =~ '^\(-p\|--private\)$\C'
      let private = 1
    elseif arg =~ '^\(-P\|--public\)$\C'
      let private = 0
    elseif arg =~ '^\(-a\|--anonymous\)$\C'
      let user = ''
      let token = ''
    elseif arg =~ '^\(-c\|--clipboard\)$\C'
      let clipboard = 1
    elseif arg =~ '^\(-d\|--delete\)$\C' && bufname =~ bufnamemx
      let deletepost = 1
      let gistid = matchstr(bufname, bufnamemx)
    elseif arg =~ '^\(-e\|--edit\)$\C' && bufname =~ bufnamemx
      let editpost = 1
      let gistid = matchstr(bufname, bufnamemx)
    elseif arg =~ '^\(-f\|--fork\)$\C' && bufname =~ bufnamemx
      let gistid = matchstr(bufname, bufnamemx)
      let res = s:GistGetPage("https://gist.github.com/fork/".gistid, g:github_user, '', '')
      let loc = matchstr(res.header, '^Location:')
      let loc = matchstr(loc, '^[^:]\+: \zs.*')
      let mx = '^https://gist.github.com/\zs\([0-9a-z]\+\)$'
      if loc =~ mx
        let gistid = matchstr(loc, mx)
      else
        echohl ErrorMsg | echomsg 'Fork failed' | echohl None
        return
      endif
    elseif arg !~ '^-' && len(gistnm) == 0
      if editpost == 1 || deletepost == 1
        let gistnm = arg
      elseif len(gistls) > 0 && arg != '^\w\+$\C'
        let gistls = arg
      elseif arg =~ '^[0-9a-z]\+$\C'
        let gistid = arg
      else
        echohl ErrorMsg | echomsg 'Invalid arguments' | echohl None
        unlet args
        return 0
      endif
    elseif len(arg) > 0
      echohl ErrorMsg | echomsg 'Invalid arguments' | echohl None
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
    call s:GistList(user, token, gistls, 1)
  elseif len(gistid) > 0 && editpost == 0 && deletepost == 0
    call s:GistGet(user, token, gistid, clipboard)
  else
    let url = ''
    if multibuffer == 1
      let url = s:GistPostBuffers(user, token, private)
    else
      if a:count < 1
        let content = join(getline(a:line1, a:line2), "\n")
      else
        let save_regcont = @"
        let save_regtype = getregtype('"')
        silent! normal! gvygv
        let content = @"
        call setreg('"', save_regcont, save_regtype)
      endif
      if editpost == 1
        let url = s:GistUpdate(user, token, content, gistid, gistnm)
      elseif deletepost == 1
        call s:GistDelete(user, token, gistid)
      else
        let url = s:GistPost(user, token, content, private)
      endif
    endif
    if len(url) > 0
      if g:gist_open_browser_after_post
        let cmd = substitute(g:gist_browser_command, '%URL%', url, 'g')
        if cmd =~ '^!'
          silent! exec cmd
        elseif cmd =~ '^:[A-Z]'
          exec cmd
        else
          call system(cmd)
        endif
      endif
      if g:gist_put_url_to_clipboard_after_post > 0
        if g:gist_put_url_to_clipboard_after_post == 2
          let url = url . "\n"
        endif
        if exists('g:gist_clip_command')
          call system(g:gist_clip_command, url)
        elseif has('unix') && !has('xterm_clipboard')
          let @" = url
        else
          let @+ = url
        endif
      endif
    endif
  endif
  return 1
endfunction

let s:extmap = {
\".adb": "ada",
\".ahk": "ahk",
\".arc": "arc",
\".as": "actionscript",
\".asm": "asm",
\".asp": "asp",
\".aw": "php",
\".b": "b",
\".bat": "bat",
\".befunge": "befunge",
\".bmx": "bmx",
\".boo": "boo",
\".c-objdump": "c-objdump",
\".c": "c",
\".cfg": "cfg",
\".cfm": "cfm",
\".ck": "ck",
\".cl": "cl",
\".clj": "clj",
\".cmake": "cmake",
\".coffee": "coffee",
\".cpp": "cpp",
\".cppobjdump": "cppobjdump",
\".cs": "csharp",
\".css": "css",
\".cw": "cw",
\".d-objdump": "d-objdump",
\".d": "d",
\".darcspatch": "darcspatch",
\".diff": "diff",
\".duby": "duby",
\".dylan": "dylan",
\".e": "e",
\".ebuild": "ebuild",
\".eclass": "eclass",
\".el": "lisp",
\".erb": "erb",
\".erl": "erlang",
\".f90": "f90",
\".factor": "factor",
\".feature": "feature",
\".fs": "fs",
\".fy": "fy",
\".go": "go",
\".groovy": "groovy",
\".gs": "gs",
\".gsp": "gsp",
\".haml": "haml",
\".hs": "haskell",
\".html": "html",
\".hx": "hx",
\".ik": "ik",
\".ino": "ino",
\".io": "io",
\".j": "j",
\".java": "java",
\".js": "javascript",
\".json": "json",
\".jsp": "jsp",
\".kid": "kid",
\".lhs": "lhs",
\".lisp": "lisp",
\".ll": "ll",
\".lua": "lua",
\".ly": "ly",
\".m": "objc",
\".mak": "mak",
\".man": "man",
\".mao": "mao",
\".matlab": "matlab",
\".md": "md",
\".minid": "minid",
\".ml": "ml",
\".moo": "moo",
\".mu": "mu",
\".mustache": "mustache",
\".mxt": "mxt",
\".myt": "myt",
\".n": "n",
\".nim": "nim",
\".nu": "nu",
\".numpy": "numpy",
\".objdump": "objdump",
\".ooc": "ooc",
\".parrot": "parrot",
\".pas": "pas",
\".pasm": "pasm",
\".pd": "pd",
\".phtml": "phtml",
\".pir": "pir",
\".pl": "perl",
\".po": "po",
\".py": "python",
\".pytb": "pytb",
\".pyx": "pyx",
\".r": "r",
\".raw": "raw",
\".rb": "ruby",
\".rhtml": "rhtml",
\".rkt": "rkt",
\".rs": "rs",
\".rst": "rst",
\".s": "s",
\".sass": "sass",
\".sc": "sc",
\".scala": "scala",
\".scm": "scheme",
\".scpt": "scpt",
\".scss": "scss",
\".self": "self",
\".sh": "sh",
\".sml": "sml",
\".sql": "sql",
\".st": "smalltalk",
\".tcl": "tcl",
\".tcsh": "tcsh",
\".tex": "tex",
\".textile": "textile",
\".tpl": "smarty",
\".twig": "twig",
\".txt" : "text",
\".v": "verilog",
\".vala": "vala",
\".vb": "vbnet",
\".vhd": "vhdl",
\".vim": "vim",
\".weechatlog": "weechatlog",
\".xml": "xml",
\".xq": "xquery",
\".xs": "xs",
\".yml": "yaml",
\}
let &cpo = s:save_cpo
unlet s:save_cpo

" vim:set et:
