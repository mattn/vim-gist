"=============================================================================
" File: gist.vim
" Author: Yasuhiro Matsumoto <mattn.jp@gmail.com>
" WebPage: http://github.com/mattn/gist-vim
" License: BSD
" GetLatestVimScripts: 2423 1 :AutoInstall: gist.vim
" script type: plugin

if &cp || (exists('g:loaded_gist_vim') && g:loaded_gist_vim)
  finish
endif
let g:loaded_gist_vim = 1

function! s:CompleteArgs(arg_lead,cmdline,cursor_pos)
    return ["-p", "-P", "-a", "-m", "-e", "-s", "-d", "-f", "-c", "-l", "-la", "-ls"]
endfunction

command! -nargs=? -range=% -complete=customlist,s:CompleteArgs Gist :call gist#Gist(<count>, <line1>, <line2>, <f-args>)

" vim:set et:
