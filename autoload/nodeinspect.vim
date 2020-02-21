let s:initiated = 0
let s:connectionType = ''
let s:connectionTsap = ''
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
let s:lastStartIsRunning = 0
let s:msgDelimiter = '&&'

autocmd VimLeavePre * call OnVimLeavePre()
autocmd BufWritePost * call OnBufWritePost()

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
		let workingDir = getcwd()
		for fileLine in readfile(s:breakpointsFile, '')
			let brkList = split(fileLine,"#")
			let filename = brkList[0]
			let allLines = split(brkList[1],',') 
			" add breakpoints only if relevant to the current pwd.
			if stridx(filename, workingDir) != -1
				" load the buffer in the background if not loaded already
				if bufloaded(filename) == 0
					execute  "badd ".filename
				endif
				" adding to breakpoint list but not yet setting the breakpoints signs.
				" this will be done in the bufenter autocmd
				for line in allLines
					"call s:addBreakpoint(filename, str2nr(line), 0)
					let line = str2nr(line)
					echom "adding breakpoint ".filename.":".line
					" mostly will not be initiated.
					if s:initiated == 0
						let signId =	s:addBrkptSign(filename, line)
						call s:addBreakpoint(filename, line, signId)
					else 
						let remoteFile = s:getRemoteFilePath(filename)
						call s:sendEvent('{"m": "nd_addbrkpt", "file":"' . remoteFile . '", "line":' . line . '}')
					endif
				endfor
			endif
		endfor
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
		if type(configObj) == 4 && has_key(configObj,"localRoot") == 1 && has_key(configObj,"remoteRoot") == 1
			let s:configuration["localRoot"] = configObj["localRoot"]
			let s:configuration["remoteRoot"] = configObj["remoteRoot"]
			" add trailing backslash if not present. it will normalize both inputs
			" in case the user add one with and one without
			if s:configuration["localRoot"][-1:-1] != '/' 
				let s:configuration["localRoot"] = s:configuration["localRoot"] . '/'
			endif
			if s:configuration["remoteRoot"][-1:-1] != '/' 
				let s:configuration["remoteRoot"] = s:configuration["remoteRoot"] . '/'
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


" if configuration applies, get the local file path
function! s:getLocalFilePath(file)
	if has_key(s:configuration,"localRoot") == 0 || has_key(s:configuration,"remoteRoot") == 0
		return a:file
	endif
	" files arrive relative(?) is so, add '/'
	"let preFileStr = ''
	"if strlen(a:file)>1 && a:file[0:0] != '/' && strlen(s:configuration["remoteRoot"]) > 1 && s:configuration["remoteRoot"][0:0] == '/'
		let preFileStr = '/'
	"endif
	" strip file of its path, add it to the local
	let localFile = substitute(preFileStr.a:file,	s:configuration["remoteRoot"], s:configuration["localRoot"], "")
	return localFile
endfunction




" if configuration applies, get the remote file path
function! s:getRemoteFilePath(file)
	if has_key(s:configuration,"localRoot") == 0 || has_key(s:configuration,"remoteRoot") == 0
		return a:file
	endif
	" strip file of its path, add it to the remote
	let remoteFile = substitute(a:file,	s:configuration["localRoot"], s:configuration["remoteRoot"], "")
	return remoteFile
endfunction

