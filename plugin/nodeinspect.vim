" ============================================================================
" nodeinspect.vim, interactive debugger for (n)vim
" Eli Babila (elibabila@gmail.com)
" ============================================================================


if exists('nodeinspect_loaded')
    finish
endif
if has("nvim") == 0 && v:version < 801
   echohl WarningMsg
   echom  "vim-node-inspect requires vim 8.1"
   echohl None
   finish
endif
let nodeinspect_loaded = 1

command! -nargs=0 NodeInspectStart call nodeinspect#NodeInspectStart()
command! -nargs=0 NodeInspectRun call nodeinspect#NodeInspectRun()
command! -nargs=1 NodeInspectConnect call nodeinspect#NodeInspectConnect(<args>)
"command! -nargs=0 NodeInspectPause call nodeinspect#NodeInspectPause()
command! -nargs=0 NodeInspectStepOver call nodeinspect#NodeInspectStepOver()
command! -nargs=0 NodeInspectStepInto call nodeinspect#NodeInspectStepInto()
command! -nargs=0 NodeInspectStepOut call nodeinspect#NodeInspectStepOut()
command! -nargs=0 NodeInspectStop call nodeinspect#NodeInspectStop()
command! -nargs=0 NodeInspectToggleBreakpoint call nodeinspect#NodeInspectToggleBreakpoint()
command! -nargs=0 NodeInspectRemoveAllBreakpoints call nodeinspect#NodeInspectRemoveAllBreakpoints()
command! -nargs=0 NodeInspectAddWatch call nodeinspect#NodeInspectAddWatch()

autocmd VimEnter * call nodeinspect#OnNodeInspectEnter()

