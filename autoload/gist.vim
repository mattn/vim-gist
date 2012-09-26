"=============================================================================
" File: gist.vim
" Author: Yasuhiro Matsumoto <mattn.jp@gmail.com>
" Last Change: 27-Sep-2012.
" Version: 7.0
" WebPage: http://github.com/mattn/gist-vim
" License: BSD

let s:save_cpo = &cpo
set cpo&vim

let s:configfile = expand('~/.gist-vim')

if !exists('g:github_user')
  let s:system = function(get(g:, 'webapi#system_function', 'system'))
  let g:github_user = substitute(s:system('git config --get github.user'), "\n", '', '')
  if strlen(g:github_user) == 0
    let g:github_user = $GITHUB_USER
  end
endif

function! s:get_browser_command()
  let gist_browser_command = get(g:, 'gist_browser_command', '')
  if gist_browser_command == ''
    if has('win32') || has('win64')
      let gist_browser_command = '!start rundll32 url.dll,FileProtocolHandler %URL%'
    elseif has('mac') || has('macunix') || has('gui_macvim') || system('uname') =~? '^darwin'
      let gist_browser_command = 'open %URL%'
    elseif executable('xdg-open')
      let gist_browser_command = 'xdg-open %URL%'
    elseif executable('firefox')
      let gist_browser_command = 'firefox %URL% &'
    else
      let gist_browser_command = ''
    endif
  endif
  return gist_browser_command
endfunction

function! s:open_browser(url)
  let cmd = s:get_browser_command()
  if len(cmd) == 0
    redraw
    echohl WarningMsg
    echo "It seems that you don't have general web browser. Open URL below."
    echohl None
    echo a:url
    return
  endif
  if cmd =~ '^!'
    let cmd = substitute(cmd, '%URL%', '\=shellescape(a:url)', 'g')
    silent! exec cmd
  elseif cmd =~ '^:[A-Z]'
    let cmd = substitute(cmd, '%URL%', '\=a:url', 'g')
    exec cmd
  else
    let cmd = substitute(cmd, '%URL%', '\=shellescape(a:url)', 'g')
    call system(cmd)
  endif
endfunction

