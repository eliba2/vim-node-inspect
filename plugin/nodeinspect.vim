" ============================================================================
" nodeinspect.vim,  a wrapper over node-inspect
" Eli Babila (elibabila@gmail.com)
" ============================================================================


if exists('nodeinspect_loaded')
    finish
endif
let nodeinspect_loaded = 1

command! -nargs=0 StartNodeInspect call nodeinspect#StartNodeInspect()
command! -nargs=0 NodeInspectToggleBreakpoint call nodeinspect#NodeInspectToggleBreakpoint()
command! -nargs=0 NodeInspectStepOver call nodeinspect#NodeInspectStepOver()
command! -nargs=0 NodeInspectStepInto call nodeinspect#NodeInspectStepInto()

