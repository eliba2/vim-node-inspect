let s:has_supported_python = 0
let s:initiated = 0
let s:plugin_path = expand('<sfile>:h:h')
let s:channel = 0
let s:sign_id = 2
let s:brkpt_sign_id = 3
let s:sign_group = 'visgroup'
let s:sign_cur_exec = 'vis'
let s:sign_brkpt = 'visbkpt'
let s:breakpoints = {}
let s:signInitiated = 0

autocmd VimLeavePre * call OnNodeInspectExit()

func s:addBrkptSign(file, line)
		let s:brkpt_sign_id = s:brkpt_sign_id + 1
		execute("sign place " . s:brkpt_sign_id . " line=" . a:line . " name=" . s:sign_brkpt . " group=" . s:sign_group . " file=" . a:file)
    return s:brkpt_sign_id
endfunc

func s:removeBrkptSign(id, file)
    execute("sign unplace " . a:id . " group=" . s:sign_group . " file=" . a:file)
endfunc

func s:addSign(file, line)
    execute("sign place " . s:sign_id . " line=" . a:line . " name=" . s:sign_cur_exec . " group=" . s:sign_group .  " file=" . a:file)
endfunc

func s:removeSign()
    execute "sign unplace " . s:sign_id . " group=" . s:sign_group
endfunc


func s:sendEvent(e)
	if has("nvim")
		call chansend(s:channel, a:e)
	else
		call ch_sendraw(s:channel, a:e)
	endif
endfunc

func s:NodeInspectCleanup()
	call s:removeSign()
	let s:initiated = 0
endfunc

function! s:NodeInspectToggleBreakpoint()
	let file = expand('%:.')
	let line = line('.')
	" might need to initialize the sings if called before the inspector is running
	if s:signInitiated == 0
		call s:SignInit()
	endif
	" check if the file is in the directory and check for relevant line
	if has_key(s:breakpoints, file) == 1 && has_key(s:breakpoints[file], line) == 1
		let bid = s:breakpoints[file][line]
		" its in, remove it
		call remove(s:breakpoints[file], line)
		" if the dictionary is empty, remove the file entirely
		if len(s:breakpoints[file]) == 0
			call remove(s:breakpoints, file)
		endif
		" remove sign
		call s:removeBrkptSign(bid, file)
		" send event only if node-inspect was started
		if s:initiated == 1
			call s:sendEvent('{"m": "nd_removebrkpt", "file":' . file . ', "line":' . line . '}')
		endif
	else
		" add sign, store id
		let bid =	s:addBrkptSign(file, line)
		if has_key(s:breakpoints, file) == 0
			" does not exist, add it, file and line
			let s:breakpoints[file] = {}
		endif
		let s:breakpoints[file][line] = bid
		" send event only if node-inspect was started
		if s:initiated == 1
			call s:sendEvent('{"m": "nd_addbrkpt", "file":' . file . ', "line":' . line . '}')
		endif
	endif
endfunction

function! s:NodeInspectStepOver()
	call s:removeSign()
	call s:sendEvent('{"m": "nd_next"}')
endfunction

function! s:NodeInspectStepInto()
	call s:removeSign()
	call s:sendEvent('{"m": "nd_into"}')
endfunction


function! s:NodeInspectStop()
	call s:sendEvent('{"m": "nd_kill"}')
	call s:removeSign()
  call s:NodeInspectCleanup()
	execute s:repl_buf . "bd!"
endfunction


function! s:NodeInspectContinue()
	call s:removeSign()
	call s:sendEvent('{"m": "nd_continue"}')
endfunction


function! s:NodeInspectStepOut()
	call s:removeSign()
	call s:sendEvent('{"m": "nd_out"}')
endfunction



func s:onDebuggerStopped(mes)
	call win_gotoid(s:start_win)
	execute "edit " . a:mes["file"]
	execute ":" . a:mes["line"]
	call s:addSign(a:mes["file"], a:mes["line"])
endfunc


func OnNodeMessage(channel, msg)
	if len(a:msg) == 0 || len(a:msg) == 1 &&  len(a:msg[0]) == 0
		let mes = ''
	else
		let mes = json_decode(a:msg)
	endif
	if mes["m"] == "nd_stopped"
		call s:onDebuggerStopped(mes)
	else
		echo "vim-node-inspect: unknown message"
	endif
endfunc


func OnNodeNvimMessage(channel, msg, name)
	call OnNodeMessage(a:channel, a:msg)
endfunc

function! s:SignInit()
	if s:signInitiated == 0
		" debug sign 
    execute "sign define " . s:sign_cur_exec . " text=>> texthl=Select"
		" breakpoint sign
    execute "sign define " . s:sign_brkpt . " text=() texthl=SyntasticErrorSign"
	endif
endfunction


function! s:NodeInspectStart(start)
	" register global on exit, add signs 
	if s:initiated == 0
		let s:initiated = 1
		if s:signInitiated == 0
			call s:SignInit()
		endif
		" start
		let s:start_win = win_getid()
		let file = expand('%:p')
		execute "bo 10new"
		let s:repl_win = win_getid()
		let s:repl_buf = bufnr('%')
		set nonu
		if has("nvim")
			execute "let s:term_id = termopen ('node " . s:plugin_path . "/node-inspect/cli.js " . file . "', {'on_exit': 'OnNodeInspectNvimExit'})"
		else
			execute "let s:term_id = term_start ('node " . s:plugin_path . "/node-inspect/cli.js " . file . "', {'curwin': 1, 'term_kill': 'kill',  'exit_cb': 'OnNodeInspectExit', 'term_finish': 'close'})"
		endif
		" switch back to start buf
		call win_gotoid(s:start_win)
		sleep 150m
		if has("nvim")
			let s:channel = sockconnect("tcp", "localhost:9514", {"on_data": "OnNodeNvimMessage"})
		else
			let s:channel = ch_open("localhost:9514", {"mode":"raw", "callback": "OnNodeMessage"})
		endif
		" to_do check return value from socket for failure
	else
		call s:sendEvent('{"m": "nd_restart"}')
	endif
	" send breakpoints, if any
	call s:sendEvent('{"m": "nd_setbreakpoints", "breakpoints":' . json_encode(s:breakpoints) . '}')
endfunction




function! OnNodeInspectExit(...)
	if s:initiated == 1
		call s:NodeInspectCleanup()
	endif
endfunction


function! OnNodeInspectNvimExit(...)
	" close the window as there's no such option in termopen
	call win_gotoid(s:repl_win)
	execute "bd!"
	if s:initiated == 1
		call s:NodeInspectCleanup()
	endif
endfunction


" Callable functions


function! nodeinspect#NodeInspectToggleBreakpoint()
	call s:NodeInspectToggleBreakpoint()
endfunction

function! nodeinspect#NodeInspectStepOver()
	if s:initiated == 0
		echo "node-inspect not started"
		return
	endif
	call s:NodeInspectStepOver()
endfunction

function! nodeinspect#NodeInspectStepInto()
	if s:initiated == 0
		echo "node-inspect not started"
		return
	endif
	call s:NodeInspectStepInto()
endfunction

function! nodeinspect#NodeInspectStepOut()
	if s:initiated == 0
		echo "node-inspect not started"
		return
	endif
	call s:NodeInspectStepOut()
endfunction

function! nodeinspect#NodeInspectContinue()
	if s:initiated == 0
		echo "node-inspect not started"
		return
	endif
	call s:NodeInspectContinue()
endfunction

function! nodeinspect#NodeInspectStop()
	if s:initiated == 0
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