function! s:shellwords(str)
  let words = split(a:str, '\%(\([^ \t\''"]\+\)\|''\([^\'']*\)''\|"\(\%([^\"\\]\|\\.\)*\)"\)\zs\s*\ze')
  let words = map(words, 'substitute(v:val, ''\\\([\\ ]\)'', ''\1'', "g")')
  let words = map(words, 'matchstr(v:val, ''^\%\("\zs\(.*\)\ze"\|''''\zs\(.*\)\ze''''\|.*\)$'')')
  return words
endfunction

function! s:format_gist(gist)
  let files = sort(keys(a:gist.files))
  if empty(files)
    return ""
  endif
  let file = a:gist.files[files[0]]
  if has_key(file, "content")
    let code = file.content
    let code = "\n".join(map(split(code, "\n"), '"  ".v:val'), "\n")
  else
    let code = ""
  endif
  return printf("gist: %s %s%s", a:gist.id, type(a:gist.description)==0?"": a:gist.description, code)
endfunction

" Note: A colon in the file name has side effects on Windows due to NTFS Alternate Data Streams; avoid it.
let s:bufprefix = 'gist' . (has('unix') ? ':' : '_')
function! s:GistList(gistls, page)
  if a:gistls == '-all'
    let url = 'https://api.github.com/gists/public'
  elseif get(g:, 'gist_show_privates', 0) && a:gistls == 'starred'
    let url = 'https://api.github.com/gists/starred'
  elseif get(g:, 'gist_show_privates') && a:gistls == 'mine'
    let url = 'https://api.github.com/gists'
  else
    let url = 'https://api.github.com/users/'.a:gistls.'/gists'
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

  setlocal modifiable
  let old_undolevels = &undolevels
  let oldlines = []
  silent %d _

  redraw | echon 'Listing gists... '
  let auth = s:GistGetAuthHeader()
  if len(auth) == 0
    bw!
    redraw
    echohl ErrorMsg | echomsg 'Canceled' | echohl None
    return
  endif
  let res = webapi#http#get(url, '', { "Authorization": auth })
  if v:shell_error != 0
    bw!
    redraw
    echohl ErrorMsg | echomsg 'Gists not found' | echohl None
    return
  endif
  let content = webapi#json#decode(res.content)
  if type(content) == 4 && has_key(content, 'message') && len(content.message)
    bw!
    redraw
    echohl ErrorMsg | echomsg content.message | echohl None
    if content.message == 'Bad credentials'
      call delete(s:configfile)
    endif
    return
  endif

  let lines = map(filter(content, '!empty(v:val.files)'), 's:format_gist(v:val)')
  call setline(1, split(join(lines, "\n"), "\n"))

  $put='more...'

  let b:gistls = a:gistls
  let b:page = a:page
  setlocal buftype=nofile bufhidden=hide noswapfile
  setlocal nomodified
  setlocal nomodifiable
  syntax match SpecialKey /^gist:/he=e-1
  nnoremap <silent> <buffer> <cr> :call <SID>GistListAction(0)<cr>
  nnoremap <silent> <buffer> <s-cr> :call <SID>GistListAction(1)<cr>

  cal cursor(1+len(oldlines),1)
  nohlsearch
  redraw | echo ''
endfunction

function! gist#list(user, ...)
  let page = get(a:000, 0, 0)
  if a:user == '-all'
    let url = 'https://api.github.com/gists/public'
  elseif get(g:, 'gist_show_privates', 0) && a:user == 'starred'
    let url = 'https://api.github.com/gists/starred'
  elseif get(g:, 'gist_show_privates') && a:user == 'mine'
    let url = 'https://api.github.com/gists'
  else
    let url = 'https://api.github.com/users/'.a:user.'/gists'
  endif

  let auth = s:GistGetAuthHeader()
  if len(auth) == 0
    return []
  endif
  let res = webapi#http#get(url, '', { "Authorization": auth })
  return webapi#json#decode(res.content)
endfunction

function! s:GistGetFileName(gistid)
  let auth = s:GistGetAuthHeader()
  if len(auth) == 0
    return ''
  endif
  let res = webapi#http#get('https://api.github.com/gists/'.a:gistid, '', { "Authorization": auth })
  let gist = webapi#json#decode(res.content)
  if has_key(gist, 'files')
    return sort(keys(gist.files))[0]
  endif
  return ''
endfunction

function! s:GistDetectFiletype(gistid)
  let auth = s:GistGetAuthHeader()
  if len(auth) == 0
    return ''
  endif
  let res = webapi#http#get('https://api.github.com/gists/'.a:gistid, '', { "Authorization": auth })
  let gist = webapi#json#decode(res.content)
  let filename = sort(keys(gist.files))[0]
  let ext = fnamemodify(filename, ':e')
  if has_key(s:extmap, ext)
    let type = s:extmap[ext]
  else
    let type = get(gist.files[filename], "type", "text")
  endif
  silent! exec "setlocal ft=".tolower(type)
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

function! s:GistGet(gistid, clipboard)
  redraw | echon 'Getting gist... '
  let res = webapi#http#get('https://api.github.com/gists/'.a:gistid, '', { "Authorization": s:GistGetAuthHeader() })
  let status = matchstr(matchstr(res.header, '^Status:'), '^[^:]\+: \zs.*')
  if status =~ '^2'
    let gist = webapi#json#decode(res.content)
    if get(g:, 'gist_get_multiplefile', 0) != 0
      let num_file = len(keys(gist.files))
    else
      let num_file = 1
    endif
    redraw
    if num_file > len(keys(gist.files))
      echohl ErrorMsg | echomsg 'Gist not found' | echohl None
      return
    endif
    for n in range(num_file)
      try
        let old_undolevels = &undolevels
        let filename = sort(keys(gist.files))[n]

        let winnum = bufwinnr(bufnr(s:bufprefix.a:gistid."/".filename))
        if winnum != -1
          if winnum != bufwinnr('%')
            exe winnum 'wincmd w'
          endif
          setlocal modifiable
        else
          exec 'silent noautocmd new'
          setlocal noswapfile
          exec 'noautocmd file' s:bufprefix.a:gistid."/".fnameescape(filename)
        endif
        set undolevels=-1
        filetype detect
        silent %d _

        let content = gist.files[filename].content
        call setline(1, split(content, "\n"))
        let b:gist = {
        \ "filename": filename,
        \ "id": gist.id,
        \ "description": gist.description,
        \ "private": gist.public =~ 'true',
        \}
      catch
        let &undolevels = old_undolevels
        bw!
        redraw
        echohl ErrorMsg | echomsg 'Gist contains binary' | echohl None
        return
      endtry
      let &undolevels = old_undolevels
      setlocal buftype=acwrite bufhidden=delete noswapfile
      setlocal nomodified
      doau StdinReadPost,BufRead,BufReadPost
      let gist_detect_filetype = get(g:, 'gist_detect_filetype', 0)
      if (&ft == '' && gist_detect_filetype == 1) || gist_detect_filetype == 2
        call s:GistDetectFiletype(a:gistid)
      endif
      if a:clipboard
        if exists('g:gist_clip_command')
          exec 'silent w !'.g:gist_clip_command
        elseif has('clipboard')
          silent! %yank +
        else
          %yank
        endif
      endif
      1
      au! BufWriteCmd <buffer> call s:GistWrite(expand("<amatch>"))
    endfor
  else
    bw!
    redraw
    echohl ErrorMsg | echomsg 'Gist not found' | echohl None
    return
  endif
endfunction

function! s:GistListAction(shift)
  let line = getline('.')
  let mx = '^gist:\s*\zs\(\w\+\)\ze.*'
  if line =~# mx
    let gistid = matchstr(line, mx)
    if a:shift
      call s:open_browser("https://gist.github.com/" . gistid)
    else
      call s:GistGet(gistid, 0)
    endif
    return
  endif
  if line =~# '^more\.\.\.$'
    call s:GistList(b:gistls, b:page+1)
    return
  endif
endfunction

function! s:GistUpdate(content, gistid, gistnm, desc)
  let gist = { "id": a:gistid, "files" : {}, "description": "","public": function('webapi#json#true') }
  if exists('b:gist')
    if has_key(b:gist, 'private') && b:gist.private | let gist["public"] = function('webapi#json#false') | endif
    if has_key(b:gist, 'description') | let gist["description"] = b:gist.description | endif
    if has_key(b:gist, 'filename') | let filename = b:gist.filename | endif
  else
    let filename = a:gistnm
    if len(filename) == 0 | let filename = s:GistGetFileName(a:gistid) | endif
    if len(filename) == 0 | let filename = s:get_current_filename(1) | endif
  endif

  let auth = s:GistGetAuthHeader()
  if len(auth) == 0
    redraw
    echohl ErrorMsg | echomsg 'Canceled' | echohl None
    return
  endif

  " Update description
  " If no new description specified, keep the old description
  if a:desc != ' '
    let gist["description"] = a:desc
  else
    let res = webapi#http#get('https://api.github.com/gists/'.a:gistid, '', { "Authorization": auth })
    let status = matchstr(matchstr(res.header, '^Status:'), '^[^:]\+: \zs.*')
    if status =~ '^2'
      let old_gist = webapi#json#decode(res.content)
      let gist["description"] = old_gist.description
    endif
  endif

  let gist.files[filename] = { "content": a:content, "filename": filename }

  redraw | echon 'Updating gist... '
  let res = webapi#http#post('https://api.github.com/gists/' . a:gistid,
  \ webapi#json#encode(gist), {
  \   "Authorization": auth,
  \   "Content-Type": "application/json",
  \})
  let status = matchstr(matchstr(res.header, '^Status:'), '^[^:]\+: \zs.*')
  if status =~ '^2'
    let obj = webapi#json#decode(res.content)
    let loc = obj["html_url"]
    redraw | echomsg 'Done: '.loc
    let b:gist = {"id": a:gistid, "filename": filename}
    setlocal nomodified
  else
    let loc = ''
    let status = matchstr(status, '^\d\+\s*\zs.*')
    echohl ErrorMsg | echomsg 'Post failed: '.status | echohl None
  endif
  return loc
endfunction

function! s:GistDelete(gistid)
  let auth = s:GistGetAuthHeader()
  if len(auth) == 0
    redraw
    echohl ErrorMsg | echomsg 'Canceled' | echohl None
    return
  endif

  redraw | echon 'Deleting gist... '
  let res = webapi#http#post('https://api.github.com/gists/'.a:gistid, '', {
  \   "Authorization": auth,
  \   "Content-Type": "application/json",
  \}, 'DELETE')
  let status = matchstr(matchstr(res.header, '^Status:'), '^[^:]\+: \zs.*')
  if status =~ '^2'
    redraw | echomsg 'Done: '
    if exists('b:gist')
      unlet b:gist
    endif
  else
    let status = matchstr(status, '^\d\+\s*\zs.*')
    echohl ErrorMsg | echomsg 'Delete failed: '.status | echohl None
  endif