" if configuration applies, get the breakpoints object normalized according to
" the remote path.
function! s:getRemoteBreakpointsObj(breakpoints)
	if has_key(s:configuration,"localRoot") == 0 || has_key(s:configuration,"remoteRoot") == 0
		return a:breakpoints
	endif
	let remoteBreakpoints = {}
	for filename in keys(a:breakpoints)
		let remoteFile = s:getRemoteFilePath(filename)
		let remoteBreakpoints[remoteFile] = {}
		for lineKey in keys(a:breakpoints[filename])
			let remoteBreakpoints[remoteFile][lineKey] = a:breakpoints[filename][lineKey]
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
" node inspect notification will ocuur only if started
function! s:NodeInspectRemoveAllBreakpoints(inspectNotify)
	for filename in keys(s:breakpoints)
		for line in keys(s:breakpoints[filename])
			let signId = s:breakpoints[filename][line]
			call s:removeBreakpoint(filename, line)
			if signId != 0
				call s:removeBrkptSign(signId, filename)
			endif
		endfor
	endfor
	if a:inspectNotify == 1 && s:initiated == 1
		let remoteFiles = s:getRemoteBreakpointsObj(s:breakpoints)
		call s:sendEvent('{"m": "nd_removeallbrkpts", "breakpoints":' . json_encode(remoteFiles) . '}')
	endif
endfunction

" called when node resolves this to a location.
" in case the breakpoint buffer is not loaded (such as the case of loading
" previous code), a bg buffer will be added, only if its relevant to the
" current pwd. See readme for more info on this.
function! s:breakpointResolved(file, line)
	let localFile = s:getLocalFilePath(a:file)
	if filereadable(localFile)
		let found = 0
		let loaded = 0
		for buf in getbufinfo()
			if buf.name == a:file
				let found = 1
				let loaded = 1
				break
			endif
		endfor
		if found == 0
			" check if to load the file or not
			let workingDir = getcwd()
			if stridx(a:file, workingDir) != -1
				if bufloaded(a:file) == 0
					execute  "badd ".a:file
				endif
				let loaded = 1
			endif
		endif
		if loaded == 1
			let signId = s:addBrkptSign(localFile, a:line)
			call s:addBreakpoint(localFile, a:line, signId)
		endif
	endif
endfunction


" toggle a breakpoint
" in case a breakpoint does not exist in this location, solve it throught
" devtools protocol. the callback will set the breakpoint.
" in case if does exist, remove it.
" that said, in case the debugger is not set - setting a breakpoint will
" always succeed and once the debugger is started it will be validated.
function! s:NodeInspectToggleBreakpoint()
	" disabled when a buffer is modified
	if &mod == 1
		echom "Can't toggle a breakpoint while file is dirty"
		return
	endif
	" check if the file is in the directory and check for relevant line
	let file = expand('%:p')
	let line = line('.')
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
		" request to add this sign. if node inspect was not started yet, add it to
		" the list
		if s:initiated == 0
			let signId =	s:addBrkptSign(file, line)
			call s:addBreakpoint(file, line, signId)
		else 
			let remoteFile = s:getRemoteFilePath(file)
			call s:sendEvent('{"m": "nd_addbrkpt", "file":"' . remoteFile . '", "line":' . line . '}')
		endif
	endif
endfunction



" empty the backtrace window, adds a 'debugger not stopped' window by default
" or a user message
function! s:clearBacktraceWindow(...)
	if a:0 == 0
		let message = 'Debugger not stopped'
	else
		let message = a:1
	endif
	let cur_win = win_getid()
	let gotoResult = win_gotoid(s:backtrace_win)
	if gotoResult == 1
		" execute "set modifiable"
		execute "%d"
		call setline('.', message)
		" execute "set nomodifiable"
		call win_gotoid(cur_win)
		" execute "set modifiable"
	endif
endfunction


" called when the debuggger was stopped. settings signs and position
function! s:onDebuggerStopped(mes)
	" open the relevant file only if it can be found locally
	" translate to local in case of remote connection
	let localFile = s:getLocalFilePath(a:mes["file"])
	if filereadable(localFile)
		" print backtrace
		let gotoResult = win_gotoid(s:backtrace_win)
		if gotoResult == 1
			" execute "set modifiable"
			execute "%d"
			for traceEntry in a:mes["backtrace"]
				" props are name & frameLocation
				call append(getline('$'), traceEntry["name"].'['.traceEntry["frameLocation"].']')
			endfor
			execute 'normal! 1G'
			" execute "set nomodifiable"
		endif
		" goto editor window
		call win_gotoid(s:start_win)
		" execute "set modifiable"
		execute "edit " . localFile
		execute ":" . a:mes["line"]
		call s:addSign(localFile, a:mes["line"])
	else
		call s:clearBacktraceWindow('Debugger Stopped. Source file is not available')
	endif
	" request watches update	
	let watches = nodeinspect#watches#GetWatches()
	let watchesJson = json_encode(watches)
	call s:sendEvent('{"m": "nd_updatewatches", "watches":' . watchesJson . '}')
