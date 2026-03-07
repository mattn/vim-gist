"=============================================================================
" File: gist.vim
" Author: Yasuhiro Matsumoto <mattn.jp@gmail.com>
" Last Change: 10-Oct-2016.
" Version: 7.3
" WebPage: http://github.com/mattn/vim-gist
" License: BSD

let s:save_cpo = &cpoptions
set cpoptions&vim

if exists('g:gist_disabled') && g:gist_disabled == 1
  function! gist#Gist(...) abort
  endfunction
  finish
endif

if !exists('g:github_user') && !executable('git')
  echohl ErrorMsg | echomsg 'Gist: require ''git'' command' | echohl None
  finish
endif

if !executable('curl')
  echohl ErrorMsg | echomsg 'Gist: require ''curl'' command' | echohl None
  finish
endif

if globpath(&rtp, 'autoload/webapi/http.vim') ==# ''
  echohl ErrorMsg | echomsg 'Gist: require ''webapi'', install https://github.com/mattn/webapi-vim' | echohl None
  finish
else
  call webapi#json#true()
endif

if exists('g:gist_token_file')
  let s:gist_token_file = expand(g:gist_token_file)
elseif filereadable(expand('~/.gist-vim'))
  let s:gist_token_file = expand('~/.gist-vim')
elseif has('win32') || has('win64')
  let s:gist_token_file = expand('$APPDATA/vim-gist.json')
else
  let s:gist_token_file = expand('~/.config/vim-gist.json')
endif
let s:system = function(get(g:, 'webapi#system_function', 'system'))

if !exists('g:github_user')
  let g:github_user = substitute(s:system('git config --get github.user'), "\n", '', '')
  if strlen(g:github_user) == 0
    let g:github_user = $GITHUB_USER
  end
endif

if !exists('g:gist_api_url')
  let g:gist_api_url = substitute(s:system('git config --get github.apiurl'), "\n", '', '')
  if strlen(g:gist_api_url) == 0
    let g:gist_api_url = 'https://api.github.com/'
  end
  if exists('g:github_api_url') && !exists('g:gist_shutup_issue154')
    if matchstr(g:gist_api_url, 'https\?://\zs[^/]\+\ze') != matchstr(g:github_api_url, 'https\?://\zs[^/]\+\ze')
      echohl WarningMsg
      echo '--- Warning ---'
      echo 'It seems that you set different URIs for github_api_url/gist_api_url.'
      echo 'If you want to remove this message: let g:gist_shutup_issue154 = 1'
      echohl None
      if confirm('Continue?', '&Yes\n&No') != 1
        let g:gist_disabled = 1
        finish
      endif
      redraw!
    endif
  endif
endif
if g:gist_api_url !~# '/$'
  let g:gist_api_url .= '/'
endif

if !exists('g:gist_update_on_write')
  let g:gist_update_on_write = 1
endif

function! s:get_browser_command() abort
  let l:gist_browser_command = get(g:, 'gist_browser_command', '')
  if l:gist_browser_command ==# ''
    if has('win32') || has('win64')
      let l:gist_browser_command = '!start rundll32 url.dll,FileProtocolHandler %URL%'
    elseif has('mac') || has('macunix') || has('gui_macvim') || system('uname') =~? '^darwin'
      let l:gist_browser_command = 'open %URL%'
    elseif executable('xdg-open')
      let l:gist_browser_command = 'xdg-open %URL%'
    elseif executable('firefox')
      let l:gist_browser_command = 'firefox %URL% &'
    else
      let l:gist_browser_command = ''
    endif
  endif
  return l:gist_browser_command
endfunction

function! s:open_browser(url) abort
  let l:cmd = s:get_browser_command()
  if len(l:cmd) == 0
    redraw
    echohl WarningMsg
    echo 'It seems that you don''t have general web browser. Open URL below.'
    echohl None
    echo a:url
    return
  endif
  let l:quote = &shellxquote == '"' ?  "'" : '"'
  if l:cmd =~# '^!'
    let l:cmd = substitute(l:cmd, '%URL%', '\=l:quote.a:url.l:quote', 'g')
    silent! exec l:cmd
  elseif l:cmd =~# '^:[A-Z]'
    let l:cmd = substitute(l:cmd, '%URL%', '\=a:url', 'g')
    exec l:cmd
  else
    let l:cmd = substitute(l:cmd, '%URL%', '\=l:quote.a:url.l:quote', 'g')
    call system(l:cmd)
  endif
endfunction