endfunction

function! s:get_current_filename(no)
  let filename = expand('%:t')
  if len(filename) == 0 && &ft != ''
    let pair = filter(items(s:extmap), 'v:val[1] == &ft')
    if len(pair) > 0
      let filename = printf('gistfile%d%s', a:no, pair[0][0])
    endif
  endif
  if filename == ''
    let filename = printf('gistfile%d.txt', a:no)
  endif
  return filename
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
function! s:GistPost(content, private, desc, anonymous)
  let gist = { "files" : {}, "description": "","public": function('webapi#json#true') }
  if a:desc != ' ' | let gist["description"] = a:desc | endif
  if a:private | let gist["public"] = function('webapi#json#false') | endif
  let filename = s:get_current_filename(1)
  let gist.files[filename] = { "content": a:content, "filename": filename }

  let header = {"Content-Type": "application/json"}
  if !a:anonymous
    let auth = s:GistGetAuthHeader()
    if len(auth) == 0
      redraw
      echohl ErrorMsg | echomsg 'Canceled' | echohl None
      return
    endif
    let header["Authorization"] = auth
  endif

  redraw | echon 'Posting it to gist... '
  let res = webapi#http#post('https://api.github.com/gists', webapi#json#encode(gist), header)
  let status = matchstr(matchstr(res.header, '^Status:'), '^[^:]\+: \zs.*')
  if status =~ '^2'
    let obj = webapi#json#decode(res.content)
    let loc = obj["html_url"]
    redraw | echomsg 'Done: '.loc
    let b:gist = {
    \ "filename": filename,
    \ "id": matchstr(loc, '[^/]\+$'),
    \ "description": gist['description'],
    \ "private": a:private,
    \}
  else
    let loc = ''
    let status = matchstr(status, '^\d\+\s*\zs.*')
    echohl ErrorMsg | echomsg 'Post failed: '.status | echohl None
  endif
  return loc
