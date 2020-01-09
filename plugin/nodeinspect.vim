" ============================================================================
" nodeinspect.vim,  a wrapper over node-inspect
" Eli Babila (elibabila@gmail.com)
" ============================================================================


if exists('nodeinspect_loaded')
    finish
endif
let nodeinspect_loaded = 1

command! -nargs=0 NodeInspectStart call nodeinspect#NodeInspectStart()
command! -nargs=0 NodeInspectStartRun call nodeinspect#NodeInspectStartRun()
command! -nargs=0 NodeInspectStepOver call nodeinspect#NodeInspectStepOver()
command! -nargs=0 NodeInspectStepInto call nodeinspect#NodeInspectStepInto()
command! -nargs=0 NodeInspectStepOut call nodeinspect#NodeInspectStepOut()
command! -nargs=0 NodeInspectContinue call nodeinspect#NodeInspectContinue()
command! -nargs=0 NodeInspectStop call nodeinspect#NodeInspectStop()
command! -nargs=0 NodeInspectToggleBreakpoint call nodeinspect#NodeInspectToggleBreakpoint()

"autocmd VimLeavePre * call OnNodeInspectExit()
autocmd VimEnter * call nodeinspect#OnNodeInspectEnter()
