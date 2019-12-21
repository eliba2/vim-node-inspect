

let s:has_supported_python = 0
let s:initiated = 0
let s:channel = 0
let s:sign_id = 2
let s:brkpt_sign_id = 3
let s:sign_group = 'visgroup'
let s:sign_cur_exec = 'vis'
let s:sign_brkpt = 'visbkpt'



if has('python3')
    let s:has_supported_python = 2
elseif has('python')"
    let s:has_supported_python = 1
endif

if !s:has_supported_python
    function! s:NodeInspectDidNotLoad()
        echohl WarningMsg|echomsg "Node Inspect requires Vim to be compiled with Python 2.4+"|echohl None
    endfunction
    call s:NodeInspectDidNotLoad()
    finish
endif

let s:plugin_path = escape(expand('<sfile>:p:h'), '\')


function! s:NodeInspectToggleBreakpoint()
	if s:has_supported_python == 2
		python3 NodeInspectToggleBreakpoint()
	else
		python NodeInspectToggleBreakpoint()
	endif
endfunction

function! s:NodeInspectStepOver()
	if s:has_supported_python == 2
		python3 NodeInspectStepOver()
	else
		python NodeInspectStepOver()
	endif
endfunction

function! s:NodeInspectStepInto()
	if s:has_supported_python == 2
		python3 NodeInspectStepInto()
	else
		python NodeInspectStepInto()
	endif
endfunction


function! s:NodeInspectStop()
	if s:has_supported_python == 2
		python3 NodeInspectStop()
	else
		python NodeInspectStop()
	endif
endfunction

function! s:NodeInspectContinue()
	if s:has_supported_python == 2
		python3 NodeInspectContinue()
	else
		python NodeInspectContinue()
	endif
endfunction

function! s:NodeInspectStepOut()
	if s:has_supported_python == 2
		python3 NodeInspectStepOut()
	else
		python NodeInspectStepOut()
	endif
endfunction



func s:addBrkptSign(file, line)
    id = brkpt_sign_id + 1
    vim.command('sign place %d line=%s name=%s group=%s file=%s' % (id, line, sign_brkpt, sign_group, file))
    return id
endfunc

func s:removeBrkptSign(id, file)
    vim.command('sign unplace %d group=%s file=%s' % (id, sign_group, file))
endfunc

func s:addSign(file, line)
    execute("sign place " . s:sign_id . " line=" . a:line . " name=" . s:sign_cur_exec . " group=" . s:sign_group .  " file=" . a:file)
endfunc

func s:removeSign()
    " print 'sign unplace %i group=%s' % (sign_id, sign_group)
    " vim.command('sign unplace %i group=%s' % (sign_id, sign_group))
    " vim doesn't have the group... should check w nvim.
    execute('sign unplace %d group=%s' % (sign_id, sign_group))
endfunc







func s:onDebuggerStopped(mes)
	execute "edit " . a:mes["file"]
	execute ":" . a:mes["line"]
	call s:addSign(a:mes["file"], a:mes["line"])
endfunc


func OnNodeMessage(channel, msg)
	let mes = json_decode(a:msg)
	if mes["m"] == "nd_stopped"
		call s:onDebuggerStopped(mes)
	else
		echo "vim-node-inspect: unknown message"
	endif
endfunc


function! s:NodeInspectStart(start)
	" register global on exit, add signs 
	if s:initiated == 0
		let s:initiated = 1
		autocmd VimLeavePre * call OnNodeInspectExit(0,0,0)
		" debug sign 
    execute "sign define " . s:sign_cur_exec . " text=>> texthl=Select"
		" breakpoint sign
    execute "sign define " . s:sign_brkpt . " text=() texthl=SyntasticErrorSign"
	endif

	" start
	let g:started = 1
	let s:start_win = winnr()
	let file = expand('%:p')
	execute "bo 10new"
	let s:repl_win = winnr()
	let s:repl_buf = bufnr('%')
	set nonu
	if has("nvim")
		termcmd = '''call term_start ("node node-inspect/cli.js %s", {'curwin': 1, 'term_kill': 'kill',  'exit_cb': 'OnNodeInspectExit'})'''%f
	else
		execute "let s:term_id = term_start ('node node-inspect/cli.js " . file . "', {'curwin': 1, 'term_kill': 'kill',  'exit_cb': 'OnNodeInspectExit'})"
	endif

	" switch back to start buf
	execute s:start_win . "wincmd w"
	" try and connect from vim; can I remove python ?
	sleep 150m
	let s:channel = ch_open("localhost:9514", {"mode":"raw", "callback": "OnNodeMessage"})
endfunction




function! OnNodeInspectExit(a,b,c)
	if s:has_supported_python == 2
		python3 NodeInspectCleanup()
	else
		python NodeInspectCleanup()
	endif
endfunction

function! NodeInspectTimerCallback(timer)
	if s:has_supported_python == 2
		python3 NodeInspectExecLoop()
	else
		python NodeInspectExecLoop()
	endif
endfunction


" Callable functions


function! nodeinspect#NodeInspectToggleBreakpoint()
	if !exists('g:nodeinspect_py_loaded')
		echo "node-inspect not started"
		return
	endif
	call s:NodeInspectToggleBreakpoint()
endfunction

function! nodeinspect#NodeInspectStepOver()
	if !exists('g:nodeinspect_py_loaded')
		echo "node-inspect not started"
		return
	endif
	call s:NodeInspectStepOver()
endfunction

function! nodeinspect#NodeInspectStepInto()
	if !exists('g:nodeinspect_py_loaded')
		echo "node-inspect not started"
		return
	endif
	call s:NodeInspectStepInto()
endfunction

function! nodeinspect#NodeInspectStepOut()
	if !exists('g:nodeinspect_py_loaded')
		echo "node-inspect not started"
		return
	endif
	call s:NodeInspectStepOut()
endfunction

function! nodeinspect#NodeInspectContinue()
	if !exists('g:nodeinspect_py_loaded')
		echo "node-inspect not started"
		return
	endif
	call s:NodeInspectContinue()
endfunction

function! nodeinspect#NodeInspectStop()
	if !exists('g:nodeinspect_py_loaded')
		echo "node-inspect not started"
		return
	endif
	call s:NodeInspectStop()
endfunction

function! nodeinspect#NodeInspectStart()
    call s:NodeInspectStart(0)
endfunction

function! nodeinspect#NodeInspectStartRun()
    call s:NodeInspectStart(1)
endfunction

