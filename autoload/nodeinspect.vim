let s:initiated = 0
let s:plugin_path = expand('<sfile>:h:h')
let s:channel = 0
let s:sign_id = 2
let s:repl_win = -1
let s:backtrace_win = -1
let s:brkpt_sign_id = 3
let s:sign_group = 'visgroup'
let s:sign_cur_exec = 'vis'
let s:sign_brkpt = 'visbkpt'
let s:breakpoints = {}
let s:breakpointsUnhandledBuffers = {}
let s:breakpointsFile = s:plugin_path . '/breakpoints'
let s:configuration = {}
let s:configFileName = 'vim-node-config.json' 

autocmd VimLeavePre * call OnVimLeavePre()
autocmd BufEnter * call OnBufEnter()

" utility functions to add signs
function! s:addBrkptSign(file, line)
	let s:brkpt_sign_id = s:brkpt_sign_id + 1
	execute("sign place " . s:brkpt_sign_id . " line=" . a:line . " name=" . s:sign_brkpt . " group=" . s:sign_group . " file=" . a:file)
	return s:brkpt_sign_id
endfunction

function! s:removeBrkptSign(id, file)
	execute("sign unplace " . a:id . " group=" . s:sign_group . " file=" . a:file)
endfunction

function! s:addSign(file, line)
	execute("sign place " . s:sign_id . " line=" . a:line . " name=" . s:sign_cur_exec . " group=" . s:sign_group .  " file=" . a:file)
endfunction

function! s:removeSign()
	execute "sign unplace " . s:sign_id . " group=" . s:sign_group
endfunction

function! s:SignInit()
	" debug sign 
	execute "sign define " . s:sign_cur_exec . " text=>> texthl=Select"
	" breakpoint sign
	execute "sign define " . s:sign_brkpt . " text=() texthl=SyntasticErrorSign"
endfunction

" send event to node bridge
function! s:sendEvent(e)
	if has("nvim") && s:channel > 0
		call chansend(s:channel, a:e)
	elseif ch_status(s:channel) == "open"
		call ch_sendraw(s:channel, a:e)
	endif
endfunction


" write configuration (breakpoints) file
" it is serialized as a list of lines, each consist of
" <file>#<line>,<line>...
function! s:saveBreakpointsFile()
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
	call writefile(breakpointList, s:breakpointsFile)
endfunction

" load breakpoints file. see above for description.
function! s:loadBreakpointsFile()
	" breakpoints file
	if filereadable(s:breakpointsFile)
		for fileLine in readfile(s:breakpointsFile, '')
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
endfunction

" try and load the config file; it migth not exist, in this case use the
" defaults.
function! s:LoadConfigFile()
	let configFilePath = getcwd() . '/' . s:configFileName
	let fullFile = ''
	if filereadable(configFilePath)
		let lines = readfile(configFilePath)
		for line in lines
			let fullFile = fullFile . line
		endfor
		" loaded the entire file, parse it to object
		let configObj = json_decode(fullFile)
		if type(configObj) == 4 && has_key(configObj,"localPath") == 1 && has_key(configObj,"remotePath") == 1
			let s:configuration["localPath"] = configObj["localPath"]
			let s:configuration["remotePath"] = configObj["remotePath"]
			" add trailing backslash if not present. it will normalize both inputs
			" in case the user add one with and one without
			if s:configuration["localPath"][-1:-1] != '/' 
				let s:configuration["localPath"] = s:configuration["localPath"] . '/'
			endif
			if s:configuration["remotePath"][-1:-1] != '/' 
				let s:configuration["remotePath"] = s:configuration["remotePath"] . '/'
			endif
		endif
	endif
endfunction


" called on removal of the node bridge.
function! s:NodeInspectCleanup()
	let s:initiated = 0
	call s:removeSign()
	call s:saveBreakpointsFile()
	" close channel if available
	if has("nvim") && s:channel > 0
		call chanclose(s:channel)
	elseif ch_status(s:channel) == "open"
		call ch_close(s:channel)
	endif	
endfunction




" if configuration applies, get the remote file path
function! s:getRemoteFilePath(file)
	if has_key(s:configuration,"localPath") == 0 || has_key(s:configuration,"remotePath") == 0
		return a:file
	endif
	" strip file of its path, add it to the remote
	let remoteFile = substitute(a:file,	s:configuration["localPath"], s:configuration["remotePath"], "")
	return remoteFile
endfunction

" if configuration applies, get the breakpoints object normalized according to
" the remote path.
function! s:getRemoteBreakpointsObj()
	if has_key(s:configuration,"localPath") == 0 || has_key(s:configuration,"remotePath") == 0
		return s:breakpoints
	endif
	let remoteBreakpoints = {}
	for filename in keys(s:breakpoints)
		let remoteFile = s:getRemoteFilePath(filename)
		let remoteBreakpoints[remoteFile] = {}
		for lineKey in keys(s:breakpoints[filename])
			let remoteBreakpoints[remoteFile][lineKey] = s:breakpoints[filename][lineKey]
		endfor
	endfor
	return remoteBreakpoints