function! s:shellwords(str) abort
  let l:words = split(a:str, '\%(\([^ \t\''"]\+\)\|''\([^\'']*\)''\|"\(\%([^\"\\]\|\\.\)*\)"\)\zs\s*\ze')
  let l:words = map(l:words, 'substitute(v:val, ''\\\([\\ ]\)'', ''\1'', "g")')
  let l:words = map(l:words, 'matchstr(v:val, ''^\%\("\zs\(.*\)\ze"\|''''\zs\(.*\)\ze''''\|.*\)$'')')
  return l:words
endfunction

function! s:truncate(str, num)
  let l:mx_first = '^\(.\)\(.*\)$'
  let l:str = a:str
  let l:ret = ''
  let l:width = 0
  while 1
    let l:char = substitute(l:str, l:mx_first, '\1', '')
    let l:cells = strdisplaywidth(l:char)
    if l:cells == 0 || l:width + l:cells > a:num
      break
    endif
    let l:width = l:width + l:cells
    let l:ret .= l:char
    let l:str = substitute(l:str, l:mx_first, '\2', '')
  endwhile
  while l:width + 1 <= a:num
    let l:ret .= ' '
    let l:width = l:width + 1
  endwhile
  return l:ret
endfunction

function! s:format_gist(gist) abort
  let l:files = sort(keys(a:gist.files))
  if empty(l:files)
    return ''
  endif
  let l:file = a:gist.files[l:files[0]]
  let l:name = l:file.filename
  if has_key(l:file, 'content')
    let l:code = l:file.content
    let l:code = "\n".join(map(split(l:code, "\n"), '"  ".v:val'), "\n")
  else
    let l:code = ''
  endif
  let l:desc = type(a:gist.description)==0 || a:gist.description ==# '' ? '' : a:gist.description
  let l:name = substitute(l:name, '[\r\n\t]', ' ', 'g')
  let l:name = substitute(l:name, '  ', ' ', 'g')
  let l:desc = substitute(l:desc, '[\r\n\t]', ' ', 'g')
  let l:desc = substitute(l:desc, '  ', ' ', 'g')
  " Display a nice formatted (and truncated if needed) table of gists on screen
  " Calculate field lengths for gist-listing formatting on screen
  redir =>l:a |exe 'sil sign place buffer='.bufnr('')|redir end
  let l:signlist = split(l:a, '\n')
  let l:width = winwidth(0) - ((&number||&relativenumber) ? &numberwidth : 0) - &foldcolumn - (len(l:signlist) > 2 ? 2 : 0)
  let l:idlen = 33
  let l:namelen = get(g:, 'gist_namelength', 30)
  let l:desclen = l:width - (l:idlen + l:namelen + 10)
  return printf('gist: %s %s %s', s:truncate(a:gist.id, l:idlen), s:truncate(l:name, l:namelen), s:truncate(l:desc, l:desclen))
endfunction

" Note: A colon in the file name has side effects on Windows due to NTFS Alternate Data Streams; avoid it.
let s:bufprefix = 'gist' . (has('unix') ? ':' : '_')
function! s:GistList(gistls, page, pagelimit) abort
  if a:gistls ==# '-all'
    let l:url = g:gist_api_url.'gists/public'
  elseif get(g:, 'gist_show_privates', 0) && a:gistls ==# 'starred'
    let l:url = g:gist_api_url.'gists/starred'
  elseif get(g:, 'gist_show_privates') && a:gistls ==# 'mine'
    let l:url = g:gist_api_url.'gists'
  else
    let l:url = g:gist_api_url.'users/'.a:gistls.'/gists'
  endif
  let l:winnum = bufwinnr(bufnr(s:bufprefix.a:gistls))
  if l:winnum != -1
    if l:winnum != bufwinnr('%')
      exe l:winnum 'wincmd w'
    endif
    setlocal modifiable
  else
    if get(g:, 'gist_list_vsplit', 0)
      exec 'silent noautocmd vsplit +set\ winfixwidth ' s:bufprefix.a:gistls
    elseif get(g:, 'gist_list_rightbelow', 0)
      exec 'silent noautocmd rightbelow 5 split +set\ winfixheight ' s:bufprefix.a:gistls
    else
      exec 'silent noautocmd split' s:bufprefix.a:gistls
    endif
  endif

  let l:url = l:url . '?per_page=' . a:pagelimit
  if a:page > 1
    let l:oldlines = getline(0, line('$'))
    let l:url = l:url . '&page=' . a:page
  endif

  setlocal modifiable
  let l:old_undolevels = &undolevels
  let l:oldlines = []
  silent %d _

  redraw | echon 'Listing gists... '
  let l:auth = s:GistGetAuthHeader()
  if len(l:auth) == 0
    bw!
    redraw
    echohl ErrorMsg | echomsg v:errmsg | echohl None
    return
  endif
  let l:res = webapi#http#get(l:url, '', { 'Authorization': l:auth })
  if v:shell_error != 0
    bw!
    redraw
    echohl ErrorMsg | echomsg 'Gists not found' | echohl None
    return
  endif
  let l:content = webapi#json#decode(l:res.content)
  if type(l:content) == 4 && has_key(l:content, 'message') && len(l:content.message)
    bw!
    redraw
    echohl ErrorMsg | echomsg l:content.message | echohl None
    if l:content.message ==# 'Bad credentials'
      call delete(s:gist_token_file)
    endif
    return
  endif

  let l:lines = map(filter(l:content, '!empty(v:val.files)'), 's:format_gist(v:val)')
  call setline(1, split(join(l:lines, "\n"), "\n"))

  $put='more...'

  let b:gistls = a:gistls
  let b:page = a:page
  setlocal buftype=nofile bufhidden=hide noswapfile
  setlocal cursorline
  setlocal nomodified
  setlocal nomodifiable
  syntax match SpecialKey /^gist:/he=e-1
  syntax match Title /^gist: \S\+/hs=s+5 contains=ALL
  nnoremap <silent> <buffer> <cr> :call <SID>GistListAction(0)<cr>
  nnoremap <silent> <buffer> o :call <SID>GistListAction(0)<cr>
  nnoremap <silent> <buffer> b :call <SID>GistListAction(1)<cr>
  nnoremap <silent> <buffer> y :call <SID>GistListAction(2)<cr>
  nnoremap <silent> <buffer> p :call <SID>GistListAction(3)<cr>
  nnoremap <silent> <buffer> <esc> :bw<cr>
  nnoremap <silent> <buffer> <s-cr> :call <SID>GistListAction(1)<cr>

  cal cursor(1+len(l:oldlines),1)
  nohlsearch
  redraw | echo ''
endfunction

function! gist#list_recursively(user, ...) abort
  let l:use_cache = get(a:000, 0, 1)
  let l:limit = get(a:000, 1, -1)
  let l:verbose = get(a:000, 2, 1)
  if a:user ==# 'mine'
    let l:url = g:gist_api_url . 'gists'
  elseif a:user ==# 'starred'
    let l:url = g:gist_api_url . 'gists/starred'
  else
    let l:url = g:gist_api_url.'users/'.a:user.'/gists'
  endif

  let l:auth = s:GistGetAuthHeader()
  if len(l:auth) == 0
    " anonymous user cannot get gists to prevent infinite recursive loading
    return []
  endif

  if l:use_cache && exists('g:gist_list_recursively_cache')
    if has_key(g:gist_list_recursively_cache, a:user)
      return webapi#json#decode(g:gist_list_recursively_cache[a:user])
    endif
  endif

  let l:page = 1
  let l:gists = []
  let l:lastpage = -1

  function! s:get_lastpage(res) abort
    let l:links = split(a:res.header[match(a:res.header, 'Link')], ',')
    let l:link = l:links[match(l:links, 'rel=[''"]last[''"]')]
    let l:page = str2nr(matchlist(l:link, '\%(page=\)\(\d\+\)')[1])
    return l:page
  endfunction

  if l:verbose > 0
    redraw | echon 'Loading gists...'
  endif

  while l:limit == -1 || l:page <= l:limit
    let l:res = webapi#http#get(l:url.'?page='.l:page, '', {'Authorization': l:auth})
    if l:limit == -1
      " update limit to the last page
      let l:limit = s:get_lastpage(l:res)
    endif
    if l:verbose > 0
      redraw | echon 'Loading gists... ' . l:page . '/' . l:limit . ' pages has loaded.'
    endif
    let l:gists = l:gists + webapi#json#decode(l:res.content)
    let l:page = l:page + 1
  endwhile
  let g:gist_list_recursively_cache = get(g:, 'gist_list_recursively_cache', {})
  let g:gist_list_recursively_cache[a:user] = webapi#json#encode(l:gists)
  return l:gists
endfunction

function! gist#list(user, ...) abort
  let l:page = get(a:000, 0, 0)
  if a:user ==# '-all'
    let l:url = g:gist_api_url.'gists/public'
  elseif get(g:, 'gist_show_privates', 0) && a:user ==# 'starred'
    let l:url = g:gist_api_url.'gists/starred'
  elseif get(g:, 'gist_show_privates') && a:user ==# 'mine'
    let l:url = g:gist_api_url.'gists'
  else
    let l:url = g:gist_api_url.'users/'.a:user.'/gists'
  endif

  let l:auth = s:GistGetAuthHeader()
  if len(l:auth) == 0
    return []
  endif
  let l:res = webapi#http#get(l:url, '', { 'Authorization': l:auth })
  return webapi#json#decode(l:res.content)
endfunction

function! s:GistGetFileName(gistid) abort
  let l:auth = s:GistGetAuthHeader()
  if len(l:auth) == 0
    return ''
  endif
  let l:res = webapi#http#get(g:gist_api_url.'gists/'.a:gistid, '', { 'Authorization': l:auth })
  let l:gist = webapi#json#decode(l:res.content)
  if has_key(l:gist, 'files')
    return sort(keys(l:gist.files))[0]
  endif
  return ''
endfunction

function! s:GistDetectFiletype(gistid) abort
  let l:auth = s:GistGetAuthHeader()
  if len(l:auth) == 0
    return ''
  endif
  let l:res = webapi#http#get(g:gist_api_url.'gists/'.a:gistid, '', { 'Authorization': l:auth })
  let l:gist = webapi#json#decode(l:res.content)
  let l:filename = sort(keys(l:gist.files))[0]
  let l:ext = fnamemodify(l:filename, ':e')
  if has_key(s:extmap, l:ext)
    let l:type = s:extmap[l:ext]
  else
    let l:type = get(l:gist.files[l:filename], 'type', 'text')
  endif
  silent! exec 'setlocal ft='.tolower(l:type)
endfunction

function! s:GistWrite(fname) abort
  if substitute(a:fname, '\\', '/', 'g') == expand("%:p:gs@\\@/@")
    if g:gist_update_on_write != 2 || v:cmdbang
      Gist -e
    else
      echohl ErrorMsg | echomsg 'Please type ":w!" to update a gist.' | echohl None
    endif
  else
    exe 'w'.(v:cmdbang ? '!' : '') fnameescape(v:cmdarg) fnameescape(a:fname)
    silent! exe 'file' fnameescape(a:fname)
    silent! au! BufWriteCmd <buffer>
  endif
endfunction

function! s:GistGet(gistid, clipboard) abort
  redraw | echon 'Getting gist... '
  let l:res = webapi#http#get(g:gist_api_url.'gists/'.a:gistid, '', { 'Authorization': s:GistGetAuthHeader() })
  if l:res.status =~# '^2'
    try
      let l:gist = webapi#json#decode(l:res.content)
    catch
      redraw
      echohl ErrorMsg | echomsg 'Gist seems to be broken' | echohl None
      return
    endtry
    if get(g:, 'gist_get_multiplefile', 0) != 0
      let l:num_file = len(keys(l:gist.files))
    else
      let l:num_file = 1
    endif
    redraw
    if l:num_file > len(keys(l:gist.files))
      echohl ErrorMsg | echomsg 'Gist not found' | echohl None
      return
    endif
    augroup GistWrite
      au!
    augroup END
    for l:n in range(l:num_file)
      try
        let l:old_undolevels = &undolevels
        let l:filename = sort(keys(l:gist.files))[l:n]

        let l:winnum = bufwinnr(bufnr(s:bufprefix.a:gistid.'/'.l:filename))
        if l:winnum != -1
          if l:winnum != bufwinnr('%')
            exe l:winnum 'wincmd w'
          endif
          setlocal modifiable
        else
          if l:num_file == 1
            if get(g:, 'gist_edit_with_buffers', 0)
              let l:found = -1
              for l:wnr in range(1, winnr('$'))
                let l:bnr = winbufnr(l:wnr)
                if l:bnr != -1 && !empty(getbufvar(l:bnr, 'gist'))
                  let l:found = l:wnr
                  break
                endif
              endfor
              if l:found != -1
                exe l:found 'wincmd w'
                setlocal modifiable
              else
                if get(g:, 'gist_list_vsplit', 0)
                  exec 'silent noautocmd rightbelow vnew'
                else
                  exec 'silent noautocmd rightbelow new'
                endif
              endif
            else
              silent only!
              if get(g:, 'gist_list_vsplit', 0)
                exec 'silent noautocmd rightbelow vnew'
              else
                exec 'silent noautocmd rightbelow new'
              endif
            endif
          else
            if get(g:, 'gist_list_vsplit', 0)
              exec 'silent noautocmd rightbelow vnew'
            else
              exec 'silent noautocmd rightbelow new'
            endif
          endif
          setlocal noswapfile
          silent exec 'noautocmd file' s:bufprefix.a:gistid.'/'.fnameescape(l:filename)
        endif
        set undolevels=-1
        filetype detect
        silent %d _

        let l:content = l:gist.files[l:filename].content
        call setline(1, split(l:content, "\n"))
        let b:gist = {
        \ 'filename': l:filename,
        \ 'id': l:gist.id,
        \ 'description': l:gist.description,
        \ 'private': l:gist.public =~# 'true',
        \}
      catch
        let &undolevels = l:old_undolevels
        bw!
        redraw
        echohl ErrorMsg | echomsg 'Gist contains binary' | echohl None
        return
      endtry
      let &undolevels = l:old_undolevels
      setlocal buftype=acwrite bufhidden=hide noswapfile
      setlocal nomodified
      doau StdinReadPost,BufRead,BufReadPost
      let l:gist_detect_filetype = get(g:, 'gist_detect_filetype', 0)
      if (&ft ==# '' && l:gist_detect_filetype == 1) || l:gist_detect_filetype == 2
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
      augroup GistWrite
        au! BufWriteCmd <buffer> call s:GistWrite(expand("<amatch>"))
      augroup END
    endfor
  else
    bw!
    redraw
    echohl ErrorMsg | echomsg 'Gist not found' | echohl None
    return
  endif
endfunction

function! s:GistListAction(mode) abort
  let l:line = getline('.')
  let l:mx = '^gist:\s*\zs\(\w\+\)\ze.*'
  if l:line =~# l:mx
    let l:gistid = matchstr(l:line, l:mx)
    if a:mode == 1
      call s:open_browser('https://gist.github.com/' . l:gistid)
    elseif a:mode == 0
      call s:GistGet(l:gistid, 0)
      wincmd w
      bw
    elseif a:mode == 2
      call s:GistGet(l:gistid, 1)
      " TODO close with buffe rname
      bdelete
      bdelete
    elseif a:mode == 3
      call s:GistGet(l:gistid, 1)
      " TODO close with buffe rname
      bdelete
      bdelete
      normal! "+p
    endif
    return
  endif
  if l:line =~# '^more\.\.\.$'
    call s:GistList(b:gistls, b:page+1, g:gist_per_page_limit)
    return
  endif
endfunction

function! s:GistUpdate(content, gistid, gistnm, desc) abort
  let l:gist = { 'id': a:gistid, 'files' : {}, 'description': '','public': function('webapi#json#true') }
  if exists('b:gist')
    if has_key(b:gist, 'filename') && len(a:gistnm) > 0
      let l:gist.files[b:gist.filename] = { 'content': '', 'filename': b:gist.filename }
      let b:gist.filename = a:gistnm
    endif
    if has_key(b:gist, 'private') && b:gist.private | let l:gist['public'] = function('webapi#json#false') | endif
    if has_key(b:gist, 'description') | let l:gist['description'] = b:gist.description | endif
    if has_key(b:gist, 'filename') | let l:filename = b:gist.filename | endif
  else
    let l:filename = a:gistnm
    if len(l:filename) == 0 | let l:filename = s:GistGetFileName(a:gistid) | endif
    if len(l:filename) == 0 | let l:filename = s:get_current_filename(1) | endif
  endif

  let l:auth = s:GistGetAuthHeader()
  if len(l:auth) == 0
    redraw
    echohl ErrorMsg | echomsg v:errmsg | echohl None
    return
  endif

  " Update description
  " If no new description specified, keep the old description
  if a:desc !=# ' '
    let l:gist['description'] = a:desc
  else
    let l:res = webapi#http#get(g:gist_api_url.'gists/'.a:gistid, '', { 'Authorization': l:auth })
    if l:res.status =~# '^2'
      let l:old_gist = webapi#json#decode(l:res.content)
      let l:gist['description'] = l:old_gist.description
    endif
  endif

  let l:gist.files[l:filename] = { 'content': a:content, 'filename': l:filename }

  redraw | echon 'Updating gist... '
  let l:res = webapi#http#post(g:gist_api_url.'gists/' . a:gistid,
  \ webapi#json#encode(l:gist), {
  \   'Authorization': l:auth,
  \   'Content-Type': 'application/json',
  \})
  if l:res.status =~# '^2'
    let l:obj = webapi#json#decode(l:res.content)
    let l:loc = l:obj['html_url']
    let b:gist = {'id': a:gistid, 'filename': l:filename}
    setlocal nomodified
    redraw | echomsg 'Done: '.l:loc
  else
    let l:loc = ''
    echohl ErrorMsg | echomsg 'Post failed: ' . l:res.message | echohl None
  endif
  return l:loc
endfunction

function! s:GistDelete(gistid) abort
  let l:auth = s:GistGetAuthHeader()
  if len(l:auth) == 0
    redraw
    echohl ErrorMsg | echomsg v:errmsg | echohl None
    return
  endif

  redraw | echon 'Deleting gist... '
  let l:res = webapi#http#post(g:gist_api_url.'gists/'.a:gistid, '', {
  \   'Authorization': l:auth,
  \   'Content-Type': 'application/json',
  \}, 'DELETE')
  if l:res.status =~# '^2'
    if exists('b:gist')
      unlet b:gist
    endif
    redraw | echomsg 'Done: '
  else
    echohl ErrorMsg | echomsg 'Delete failed: ' . l:res.message | echohl None
  endif
