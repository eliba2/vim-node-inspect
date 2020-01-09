let s:initiated = 0
let s:plugin_path = expand('<sfile>:h:h')
let s:channel = 0
let s:sign_id = 2
let s:brkpt_sign_id = 3
let s:sign_group = 'visgroup'
let s:sign_cur_exec = 'vis'
let s:sign_brkpt = 'visbkpt'
let s:breakpoints = {}
let s:breakpointsUnhandledBuffers = {}
let s:configFile = s:plugin_path . '/breakpoints'

autocmd VimLeavePre * call OnNodeInspectExit()
autocmd BufEnter * call OnBufEnter()

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


" write breakpoints file
" it is serialized as a list of lines, each consist of
" <file>#<line>,<line>...
func s:saveConfigFile()
	let breakpointList = []
	for filename in keys(s:breakpoints)
		let allLines = ''
		for lineKey in keys(s:breakpoints[filename])
			if allLines != ''
				let allLines = allLines . ','
			endif
			let allLines = allLines . lineKey
		endfor
		let line = filename . '#' . allLines
		call add(breakpointList, line)
	endfor
	call writefile(breakpointList, s:configFile)
endfunc

" load breakpoints file. see above for description.
func s:loadConfigFile()
	if filereadable(s:configFile)
		for fileLine in readfile(s:configFile, '')
			let brkList = split(fileLine,"#")
			let filename = brkList[0]
			let allLines = split(brkList[1],',') 
			" adding to breakpoint list but not yet setting the breakpoints signs.
			" this will be done in the bufenter autocmd
			for line in allLines
				call s:addBreakpoint(filename, str2nr(line), 0)
			endfor
			let s:breakpointsUnhandledBuffers[filename] = 1
		endfor
		" call for initial buf to setup the breakpoints signs as its not auto called
		call OnBufEnter()
	endif
endfunc


func s:NodeInspectCleanup()
	let s:initiated = 0
	call s:removeSign()
	call s:saveConfigFile()
endfunc



" add brekpoint to list, adds the sign as well
function s:addBreakpoint(file, line, signId)
	if has_key(s:breakpoints, a:file) == 0
		" does not exist, add it, file and line
		let s:breakpoints[a:file] = {}
	endif
	let s:breakpoints[a:file][a:line] = a:signId
endfunction


function s:removeBreakpoint(file, line)
	" its in, remove it
	call remove(s:breakpoints[a:file], a:line)
	" if the dictionary is empty, remove the file entirely
	if len(s:breakpoints[a:file]) == 0
		call remove(s:breakpoints, a:file)
	endif
endfunction


function! s:NodeInspectToggleBreakpoint()
	let file = expand('%:p')
	let line = line('.')
	" check if the file is in the directory and check for relevant line
	if has_key(s:breakpoints, file) == 1 && has_key(s:breakpoints[file], line) == 1
		let signId = s:breakpoints[file][line]
		call s:removeBreakpoint(file, line, signId)
		" remove sign
		call s:removeBrkptSign(signId, file)
		" send event only if node-inspect was started
		if s:initiated == 1
			call s:sendEvent('{"m": "nd_removebrkpt", "file":"' . file . '", "line":' . line . '}')
		endif
	else
		" add sign, store id
		let signId =	s:addBrkptSign(file, line)
		call s:addBreakpoint(file, line, signId)
		" send event only if node-inspect was started
		if s:initiated == 1
			call s:sendEvent('{"m": "nd_addbrkpt", "file":"' . file . '", "line":' . line . '}')
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
	call s:removeSign()
	call s:sendEvent('{"m": "nd_kill"}')
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
	" open the relevant file only if it can be found locally
	if filereadable(a:mes["file"])
		call win_gotoid(s:start_win)
		execute "edit " . a:mes["file"]
		execute ":" . a:mes["line"]
		call s:addSign(a:mes["file"], a:mes["line"])
	endif
endfunc


func OnNodeMessage(channel, msg)
	if len(a:msg) == 0 || len(a:msg) == 1 &&  len(a:msg[0]) == 0
		" currently ignoring; called at the end (nvim)
		let mes = ''
	else
		let mes = json_decode(a:msg)
		if mes["m"] == "nd_stopped"
			call s:onDebuggerStopped(mes)
		else
			echo "vim-node-inspect: unknown message "
		endif
	endif
endfunc


func OnNodeNvimMessage(channel, msg, name)
	call OnNodeMessage(a:channel, a:msg)
endfunc

function! s:SignInit()
	" debug sign 
	execute "sign define " . s:sign_cur_exec . " text=>> texthl=Select"
	" breakpoint sign
	execute "sign define " . s:sign_brkpt . " text=() texthl=SyntasticErrorSign"
endfunction


function! s:NodeInspectStart(start, tsap)

	" must start with a file. at least for now.
	if bufname() == '' && a:tsap == ''
		echom "node-inspect must start with a file. Save the buffer first"
		return
	endif
	" register global on exit, add signs 
	if s:initiated == 0
		let s:initiated = 1
		" start
		let s:start_win = win_getid()
		if a:tsap == ''
			let file = expand('%:p')
		endif
		" create bottom buffer, switch to it
		execute "bo 10new"
		let s:repl_win = win_getid()
		let s:repl_buf = bufnr('%')
		set nonu
		" is it with a filename or connection to host:port?
		if a:tsap == ''
			if has("nvim")
				execute "let s:term_id = termopen ('node " . s:plugin_path . "/node-inspect/cli.js " . file . "', {'on_exit': 'OnNodeInspectNvimExit'})"
			else
				execute "let s:term_id = term_start ('node " . s:plugin_path . "/node-inspect/cli.js " . file . "', {'curwin': 1, 'term_kill': 'kill',  'exit_cb': 'OnNodeInspectExit', 'term_finish': 'close'})"
			endif
		else
			if has("nvim")
				execute "let s:term_id = termopen ('node " . s:plugin_path . "/node-inspect/cli.js " . a:tsap . "', {'on_exit': 'OnNodeInspectNvimExit'})"
			else
				execute "let s:term_id = term_start ('node " . s:plugin_path . "/node-inspect/cli.js " . a:tsap . "', {'curwin': 1, 'term_kill': 'kill',  'exit_cb': 'OnNodeInspectExit', 'term_finish': 'close'})"
			endif
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

		" send breakpoints, if any
		sleep 150m
		call s:sendEvent('{"m": "nd_setbreakpoints", "breakpoints":' . json_encode(s:breakpoints) . '}')
		if a:start == 1
			" not sleeping will send the events together
			sleep 150m
			call s:NodeInspectContinue()
		endif
	else
		call s:sendEvent('{"m": "nd_restart"}')
	endif
endfunction


function! OnNodeInspectExit(...)
	call s:NodeInspectCleanup()
endfunction


function! OnNodeInspectNvimExit(...)
	" close the window as there's no such option in termopen
	call win_gotoid(s:repl_win)
	execute "bd!"
	call s:NodeInspectCleanup()
endfunction


" when entering a buffer, display relevant breakpoints for this file
function! OnBufEnter()
	let filename = expand('%:p')
	if has_key(s:breakpointsUnhandledBuffers, filename) == 1
		" add relevant breakpoints signs
		for lineKey in keys(s:breakpoints[filename])
			" add sign override previous value
			let signId =s:addBrkptSign(filename, lineKey)
			call s:addBreakpoint(filename, lineKey, signId)
		endfor
		" its handled, remove it
		unlet s:breakpointsUnhandledBuffers[filename]
	endif
endfunction


function! nodeinspect#OnNodeInspectEnter()
	call s:SignInit()
	call s:loadConfigFile()
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
    call s:NodeInspectStart(0, '')
endfunction

function! nodeinspect#NodeInspectStartRun()
    call s:NodeInspectStart(1, '')
endfunction

function! nodeinspect#NodeInspectConnect(tsap)
	if s:initiated == 1
		echo "close running instance first"
		return
	endif
	call s:NodeInspectStart(0,a:tsap)
endfunction