endfunction

" add a brekpoint to list
function! s:addBreakpoint(file, line, signId)
	if has_key(s:breakpoints, a:file) == 0
		" does not exist, add it, file and line
		let s:breakpoints[a:file] = {}
	endif
	let s:breakpoints[a:file][a:line] = a:signId
endfunction

" remove a breakpoint from the list.
function! s:removeBreakpoint(file, line)
	" its in, remove it
	call remove(s:breakpoints[a:file], a:line)
	" if the dictionary is empty, remove the file entirely
	if len(s:breakpoints[a:file]) == 0
		call remove(s:breakpoints, a:file)
	endif
endfunction

" remove all breakpoints. removes the signs is any
function! s:NodeInspectRemoveAllBreakpoints()
	for filename in keys(s:breakpoints)
		for line in keys(s:breakpoints[filename])
			let signId = s:breakpoints[filename][line]
			call s:removeBreakpoint(filename, line)
			if signId != 0
				call s:removeBrkptSign(signId, filename)
			endif
		endfor
	endfor
	if s:initiated == 1
		let remoteFiles = s:getRemoteBreakpointsObj()
		call s:sendEvent('{"m": "nd_removeallbrkpts", "breakpoints":' . json_encode(remoteFiles) . '}')
	endif
endfunction

" toggle a breakpoint. handles signs as well.
function! s:NodeInspectToggleBreakpoint()
	let file = expand('%:p')
	let line = line('.')
	" check if the file is in the directory and check for relevant line
	if has_key(s:breakpoints, file) == 1 && has_key(s:breakpoints[file], line) == 1
		let signId = s:breakpoints[file][line]
		call s:removeBreakpoint(file, line)
		" remove sign
		call s:removeBrkptSign(signId, file)
		" send event only if node-inspect was started
		if s:initiated == 1
			" remote file might be different according to configurations.
			let remoteFile = s:getRemoteFilePath(file)
			call s:sendEvent('{"m": "nd_removebrkpt", "file":"' . remoteFile . '", "line":' . line . '}')
		endif
	else
		" add sign, store id
		let signId =	s:addBrkptSign(file, line)
		call s:addBreakpoint(file, line, signId)
		" send event only if node-inspect was started
		if s:initiated == 1
			let remoteFile = s:getRemoteFilePath(file)
			call s:sendEvent('{"m": "nd_addbrkpt", "file":"' . file . '", "line":' . line . '}')
		endif
	endif
endfunction


" empty the backtrace window, adds a 'debugger not stopped' window
function! s:clearBacktraceWindow()
	let cur_win = win_getid()
	call win_gotoid(s:backtrace_win)
	execute "%d"
	call setline('.', 'Debugger not stopped')
	call win_gotoid(cur_win)
endfunction


" called when the debuggger was stopped. settings signs and position
function! s:onDebuggerStopped(mes)
	" open the relevant file only if it can be found locally
	if filereadable(a:mes["file"])
		" print backtrace
		call win_gotoid(s:backtrace_win)
		execute "%d"
		for traceEntry in a:mes["backtrace"]
			" props are name & frameLocation
			call append(getline('$'), traceEntry["name"].'['.traceEntry["frameLocation"].']')
		endfor
		execute 'normal! 1G'
		" goto editor window
		call win_gotoid(s:start_win)
		execute "edit " . a:mes["file"]
		execute ":" . a:mes["line"]
		call s:addSign(a:mes["file"], a:mes["line"])
	endif
endfunction

" on receiving a message from the node bridge
function! OnNodeMessage(channel, msg)
	if len(a:msg) == 0 || len(a:msg) == 1 &&  len(a:msg[0]) == 0
		" currently ignoring; called at the end (nvim)
		let mes = ''
	else
		let mes = json_decode(a:msg)
		if mes["m"] == "nd_stopped"
			call s:onDebuggerStopped(mes)
		elseif mes["m"] == "nd_sockerror"
			echom "vim-node-inspect: failed to connect to remote host"
		else
			echo "vim-node-inspect: unknown message "
		endif
	endif
endfunction

" on receiving a message from the node bridge (nvim)
function! OnNodeNvimMessage(channel, msg, name)
	call OnNodeMessage(a:channel, a:msg)
endfunction

" vim global exit handler
function! OnVimLeavePre(...)
	" close the bridge gracefully in any case its still running
	if s:initiated == 1
		call s:sendEvent('{"m": "nd_kill"}')
		sleep 150m
	endif
	call OnNodeInspectExit()
endfunction

" node exiting callback (vim)
function! OnNodeInspectExit(...)
	" make sure windows are closed (in case of stopped buffer)
	" in nvim there's no such option at all (close the window when closed)
	if s:repl_win != -1 && win_gotoid(s:repl_win) == 1
		execute "bd!"
	endif
	if s:backtrace_win != -1 && win_gotoid(s:backtrace_win) == 1
		execute "bd!"
	endif
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

