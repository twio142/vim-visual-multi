" vim-visual-multi bootstrap shim
" Requires Neovim 0.10+. No VimScript logic — delegates entirely to Lua.

if !has('nvim-0.10')
  echohl WarningMsg
  echom 'vim-visual-multi: Neovim 0.10+ required'
  echohl None
  finish
endif

if exists('g:loaded_visual_multi')
  finish
endif
let g:loaded_visual_multi = 1

lua require('visual-multi')