endfunction

function! s:get_current_filename(no) abort
  let l:filename = expand('%:t')
  if len(l:filename) == 0 && &ft !=# ''
    let l:pair = filter(items(s:extmap), 'v:val[1] == &ft')
    if len(l:pair) > 0
      let l:filename = printf('gistfile%d%s', a:no, l:pair[0][0])
    endif
  endif
  if l:filename ==# ''
    let l:filename = printf('gistfile%d.txt', a:no)
  endif
  return l:filename
endfunction

function! s:update_GistID(id) abort
  let l:view = winsaveview()
  normal! gg
  let l:ret = 0
  if search('\<GistID\>:\s*$')
    let l:line = getline('.')
    let l:line = substitute(l:line, '\s\+$', '', 'g')
    call setline('.', l:line . ' ' . a:id)
    let l:ret = 1
  endif
  call winrestview(l:view)
  return l:ret
endfunction

" GistPost function:
"   Post new gist to github
"
"   if there is an embedded gist url or gist id in your file,
"   it will just update it.
"                                                   -- by c9s
"
"   embedded gist id format:
"
"       GistID: 123123
"
function! s:GistPost(content, private, desc, anonymous) abort
  let l:gist = { 'files' : {}, 'description': '','public': function('webapi#json#true') }
  if a:desc !=# ' ' | let l:gist['description'] = a:desc | endif
  if a:private | let l:gist['public'] = function('webapi#json#false') | endif
  let l:filename = s:get_current_filename(1)
  let l:gist.files[l:filename] = { 'content': a:content, 'filename': l:filename }

  let l:header = {'Content-Type': 'application/json'}
  if !a:anonymous
    let l:auth = s:GistGetAuthHeader()
    if len(l:auth) == 0
      redraw
      echohl ErrorMsg | echomsg v:errmsg | echohl None
      return
    endif
    let l:header['Authorization'] = l:auth
  endif

  redraw | echon 'Posting it to gist... '
  let l:res = webapi#http#post(g:gist_api_url.'gists', webapi#json#encode(l:gist), l:header)
  if l:res.status =~# '^2'
    let l:obj = webapi#json#decode(l:res.content)
    let l:loc = l:obj['html_url']
    let b:gist = {
    \ 'filename': l:filename,
    \ 'id': matchstr(l:loc, '[^/]\+$'),
    \ 'description': l:gist['description'],
    \ 'private': a:private,
    \}
    if s:update_GistID(b:gist['id'])
      Gist -e
    endif
    redraw | echomsg 'Done: '.l:loc
  else
    let l:loc = ''
    echohl ErrorMsg | echomsg 'Post failed: '. l:res.message | echohl None
  endif
  return l:loc