endfunction

function! s:GistPostBuffers(private, desc, anonymous)
  let bufnrs = range(1, bufnr("$"))
  let bn = bufnr('%')
  let query = []

  let gist = { "files" : {}, "description": "","public": function('webapi#json#true') }
  if a:desc != ' ' | let gist["description"] = a:desc | endif
  if a:private | let gist["public"] = function('webapi#json#false') | endif

  let index = 1
  for bufnr in bufnrs
    if !bufexists(bufnr) || buflisted(bufnr) == 0
      continue
    endif
    echo "Creating gist content".index."... "
    silent! exec "buffer!" bufnr
    let content = join(getline(1, line('$')), "\n")
    let filename = s:get_current_filename(index)
    let gist.files[filename] = { "content": content, "filename": filename }
    let index = index + 1
  endfor
  silent! exec "buffer!" bn

  let header = {"Content-Type": "application/json"}
  if !a:anonymous
    let auth = s:GistGetAuthHeader()
    if len(auth) == 0
      redraw
      echohl ErrorMsg | echomsg 'Canceled' | echohl None
      return
    endif
    let header["Authorization"] = auth
  endif

  redraw | echon 'Posting it to gist... '
  let res = webapi#http#post('https://api.github.com/gists', webapi#json#encode(gist), header)
  let status = matchstr(matchstr(res.header, '^Status:'), '^[^:]\+: \zs.*')
  if status =~ '^2'
    let obj = webapi#json#decode(res.content)
    let loc = obj["html_url"]
    redraw | echomsg 'Done: '.loc
    let b:gist = {"id": matchstr(loc, '[^/]\+$'), "filename": filename, "private": a:private}
  else
    let loc = ''
    let status = matchstr(status, '^\d\+\s*\zs.*')
    echohl ErrorMsg | echomsg 'Post failed: '.status | echohl None
  endif
  return loc
endfunction