endfunction


" called when the debuggger session was stopped unintentionally (js error?)
function! s:onDebuggerHalted()
	"call s:removeSign()
	call s:clearBacktraceWindow('Debugger not running')
endfunction



" on receiving a message from the node bridge.
" multiple messages might arrive at one call hence the splitting.
function! OnNodeMessage(channel, msgs)
	if len(a:msgs) == 0 || len(a:msgs) == 1 && len(a:msgs[0]) == 0
		" currently ignoring; called at the end (nvim)
		let mes = ''
	else
		if type(a:msgs) == 3
			" nvim receives this as a list
			let messageText = a:msgs[0]
			let messages = split(messageText, s:msgDelimiter)
		else
			" and vim as string
			let messages = split(a:msgs, s:msgDelimiter)
		endif
		for msg in messages
			let mes = json_decode(msg)
			if mes["m"] == "nd_stopped"
				call s:onDebuggerStopped(mes)
			elseif mes["m"] == "nd_halt"
				call s:onDebuggerHalted()
			elseif mes["m"] == "nd_brk_resolved"
				"echom "breakpoint resolved ".mes["file"]." ".mes["line"]
				call s:breakpointResolved(mes["file"],mes["line"])
			elseif mes["m"] == "nd_brk_failed"
				echom "cant set breakpoint"
			elseif mes["m"] == "nd_sockerror"
				echom "vim-node-inspect: failed to connect to remote host"
			elseif mes["m"] == "nd_restartequired"
				call s:NodeInspectStart(s:lastStartIsRunning, s:connectionTsap)
			else
				echo "vim-node-inspect: unknown message "
			endif
		endfor
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
	let inspectWinId = nodeinspect#watches#GetWinId()
	if inspectWinId != -1 && win_gotoid(inspectWinId) == 1
		execute "bd!"
	endif
	call s:NodeInspectCleanup()
endfunction


" when saving a buffer during a debugg session, session should be restarted.
function! OnBufWritePost()
	if s:initiated == 1
		let filename = expand('%:p')
		let remoteFile = s:getRemoteFilePath(filename)
		call s:sendEvent('{"m": "nd_verifyrestart", "file":"' . remoteFile . '"}')
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