endfunction

function! s:GistPostBuffers(private, desc, anonymous) abort
  let l:bufnrs = range(1, bufnr('$'))
  let l:bn = bufnr('%')
  let l:query = []

  let l:gist = { 'files' : {}, 'description': '','public': function('webapi#json#true') }
  if a:desc !=# ' ' | let l:gist['description'] = a:desc | endif
  if a:private | let l:gist['public'] = function('webapi#json#false') | endif

  let l:index = 1
  for l:bufnr in l:bufnrs
    if !bufexists(l:bufnr) || buflisted(l:bufnr) == 0
      continue
    endif
    echo 'Creating gist content'.l:index.'... '
    silent! exec 'buffer!' l:bufnr
    let l:content = join(getline(1, line('$')), "\n")
    let l:filename = s:get_current_filename(l:index)
    let l:gist.files[l:filename] = { 'content': l:content, 'filename': l:filename }
    let l:index = l:index + 1
  endfor
  silent! exec 'buffer!' l:bn

  let l:header = {'Content-Type': 'application/json'}
  if !a:anonymous
    let l:auth = s:GistGetAuthHeader()
    if len(l:auth) == 0
      redraw
      echohl ErrorMsg | echomsg v:errmsg | echohl None
      return
    endif
    let l:header['Authorization'] = l:auth
  endif

  redraw | echon 'Posting it to gist... '
  let l:res = webapi#http#post(g:gist_api_url.'gists', webapi#json#encode(l:gist), l:header)
  if l:res.status =~# '^2'
    let l:obj = webapi#json#decode(l:res.content)
    let l:loc = l:obj['html_url']
    let b:gist = {
    \ 'filename': l:filename,
    \ 'id': matchstr(l:loc, '[^/]\+$'),
    \ 'description': l:gist['description'],
    \ 'private': a:private,
    \}
    if s:update_GistID(b:gist['id'])
      Gist -e
    endif
    redraw | echomsg 'Done: '.l:loc
  else
    let l:loc = ''
    echohl ErrorMsg | echomsg 'Post failed: ' . l:res.message | echohl None
  endif
  return l:loc