" called upon startup, setting signs if any.
function! nodeinspect#OnNodeInspectEnter()
	call s:SignInit()
	call s:loadBreakpointsFile()
endfunction




" step over
function! s:NodeInspectStepOver()
	call s:removeSign()
	call s:clearBacktraceWindow()
	call s:sendEvent('{"m": "nd_next"}')
endfunction

" step into
function! s:NodeInspectStepInto()
	call s:removeSign()
	call s:clearBacktraceWindow()
	call s:sendEvent('{"m": "nd_into"}')
endfunction

" stop, kills node
function! s:NodeInspectStop()
	call s:removeSign()
	call s:clearBacktraceWindow()
	call s:sendEvent('{"m": "nd_kill"}')
endfunction

" run (continue)
function! s:NodeInspectRun()
	call s:removeSign()
	call s:clearBacktraceWindow()
	call s:sendEvent('{"m": "nd_continue"}')
endfunction

" step out
function! s:NodeInspectStepOut()
	call s:removeSign()
	call s:clearBacktraceWindow()
	call s:sendEvent('{"m": "nd_out"}')
endfunction

" connects to the bridge, to to 2s. 
" returns 1 if connected successfully, otherwise 0
function! s:ConnectToBridge()
	let retries = 10
	let connected = 0
	while retries >= 0
		sleep 200m
		if has("nvim")
			let s:channel = sockconnect("tcp", "localhost:9514", {"on_data": "OnNodeNvimMessage"})
			if s:channel > 0
				let connected = 1
				break
			endif
		else
			let s:channel = ch_open("localhost:9514", {"mode":"raw", "callback": "OnNodeMessage"})
			if ch_status(s:channel) == "open"
				let connected = 1
				break
			endif
		endif
		let retries -= 1
	endwhile
	return connected
endfunction


" starts node-inspect. connects to the node bridge.
function! s:NodeInspectStart(start, tsap)
	" must start with a file. at least for now.
	if bufname('') == '' && a:tsap == ''
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
		set nonu
		" open split for call stack
		execute "rightb 30vnew | setlocal nobuflisted buftype=nofile bufhidden=wipe noswapfile"
		let s:backtrace_win = win_getid()
		set nonu
		call s:clearBacktraceWindow()
		" back to repl win
		call win_gotoid(s:repl_win)
		" is it with a filename or connection to host:port?
		if a:tsap == ''
			if has("nvim")
				execute "let s:term_id = termopen ('node " . s:plugin_path . "/node-inspect/cli.js " . file . "', {'on_exit': 'OnNodeInspectExit'})"
			else
				execute "let s:term_id = term_start ('node " . s:plugin_path . "/node-inspect/cli.js " . file . "', {'curwin': 1, 'exit_cb': 'OnNodeInspectExit', 'term_finish': 'close', 'term_kill': 'kill'})"
			endif
		else
			if has("nvim")
				execute "let s:term_id = termopen ('node " . s:plugin_path . "/node-inspect/cli.js " . a:tsap . "', {'on_exit': 'OnNodeInspectExit'})"
			else
				execute "let s:term_id = term_start ('node " . s:plugin_path . "/node-inspect/cli.js " . a:tsap . "', {'curwin': 1, 'exit_cb': 'OnNodeInspectExit', 'term_finish': 'close', 'term_kill': 'kill'})"
			endif
		endif

		" switch back to start buf
		call win_gotoid(s:start_win)

		" wait for bridge conenction
		sleep 200m
		let connected = s:ConnectToBridge()
		if connected == 0
			" can't connect. exit.
			echom 'cant connect to node-bridge'
			return
		endif

		" send breakpoints, if any
		sleep 150m
		let remoteFiles = s:getRemoteBreakpointsObj()
		call s:sendEvent('{"m": "nd_setbreakpoints", "breakpoints":' . json_encode(remoteFiles) . '}')
		if a:start == 1
			" not sleeping will send the events together
			sleep 150m
			call s:NodeInspectRun()
		endif
	else
		call s:sendEvent('{"m": "nd_restart"}')
	endif
endfunction



" Callable functions / plugin API
function! nodeinspect#NodeInspectToggleBreakpoint()
	call s:NodeInspectToggleBreakpoint()
endfunction

function! nodeinspect#NodeInspectRemoveAllBreakpoints()
	call s:NodeInspectRemoveAllBreakpoints()
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

function! nodeinspect#NodeInspectRun()
	if s:initiated == 0
    call s:NodeInspectStart(1, '')
	else
		call s:NodeInspectRun()
	endif
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

function! nodeinspect#NodeInspectConnect(tsap)
	if s:initiated == 1
		echo "close running instance first"
		return
	endif
	" try and read the config file before starting
	call s:LoadConfigFile()
	call s:NodeInspectStart(0,a:tsap)
endfunction