" pause - stop a running script
function! s:NodeInspectPause()
	call s:sendEvent('{"m": "nd_pause"}')
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

	" load configuration or remove it if needed. This will remove the entire
	" configuraton; its ok for now as it holds only connection related stuff
	if a:tsap == ''
		let s:connectionType = 'program'
		let s:connectionTsap = ''
		let s:configuration = {}
	else
		let s:connectionTsap = a:tsap
		let s:connectionType = 'attach'
		call s:LoadConfigFile()
	endif

	" remove breakpoints if any, they will be re-invalidated after the debugger
	" will (re)start.
	let remoteBreakpoints = s:getRemoteBreakpointsObj(s:breakpoints)
	" that saves me from deepcopy
	let remoteBreakpointsJson = json_encode(remoteBreakpoints)

	" register global on exit, add signs 
	if s:initiated == 0
		" start
		let s:initiated = 1
		" remove all breakpoint, they will be resolved by node-inspect
		call s:NodeInspectRemoveAllBreakpoints(0)
		let s:start_win = win_getid()
		if s:connectionType == 'program'
			let file = expand('%:p')
		endif
		" create bottom buffer, switch to it
		execute "bo ".winheight(s:start_win)/3."new"
		let s:repl_win = win_getid()
		set nonu
		" open split for call stack
		execute "rightb ".winwidth(s:start_win)/3."vnew | setlocal nobuflisted buftype=nofile bufhidden=wipe noswapfile statusline=Callstack"
		let s:backtrace_win = win_getid()
		set nonu
		call s:clearBacktraceWindow()
		" create inspect window
		execute "rightb ".winwidth(s:start_win)/3."vnew | setlocal nobuflisted buftype=nofile bufhidden=wipe noswapfile statusline=Watches"
		call nodeinspect#watches#SetWinId(win_getid())
		set nonu
		" back to repl win
		call win_gotoid(s:repl_win)
		" is it with a filename or connection to host:port?
		if s:connectionType == 'program'
			if has("nvim")
				execute "let s:term_id = termopen ('node " . s:plugin_path . "/node-inspect/cli.js " . file . "', {'on_exit': 'OnNodeInspectExit'})"
			else
				execute "let s:term_id = term_start ('node " . s:plugin_path . "/node-inspect/cli.js " . file . "', {'curwin': 1, 'exit_cb': 'OnNodeInspectExit', 'term_finish': 'close', 'term_kill': 'kill'})"
			endif
		else
			if has("nvim")
				execute "let s:term_id = termopen ('node " . s:plugin_path . "/node-inspect/cli.js " . s:connectionTsap . "', {'on_exit': 'OnNodeInspectExit'})"
			else
				execute "let s:term_id = term_start ('node " . s:plugin_path . "/node-inspect/cli.js " . s:connectionTsap . "', {'curwin': 1, 'exit_cb': 'OnNodeInspectExit', 'term_finish': 'close', 'term_kill': 'kill'})"
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
		" send a conencted message, when connecting to a remote instance
		" (node-inspect doesn't display anything in this case)
		if s:connectionType == 'attach'
			sleep 100m
			call s:sendEvent('{"m": "nd_print", "txt":"Connected to '.s:connectionTsap.'\n"}')
		endif
	else
		" remove all breakpoint, they will be resolved by node-inspect
		call s:NodeInspectRemoveAllBreakpoints(0)
		sleep 150m
		call s:removeSign()
		call s:clearBacktraceWindow()
		call s:sendEvent('{"m": "nd_restart"}')
		sleep 200m
	endif

	" send breakpoints, if any
	sleep 150m
	call s:sendEvent('{"m": "nd_setbreakpoints", "breakpoints":' . remoteBreakpointsJson . '}')
	if a:start == 1 && s:connectionType == 'program'
		" not sleeping will send the events together
		sleep 150m
		call s:NodeInspectRun()
	endif

endfunction


" Callable functions / plugin API
function! nodeinspect#NodeInspectToggleBreakpoint()
	call s:NodeInspectToggleBreakpoint()
endfunction

function! nodeinspect#NodeInspectRemoveAllBreakpoints()
	call s:NodeInspectRemoveAllBreakpoints(1)
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

function! nodeinspect#NodeInspectPause()
	if s:initiated == 0
		echo "node-inspect not started"
		return
	endif
	call s:NodeInspectPause()
endfunction

function! nodeinspect#NodeInspectRun()
	let s:lastStartIsRunning = 1
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
	let s:lastStartIsRunning = 0
	if s:initiated == 0
		call s:NodeInspectStart(0, '')
	else
		call s:NodeInspectStart(0, s:connectionTsap)
	endif
endfunction

function! nodeinspect#NodeInspectConnect(tsap)
	if s:initiated == 1
		echo "close running instance first"
		return
	endif
	let s:lastStartIsRunning = 0
	call s:NodeInspectStart(0,a:tsap)
endfunction

function! nodeinspect#NodeInspectAddWatch()
	call nodeinspect#watches#AddWatch()
endfunction

function! nodeinspect#NodeInspectRemoveWatch()
	call nodeinspect#watches#RemoveWatch()
endfunction