endfunction

function! gist#Gist(count, bang, line1, line2, ...) abort
  redraw
  let l:bufname = bufname('%')
  " find GistID: in content , then we should just update
  let l:gistid = ''
  let l:gistls = ''
  let l:gistnm = ''
  let l:gistdesc = ' '
  let l:private = get(g:, 'gist_post_private', 0)
  let l:multibuffer = 0
  let l:clipboard = 0
  let l:deletepost = 0
  let l:editpost = 0
  let l:anonymous = get(g:, 'gist_post_anonymous', 0)
  let l:openbrowser = 0
  let l:setpagelimit = 0
  let l:pagelimit = g:gist_per_page_limit
  let l:listmx = '^\%(-l\|--list\)\s*\([^\s]\+\)\?$'
  let l:bufnamemx = '^' . s:bufprefix .'\(\zs[0-9a-f]\+\ze\|\zs[0-9a-f]\+\ze[/\\].*\)$'
  if strlen(g:github_user) == 0 && l:anonymous == 0
    echohl ErrorMsg | echomsg 'You have not configured a Github account. Read '':help gist-setup''.' | echohl None
    return
  endif
  if a:bang == '!'
    let l:gistidbuf = ''
  elseif l:bufname =~# l:bufnamemx
    let l:gistidbuf = matchstr(l:bufname, l:bufnamemx)
  elseif exists('b:gist') && has_key(b:gist, 'id')
    let l:gistidbuf = b:gist['id']
  else
    let l:gistidbuf = matchstr(join(getline(a:line1, a:line2), "\n"), 'GistID:\s*\zs\w\+')
  endif

  let l:args = (a:0 > 0) ? s:shellwords(a:1) : []
  for l:arg in l:args
    if l:arg =~# '^\(-h\|--help\)$\C'
      help :Gist
      return
    elseif l:arg =~# '^\(-g\|--git\)$\C' && l:gistidbuf !=# '' && g:gist_api_url ==# 'https://api.github.com/' && has_key(b:, 'gist') && has_key(b:gist, 'id')
      echo printf('git clone git@github.com:%s', b:gist['id'])
      return
    elseif l:arg =~# '^\(-G\|--gitclone\)$\C' && l:gistidbuf !=# '' && g:gist_api_url ==# 'https://api.github.com/' && has_key(b:, 'gist') && has_key(b:gist, 'id')
      exe '!' printf('git clone git@github.com:%s', b:gist['id'])
      return
    elseif l:setpagelimit == 1
      let l:setpagelimit = 0
      let l:pagelimit = str2nr(l:arg)
      if l:pagelimit < 1 || l:pagelimit > 100
        echohl ErrorMsg | echomsg 'Page limit should be between 1 and 100: '.l:arg | echohl None
        unlet l:args
        return 0
      endif
    elseif l:arg =~# '^\(-la\|--listall\)$\C'
      let l:gistls = '-all'
    elseif l:arg =~# '^\(-ls\|--liststar\)$\C'
      let l:gistls = 'starred'
    elseif l:arg =~# '^\(-l\|--list\)$\C'
      if get(g:, 'gist_show_privates')
        let l:gistls = 'mine'
      else
        let l:gistls = g:github_user
      endif
    elseif l:arg =~# '^\(-m\|--multibuffer\)$\C'
      let l:multibuffer = 1
    elseif l:arg =~# '^\(-p\|--private\)$\C'
      let l:private = 1
    elseif l:arg =~# '^\(-P\|--public\)$\C'
      let l:private = 0
    elseif l:arg =~# '^\(-a\|--anonymous\)$\C'
      let l:anonymous = 1
    elseif l:arg =~# '^\(-s\|--description\)$\C'
      let l:gistdesc = ''
    elseif l:arg =~# '^\(-c\|--clipboard\)$\C'
      let l:clipboard = 1
    elseif l:arg =~# '^--rawurl$\C' && l:gistidbuf !=# '' && g:gist_api_url ==# 'https://api.github.com/'
      let l:gistid = l:gistidbuf
      echo 'https://gist.github.com/raw/'.l:gistid
      return
    elseif l:arg =~# '^\(-d\|--delete\)$\C' && l:gistidbuf !=# ''
      let l:gistid = l:gistidbuf
      let l:deletepost = 1
    elseif l:arg =~# '^\(-e\|--edit\)$\C'
      if l:gistidbuf !=# ''
        let l:gistid = l:gistidbuf
      endif
      let l:editpost = 1
    elseif l:arg =~# '^\(+1\|--star\)$\C' && l:gistidbuf !=# ''
      let l:auth = s:GistGetAuthHeader()
      if len(l:auth) == 0
        echohl ErrorMsg | echomsg v:errmsg | echohl None
      else
        let l:gistid = l:gistidbuf
        let l:res = webapi#http#post(g:gist_api_url.'gists/'.l:gistid.'/star', '', { 'Authorization': l:auth }, 'PUT')
        if l:res.status =~# '^2'
          echomsg 'Starred' l:gistid
        else
          echohl ErrorMsg | echomsg 'Star failed' | echohl None
        endif
      endif
      return
    elseif l:arg =~# '^\(-1\|--unstar\)$\C' && l:gistidbuf !=# ''
      let l:auth = s:GistGetAuthHeader()
      if len(l:auth) == 0
        echohl ErrorMsg | echomsg v:errmsg | echohl None
      else
        let l:gistid = l:gistidbuf
        let l:res = webapi#http#post(g:gist_api_url.'gists/'.l:gistid.'/star', '', { 'Authorization': l:auth }, 'DELETE')
        if l:res.status =~# '^2'
          echomsg 'Unstarred' l:gistid
        else
          echohl ErrorMsg | echomsg 'Unstar failed' | echohl None
        endif
      endif
      return
    elseif l:arg =~# '^\(-f\|--fork\)$\C' && l:gistidbuf !=# ''
      let l:auth = s:GistGetAuthHeader()
      if len(l:auth) == 0
        echohl ErrorMsg | echomsg v:errmsg | echohl None
        return
      else
        let l:gistid = l:gistidbuf
        let l:res = webapi#http#post(g:gist_api_url.'gists/'.l:gistid.'/fork', '', { 'Authorization': l:auth })
        if l:res.status =~# '^2'
          let l:obj = webapi#json#decode(l:res.content)
          let l:gistid = l:obj['id']
        else
          echohl ErrorMsg | echomsg 'Fork failed' | echohl None
          return
        endif
      endif
    elseif l:arg =~# '^\(-b\|--browser\)$\C'
      let l:openbrowser = 1
    elseif l:arg =~# '^\(-n\|--per-page\)$\C'
      if len(l:gistls) > 0
        let l:setpagelimit = 1
      else
        echohl ErrorMsg | echomsg 'Page limit can be set only for list commands'.l:arg | echohl None
        unlet l:args
        return 0
      endif
    elseif l:arg !~# '^-' && len(l:gistnm) == 0
      if l:gistdesc !=# ' '
        let l:gistdesc = matchstr(l:arg, '^\s*\zs.*\ze\s*$')
      elseif l:editpost == 1 || l:deletepost == 1
        let l:gistnm = l:arg
      elseif len(l:gistls) > 0 && l:arg !=# '^\w\+$\C'
        let l:gistls = l:arg
      elseif l:arg =~# '^[0-9a-z]\+$\C'
        let l:gistid = l:arg
      else
        echohl ErrorMsg | echomsg 'Invalid arguments: '.l:arg | echohl None
        unlet l:args
        return 0
      endif
    elseif len(l:arg) > 0
      echohl ErrorMsg | echomsg 'Invalid arguments: '.l:arg | echohl None
      unlet l:args
      return 0
    endif
  endfor
  unlet l:args
  "echom "gistid=".l:gistid
  "echom "gistls=".l:gistls
  "echom "gistnm=".l:gistnm
  "echom "gistdesc=".l:gistdesc
  "echom "private=".l:private
  "echom "clipboard=".l:clipboard
  "echom "editpost=".l:editpost
  "echom "deletepost=".l:deletepost

  if l:gistidbuf !=# '' && l:gistid ==# '' && l:editpost == 0 && l:deletepost == 0 && l:anonymous == 0
    let l:editpost = 1
    let l:gistid = l:gistidbuf
  endif

  if len(l:gistls) > 0
    call s:GistList(l:gistls, 1, l:pagelimit)
  elseif len(l:gistid) > 0 && l:editpost == 0 && l:deletepost == 0
    call s:GistGet(l:gistid, l:clipboard)
  else
    let l:url = ''
    if l:multibuffer == 1
      let l:url = s:GistPostBuffers(l:private, l:gistdesc, l:anonymous)
    else
      if a:count < 1
        let l:content = join(getline(a:line1, a:line2), "\n")
      else
        let l:save_regcont = @"
        let l:save_regtype = getregtype('"')
        silent! normal! gvy
        let l:content = @"
        call setreg('"', l:save_regcont, l:save_regtype)
      endif
      if l:editpost == 1
        let l:url = s:GistUpdate(l:content, l:gistid, l:gistnm, l:gistdesc)
      elseif l:deletepost == 1
        call s:GistDelete(l:gistid)
      else
        let l:url = s:GistPost(l:content, l:private, l:gistdesc, l:anonymous)
      endif
      if a:count >= 1 && get(g:, 'gist_keep_selection', 0) == 1
        silent! normal! gv
      endif
    endif
    if type(l:url) == 1 && len(l:url) > 0
      if get(g:, 'gist_open_browser_after_post', 0) == 1 || l:openbrowser
        call s:open_browser(l:url)
      endif
      let l:gist_put_url_to_clipboard_after_post = get(g:, 'gist_put_url_to_clipboard_after_post', 1)
      if l:gist_put_url_to_clipboard_after_post > 0 || l:clipboard
        if l:gist_put_url_to_clipboard_after_post == 2
          let l:url = l:url . "\n"
        endif
        if exists('g:gist_clip_command')
          call system(g:gist_clip_command, l:url)
        elseif has('clipboard')
          let @+ = l:url
        else
          let @" = l:url
        endif
      endif
    endif
  endif
  return 1