function! gist#Gist(count, line1, line2, ...)
  redraw
  if strlen(g:github_user) == 0
    echohl ErrorMsg | echomsg "You don't have github account. read ':help gist-vim-setup'." | echohl None
    return
  endif
  let bufname = bufname("%")
  " find GistID: in content , then we should just update
  let gistid = ''
  let gistls = ''
  let gistnm = ''
  let gistdesc = ' '
  let private = get(g:, 'gist_post_private', 0)
  let multibuffer = 0
  let clipboard = 0
  let deletepost = 0
  let editpost = 0
  let anonymous = 0
  let listmx = '^\%(-l\|--list\)\s*\([^\s]\+\)\?$'
  let bufnamemx = '^' . s:bufprefix .'\(\zs[0-9a-f]\+\ze\|\zs[0-9a-f]\+\ze[/\\].*\)$'
  if bufname =~ bufnamemx
    let gistidbuf = matchstr(bufname, bufnamemx)
  else
    let gistidbuf = matchstr(join(getline(a:line1, a:line2), "\n"), 'GistID:\s*\zs\w\+')
  endif

  let args = (a:0 > 0) ? s:shellwords(a:1) : []
  for arg in args
    if arg =~ '^\(-h\|--help\)$\C'
      help :Gist
      return
    elseif arg =~ '^\(-la\|--listall\)$\C'
      let gistls = '-all'
    elseif arg =~ '^\(-ls\|--liststar\)$\C'
      let gistls = 'starred'
    elseif arg =~ '^\(-l\|--list\)$\C'
      if get(g:, 'gist_show_privates')
        let gistls = 'mine'
      else
        let gistls = g:github_user
      endif
    elseif arg =~ '^\(-m\|--multibuffer\)$\C'
      let multibuffer = 1
    elseif arg =~ '^\(-p\|--private\)$\C'
      let private = 1
    elseif arg =~ '^\(-P\|--public\)$\C'
      let private = 0
    elseif arg =~ '^\(-a\|--anonymous\)$\C'
      let anonymous = 1
    elseif arg =~ '^\(-s\|--description\)$\C'
      let gistdesc = ''
    elseif arg =~ '^\(-c\|--clipboard\)$\C'
      let clipboard = 1
    elseif arg =~ '^\(-d\|--delete\)$\C' && gistidbuf != ''
      let gistid = gistidbuf
      let deletepost = 1
    elseif arg =~ '^\(-e\|--edit\)$\C' && gistidbuf != ''
      let gistid = gistidbuf
      let editpost = 1
    elseif arg =~ '^\(+1\|--star\)$\C' && gistidbuf != ''
      let auth = s:GistGetAuthHeader()
      if len(auth) == 0
        echohl ErrorMsg | echomsg 'Canceled' | echohl None
      else
        let gistid = gistidbuf
        let res = webapi#http#post('https://api.github.com/gists/'.gistid.'/star', '', { "Authorization": auth }, 'PUT')
        let status = matchstr(matchstr(res.header, '^Status:'), '^[^:]\+: \zs.*')
        if status =~ '^2'
          echomsg "Stared" gistid
        else
          echohl ErrorMsg | echomsg 'Star failed' | echohl None
        endif
      endif
      return
    elseif arg =~ '^\(-1\|--unstar\)$\C' && gistidbuf != ''
      let auth = s:GistGetAuthHeader()
      if len(auth) == 0
        echohl ErrorMsg | echomsg 'Canceled' | echohl None
      else
        let gistid = gistidbuf
        let res = webapi#http#post('https://api.github.com/gists/'.gistid.'/star', '', { "Authorization": auth }, 'DELETE')
        if status =~ '^2'
          echomsg "Unstared" gistid
        else
          echohl ErrorMsg | echomsg 'Unstar failed' | echohl None
        endif
      endif
      return
    elseif arg =~ '^\(-f\|--fork\)$\C' && gistidbuf != ''
      let auth = s:GistGetAuthHeader()
      if len(auth) == 0
        echohl ErrorMsg | echomsg 'Canceled' | echohl None
        return
      else
        let gistid = gistidbuf
        let res = webapi#http#post('https://api.github.com/gists/'.gistid.'/fork', '', { "Authorization": auth })
        let status = matchstr(matchstr(res.header, '^Status:'), '^[^:]\+: \zs.*')
        if status =~ '^2'
          let obj = webapi#json#decode(res.content)
          let gistid = obj["id"]
        else
          echohl ErrorMsg | echomsg 'Fork failed' | echohl None
          return
        endif
      endif
    elseif arg !~ '^-' && len(gistnm) == 0
      if gistdesc != ' '
        let gistdesc = matchstr(arg, '^\s*\zs.*\ze\s*$')
      elseif editpost == 1 || deletepost == 1
        let gistnm = arg
      elseif len(gistls) > 0 && arg != '^\w\+$\C'
        let gistls = arg
      elseif arg =~ '^[0-9a-z]\+$\C'
        let gistid = arg
      else
        echohl ErrorMsg | echomsg 'Invalid arguments: '.arg | echohl None
        unlet args
        return 0
      endif
    elseif len(arg) > 0
      echohl ErrorMsg | echomsg 'Invalid arguments: '.arg | echohl None
      unlet args
      return 0
    endif
  endfor
  unlet args
  "echo "gistid=".gistid
  "echo "gistls=".gistls
  "echo "gistnm=".gistnm
  "echo "gistdesc=".gistdesc
  "echo "private=".private
  "echo "clipboard=".clipboard
  "echo "editpost=".editpost
  "echo "deletepost=".deletepost

  if gistidbuf != '' && gistid == '' && editpost == 0 && deletepost == 0
    let editpost = 1
    let gistid = gistidbuf
  endif

  if len(gistls) > 0
    call s:GistList(gistls, 1)
  elseif len(gistid) > 0 && editpost == 0 && deletepost == 0
    call s:GistGet(gistid, clipboard)
  else
    let url = ''
    if multibuffer == 1
      let url = s:GistPostBuffers(private, gistdesc, anonymous)
    else
      if a:count < 1
        let content = join(getline(a:line1, a:line2), "\n")
      else
        let save_regcont = @"
        let save_regtype = getregtype('"')
        silent! normal! gvy
        let content = @"
        call setreg('"', save_regcont, save_regtype)
      endif
      if editpost == 1
        let url = s:GistUpdate(content, gistid, gistnm, gistdesc)
      elseif deletepost == 1
        call s:GistDelete(gistid)
      else
        let url = s:GistPost(content, private, gistdesc, anonymous)
      endif
      if a:count >= 1 && get(g:, 'gist_keep_selection', 0) == 1
        silent! normal! gv
      endif
    endif
    if len(url) > 0
      if get(g:, 'gist_open_browser_after_post', 0) == 1
        call s:open_browser(url)
      endif
      let gist_put_url_to_clipboard_after_post = get(g:, 'gist_put_url_to_clipboard_after_post', 1)
      if gist_put_url_to_clipboard_after_post > 0
        if gist_put_url_to_clipboard_after_post == 2
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

function! s:GistGetAuthHeader()
  if get(g:, 'gist_use_password_in_gitconfig', 0) != 0
    let password = substitute(system('git config --get github.password'), "\n", '', '')
    if password =~ '^!' | let password = system(password[1:]) | endif
    return printf("basic %s", webapi#base64#b64encode(g:github_user.":".password))
  endif
  let auth = ""
  if filereadable(s:configfile)
    let str = join(readfile(s:configfile), "")
    if type(str) == 1
      let auth = str
    endif
  endif
  if len(auth) > 0
    return auth
  endif

  redraw
  echohl WarningMsg
  echo 'Gist.vim requires authorization to use the Github API. These settings are stored in "~/.gist-vim". If you want to revoke, do "rm ~/.gist-vim".'
  echohl None
  let password = inputsecret("Github Password for ".g:github_user.":")
  if len(password) > 0
    let insecureSecret = printf("basic %s", webapi#base64#b64encode(g:github_user.":".password))
    let res = webapi#http#post('https://api.github.com/authorizations', webapi#json#encode({
                \  "scopes"   : ["gist"],
                \  "note"     : "Gist.vim on ".hostname(),
                \  "note_url" : "http://www.vim.org/scripts/script.php?script_id=2423"
                \}), {
                \  "Content-Type"  : "application/json",
                \  "Authorization" : insecureSecret,
                \})
    let authorization = webapi#json#decode(res.content)
    if has_key(authorization, 'token')
      let secret = printf("token %s", authorization.token)
      call writefile([secret], s:configfile)
      if !(has('win32') || has('win64'))
        call system("chmod go= ".s:configfile)
      endif
    elseif has_key(authorization, 'message')
      echohl WarningMsg
      echo authorization.message
      echohl None
      let secret = ''
    endif
  else
    let secret = ''
  endif
  return secret
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
\".md": "markdown",
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