endfunction

function! s:GistGetAuthHeader() abort
  if get(g:, 'gist_use_password_in_gitconfig', 0) != 0
    let l:password = substitute(system('git config --get github.password'), "\n", '', '')
    if l:password =~# '^!' | let l:password = system(l:password[1:]) | endif
    return printf('basic %s', webapi#base64#b64encode(g:github_user.':'.l:password))
  endif
  let l:auth = ''
  if !empty(get(g:, 'gist_token', $GITHUB_TOKEN))
    let l:auth = 'token ' . get(g:, 'gist_token', $GITHUB_TOKEN)
  elseif filereadable(s:gist_token_file)
    let l:str = join(readfile(s:gist_token_file), '')
    if type(l:str) == 1
      let l:auth = l:str
    endif
  endif
  if len(l:auth) > 0
    return l:auth
  endif

  let l:client_id = get(g:, 'gist_oauth_client_id', '9d56c2177b50717a4727')

  let l:github_host = matchstr(g:gist_api_url, 'https\?://\zs[^/]\+\ze')
  if l:github_host ==# 'api.github.com'
    let l:device_code_url = 'https://github.com/login/device/code'
    let l:access_token_url = 'https://github.com/login/oauth/access_token'
  else
    let l:device_code_url = 'https://' . l:github_host . '/login/device/code'
    let l:access_token_url = 'https://' . l:github_host . '/login/oauth/access_token'
  endif

  redraw
  echohl WarningMsg
  echo 'Gist.vim requires authorization to use the GitHub API. These settings are stored in "~/.gist-vim". If you want to revoke, do "rm ~/.gist-vim".'
  echohl None

  let l:res = webapi#http#post(l:device_code_url,
              \ 'client_id=' . l:client_id . '&scope=gist', {
              \  'Accept': 'application/json',
              \})
  let l:device = webapi#json#decode(l:res.content)
  if !has_key(l:device, 'device_code') || !has_key(l:device, 'user_code')
    let v:errmsg = get(l:device, 'error_description', 'Failed to request device code')
    redraw
    echohl ErrorMsg | echomsg v:errmsg | echohl None
    return ''
  endif

  let l:device_code = l:device.device_code
  let l:user_code = l:device.user_code
  let l:verification_uri = get(l:device, 'verification_uri', 'https://github.com/login/device')
  let l:interval = get(l:device, 'interval', 5)
  let l:expires_in = get(l:device, 'expires_in', 900)

  call s:open_browser(l:verification_uri)
  redraw
  echohl Title
  echo 'Open ' . l:verification_uri . ' and enter code: ' . l:user_code
  echohl None

  let l:elapsed = 0
  while l:elapsed < l:expires_in
    let l:sleep_cmd = 'sleep ' . l:interval
    if has('win32') || has('win64')
      let l:sleep_cmd = 'ping -n ' . (l:interval + 1) . ' 127.0.0.1 >nul'
    endif
    call system(l:sleep_cmd)
    let l:elapsed += l:interval

    let l:res = webapi#http#post(l:access_token_url,
                \ 'client_id=' . l:client_id
                \ . '&device_code=' . l:device_code
                \ . '&grant_type=urn:ietf:params:oauth:grant-type:device_code', {
                \  'Accept': 'application/json',
                \})
    let l:token_response = webapi#json#decode(l:res.content)

    if has_key(l:token_response, 'access_token')
      let l:secret = printf('token %s', l:token_response.access_token)
      call writefile([l:secret], s:gist_token_file)
      if !(has('win32') || has('win64'))
        call system('chmod go= '.s:gist_token_file)
      endif
      redraw | echo 'Authorization successful!'
      return l:secret
    endif

    let l:error = get(l:token_response, 'error', '')
    if l:error ==# 'authorization_pending'
      continue
    elseif l:error ==# 'slow_down'
      let l:interval = get(l:token_response, 'interval', l:interval + 5)
      continue
    elseif l:error ==# 'expired_token'
      redraw
      echohl ErrorMsg | echomsg 'Device code expired. Please try again.' | echohl None
      let v:errmsg = 'Device code expired'
      return ''
    elseif l:error ==# 'access_denied'
      redraw
      echohl ErrorMsg | echomsg 'Authorization was denied by the user.' | echohl None
      let v:errmsg = 'Authorization denied'
      return ''
    else
      redraw
      let v:errmsg = get(l:token_response, 'error_description', 'Authorization failed: ' . l:error)
      echohl ErrorMsg | echomsg v:errmsg | echohl None
      return ''
    endif
  endwhile

  redraw
  echohl ErrorMsg | echomsg 'Authorization timed out. Please try again.' | echohl None
  let v:errmsg = 'Authorization timed out'
  return ''
endfunction

let s:extmap = extend({
\'.adb': 'ada',
\'.ahk': 'ahk',
\'.arc': 'arc',
\'.as': 'actionscript',
\'.asm': 'asm',
\'.asp': 'asp',
\'.aw': 'php',
\'.b': 'b',
\'.bat': 'bat',
\'.befunge': 'befunge',
\'.bmx': 'bmx',
\'.boo': 'boo',
\'.c-objdump': 'c-objdump',
\'.c': 'c',
\'.cfg': 'cfg',
\'.cfm': 'cfm',
\'.ck': 'ck',
\'.cl': 'cl',
\'.clj': 'clj',
\'.cmake': 'cmake',
\'.coffee': 'coffee',
\'.cpp': 'cpp',
\'.cppobjdump': 'cppobjdump',
\'.cs': 'csharp',
\'.css': 'css',
\'.cw': 'cw',
\'.d-objdump': 'd-objdump',
\'.d': 'd',
\'.darcspatch': 'darcspatch',
\'.diff': 'diff',
\'.duby': 'duby',
\'.dylan': 'dylan',
\'.e': 'e',
\'.ebuild': 'ebuild',
\'.eclass': 'eclass',
\'.el': 'lisp',
\'.erb': 'erb',
\'.erl': 'erlang',
\'.f90': 'f90',
\'.factor': 'factor',
\'.feature': 'feature',
\'.fs': 'fs',
\'.fy': 'fy',
\'.go': 'go',
\'.groovy': 'groovy',
\'.gs': 'gs',
\'.gsp': 'gsp',
\'.haml': 'haml',
\'.hs': 'haskell',
\'.html': 'html',
\'.hx': 'hx',
\'.ik': 'ik',
\'.ino': 'ino',
\'.io': 'io',
\'.j': 'j',
\'.java': 'java',
\'.js': 'javascript',
\'.json': 'json',
\'.jsp': 'jsp',
\'.kid': 'kid',
\'.lhs': 'lhs',
\'.lisp': 'lisp',
\'.ll': 'll',
\'.lua': 'lua',
\'.ly': 'ly',
\'.m': 'objc',
\'.mak': 'mak',
\'.man': 'man',
\'.mao': 'mao',
\'.matlab': 'matlab',
\'.md': 'markdown',
\'.minid': 'minid',
\'.ml': 'ml',
\'.moo': 'moo',
\'.mu': 'mu',
\'.mustache': 'mustache',
\'.mxt': 'mxt',
\'.myt': 'myt',
\'.n': 'n',
\'.nim': 'nim',
\'.nu': 'nu',
\'.numpy': 'numpy',
\'.objdump': 'objdump',
\'.ooc': 'ooc',
\'.parrot': 'parrot',
\'.pas': 'pas',
\'.pasm': 'pasm',
\'.pd': 'pd',
\'.phtml': 'phtml',
\'.pir': 'pir',
\'.pl': 'perl',
\'.po': 'po',
\'.py': 'python',
\'.pytb': 'pytb',
\'.pyx': 'pyx',
\'.r': 'r',
\'.raw': 'raw',
\'.rb': 'ruby',
\'.rhtml': 'rhtml',
\'.rkt': 'rkt',
\'.rs': 'rs',
\'.rst': 'rst',
\'.s': 's',
\'.sass': 'sass',
\'.sc': 'sc',
\'.scala': 'scala',
\'.scm': 'scheme',
\'.scpt': 'scpt',
\'.scss': 'scss',
\'.self': 'self',
\'.sh': 'sh',
\'.sml': 'sml',
\'.sql': 'sql',
\'.st': 'smalltalk',
\'.swift': 'swift',
\'.tcl': 'tcl',
\'.tcsh': 'tcsh',
\'.tex': 'tex',
\'.textile': 'textile',
\'.tpl': 'smarty',
\'.twig': 'twig',
\'.txt' : 'text',
\'.v': 'verilog',
\'.vala': 'vala',
\'.vb': 'vbnet',
\'.vhd': 'vhdl',
\'.vim': 'vim',
\'.weechatlog': 'weechatlog',
\'.xml': 'xml',
\'.xq': 'xquery',
\'.xs': 'xs',
\'.yml': 'yaml',
\}, get(g:, 'gist_extmap', {}))

let &cpo = s:save_cpo
unlet s:save_cpo

" vim:set et:
