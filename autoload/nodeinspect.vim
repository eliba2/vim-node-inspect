let s:status = 0 " 0 - not started. 1 - started 2 - session ended (bridge exists, node exited) 3 - restarting
let s:plugin_path = expand('<sfile>:h:h')
let s:sign_id = 2
let s:brkpt_sign_id = 3
let s:sign_group = 'visgroup'
let s:sign_cur_exec = 'vis'
let s:sign_brkpt = 'visbkpt'
let s:breakpoints = {}
let s:session = {}
let s:breakpointsUnhandledBuffers = {}
let s:sessionFile = s:plugin_path . '/vim-node-session.json'
let s:configuration = {}
let s:configFileName = 'vim-node-config.json' 
let s:msgDelimiter = '&&'

highlight default NodeInspectBreakpoint ctermfg=0 ctermbg=11 guifg=#E6E1CF guibg=#FF3333
highlight default NodeInspectSign ctermfg=12 ctermbg=6 gui=bold guifg=Blue guibg=DarkCyan

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
	execute("sign place " . s:sign_id . " line=" . a:line . " name=" . s:sign_cur_exec . " group=" . s:sign_group . " file=" . a:file)
endfunction

function! s:removeSign()
	execute "sign unplace " . s:sign_id . " group=" . s:sign_group
endfunction

function! s:SignInit()
	" debug sign 
	execute "sign define " . s:sign_cur_exec . " text=>> texthl=NodeInspectSign linehl=NodeInspectSign"
	" breakpoint sign
	execute "sign define " . s:sign_brkpt . " text=() texthl=NodeInspectBreakpoint"
endfunction


" write session file, json format
function! s:saveSessionFile()
	let config = {}
	let config['breakpoints'] = s:breakpoints
	let config['watches'] = nodeinspect#watches#GetWatchesKeys()
	call writefile([json_encode(config)], s:sessionFile)
endfunction

" load session file.
function! s:loadSessionFile()
	let s:session["watches"] = {}
	if filereadable(s:sessionFile)
		let workingDir = getcwd()
		let configRaw = join(readfile(s:sessionFile, "\n"))
		let config = json_decode(configRaw)
		if has_key(config, "breakpoints")
			" the breakpoint configuration is a key-value object, filname: {
			" line:id, line:id ... }
			for filename in keys(config["breakpoints"])
				if stridx(filename, workingDir) != -1
					" load the buffer in the background if not loaded already
					if bufloaded(filename) == 0
						execute  "badd ".filename
					endif
					for lineStr in keys(config["breakpoints"][filename])
						let line = str2nr(lineStr)
						echom "adding breakpoint ".filename.":".line
						" mostly will not be initiated.
						if s:status != 1
							let signId =	s:addBrkptSign(filename, line)
							call s:addBreakpoint(filename, line, signId)
						else 
							let remoteFile = s:getRemoteFilePath(filename)
							call nodeinspect#utils#SendEvent('{"m": "nd_addbrkpt", "file":"' . remoteFile . '", "line":' . line . '}')
						endif
					endfor
				endif
			endfor
		endif
		if has_key(config, "watches")
			let s:session["watches"] = config["watches"]
		endif
	endif
endfunction


" called on removal of the node bridge.
function! s:NodeInspectCleanup()
	let s:status = 0
	call s:removeSign()
	call s:saveSessionFile()
	" close channel if available
	call nodeinspect#utils#CloseChannel()
endfunction


" if configuration applies, get the local file path
function! s:getLocalFilePath(file)
	if has_key(s:session,"localRoot") == 0 || has_key(s:session,"remoteRoot") == 0
		return a:file
	endif
	" files arrive relative(?) is so, add '/'
	let preFileStr = ''
	"if strlen(a:file)>1 && a:file[0:0] != '/' && strlen(s:configuration["remoteRoot"]) > 1 && s:configuration["remoteRoot"][0:0] == '/'
		"let preFileStr = '/'
	"endif
	" strip file of its path, add it to the local
	let localFile = substitute(preFileStr.a:file,	s:session["remoteRoot"], s:session["localRoot"], "")
	return localFile
endfunction




" if configuration applies, get the remote file path
function! s:getRemoteFilePath(file)
	if has_key(s:session,"localRoot") == 0 || has_key(s:session,"remoteRoot") == 0
		return a:file
	endif
	" strip file of its path, add it to the remote
	let remoteFile = substitute(a:file,	s:session["localRoot"], s:session["remoteRoot"], "")
	return remoteFile
endfunction

" if configuration applies, get the breakpoints object normalized according to
" the remote path.
function! s:getRemoteBreakpointsObj(breakpoints)
	if has_key(s:session,"localRoot") == 0 || has_key(s:session,"remoteRoot") == 0
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
	if a:inspectNotify == 1 && s:status == 1
		let remoteFiles = s:getRemoteBreakpointsObj(s:breakpoints)
		call nodeinspect#utils#SendEvent('{"m": "nd_removeallbrkpts", "breakpoints":' . json_encode(remoteFiles) . '}')
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
			if buf.name == localFile
				let found = 1
				let loaded = 1
				break
			endif
		endfor
		if found == 0
			" check if to load the file or not
			let workingDir = getcwd()
			if stridx(localFile, workingDir) != -1
				if bufloaded(localFile) == 0
					execute  "badd ".localFile
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
		if s:status == 1
			" remote file might be different according to configurations.
			let remoteFile = s:getRemoteFilePath(file)
			call nodeinspect#utils#SendEvent('{"m": "nd_removebrkpt", "file":"' . remoteFile . '", "line":' . line . '}')
		endif
	else
		" request to add this sign. if node inspect was not started yet, add it to
		" the list
		if s:status != 1
			let signId =	s:addBrkptSign(file, line)
			call s:addBreakpoint(file, line, signId)
		else 
			let remoteFile = s:getRemoteFilePath(file)
			call nodeinspect#utils#SendEvent('{"m": "nd_addbrkpt", "file":"' . remoteFile . '", "line":' . line . '}')
		endif
	endif
endfunction


" called when the debuggger was stopped. settings signs and position
function! s:onDebuggerStopped(mes)
	" open the relevant file only if it can be found locally
	" translate to local in case of remote connection
	let localFile = s:getLocalFilePath(a:mes["file"])
	let readable = filereadable(localFile)
	" if this the initial stop for launch, process breakpoints in here and
	" continue running if start-run is to be emulated
	if s:session["request"] == "launch"
		if s:session["initialLaunchBreak"] == 1
			let s:session["initialLaunchBreak"] = 0
			" if there are any breakpoints to set, set them now. If started running, execution will
			" continue when resolved
			if len(s:breakpoints) > 0
				let remoteBreakpoints = s:getRemoteBreakpointsObj(s:breakpoints)
				" that saves me from deepcopy
				let remoteBreakpointsJson = json_encode(remoteBreakpoints)
				" remove all breakpoint, they will be resolved and set by node-inspect
				call s:NodeInspectRemoveAllBreakpoints(0)
				" send breakpoints, if any
				call nodeinspect#utils#SendEvent('{"m": "nd_setbreakpoints", "breakpoints":' . remoteBreakpointsJson . '}')
			else
				" no breakpoints to resolve
				if s:session["startRun"] == 1 
					let s:session["startRun"] = 0 
					sleep 150m
					call s:NodeInspectRun()
					" return as the script continues
					return
				endif
			endif
		endif
	endif
	
	if readable 
		" print backtrace
		call nodeinspect#backtrace#DisplayBacktraceWindow(a:mes["backtrace"])
		" goto editor window
		call win_gotoid(s:start_win)
		" execute "set modifiable"
		execute "edit " . localFile
		execute ":" . a:mes["line"]
		call s:addSign(localFile, a:mes["line"])
	else
		if !readable
			call nodeinspect#backtrace#ClearBacktraceWindow('Debugger Stopped. Source file is not available')
		endif
	endif
	" request watches update	
	call nodeinspect#watches#UpdateWatches()
endfunction


" called when the debuggger session was stopped unintentionally (js error?)
function! s:onDebuggerHalted()
	"call s:removeSign()
	let s:status = 2
	call nodeinspect#backtrace#ClearBacktraceWindow('Session ended')
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
				if s:session["request"] == "launch" && s:session["startRun"] == 1 
					let s:session["startRun"] = 0
					sleep 150m
					call s:NodeInspectRun()
				endif
			elseif mes["m"] == "nd_brk_failed"
				echom "cant set breakpoint"
				if s:session["request"] == "launch" && s:session["startRun"] == 1 
					let s:session["startRun"] = 0
					sleep 150m
					call s:NodeInspectRun()
				endif
			elseif mes["m"] == "nd_sockerror"
				echom "vim-node-inspect: failed to connect to remote host"
			elseif mes["m"] == "nd_restartrequired"
				let s:session["startRun"] = s:session["lastStart"]
				call s:NodeInspectStart()
			elseif mes["m"] == "nd_watchesresolved"
				call nodeinspect#watches#OnWatchesResolved(mes['watches'])
			elseif mes["m"] == "nd_node_socket_closed"
				call s:onNodeInspectSocketClosed()
			elseif mes["m"] == "nd_node_socket_ready"
				if s:status == 3
					let s:status = 1
				endif
			elseif mes["m"] == "nd_repl_cont"
				call nodeinspect#NodeInspectRun()
			elseif mes["m"] == "nd_repl_kill"
				call nodeinspect#NodeInspectStop()
			elseif mes["m"] == "nd_repl_stepover"
				call nodeinspect#NodeInspectStepOver()
			elseif mes["m"] == "nd_repl_stepinto"
				call nodeinspect#NodeInspectStepInto()
			elseif mes["m"] == "nd_repl_stepout"
				call nodeinspect#NodeInspectStepOut()
			else
				echo "vim-node-inspect: unknown message ".mes["m"]
			endif
			" post handle triggers
			if mes["m"] == "nd_brk_resolved" || mes["m"] == "nd_brk_failed"
				" handle start-run. run is emulated when breakpoints are resolved (if
				" any)
				if s:session["request"] == "launch" && s:session["startRun"] == 1 
					let s:session["startRun"] = 0
					" only continue running of not requested to stop on the initial
					" line.
					let localFile = s:getLocalFilePath(mes["file"])
					if has_key(s:breakpoints, localFile) == 0 || has_key(s:breakpoints[localFile], mes["line"]) == 0
						sleep 150m
						call s:NodeInspectRun()
						" we've resumed running, do not process any further
						return
					endif
				endif
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
	if s:status != 0
		call nodeinspect#utils#SendEvent('{"m": "nd_kill"}')
		sleep 150m
	endif
	call OnNodeInspectExit()
endfunction

" node exiting callback (vim)
function! OnNodeInspectExit(...)
	" make sure windows are closed (in case of stopped buffer)
	" in nvim there's no such option at all (close the window when closed)
	call nodeinspect#repl#KillReplWindow()
	call nodeinspect#backtrace#KillBacktraceWindow()
	call nodeinspect#watches#KillWatchWindow()
	call s:NodeInspectCleanup()
endfunction


" when saving a buffer during a debugg session, session should be restarted.
function! OnBufWritePost()
	if s:status == 1
		let filename = expand('%:p')
		let remoteFile = s:getRemoteFilePath(filename)
		call nodeinspect#utils#SendEvent('{"m": "nd_verifyrestart", "file":"' . remoteFile . '"}')
	endif
endfunction


" called when a session was terminated in node-inspect. Attempt to reconnect
" if 'restart' options was set
function! s:onNodeInspectSocketClosed()
	" in case of "restarting' status (3), ignore this as node-inspect restarts
	" and will cause a socket loss
	if s:status != 3
		if s:session["request"] == "attach" && s:session["restart"] == 1
			sleep 200m
			call s:NodeInspectStart()
		else
			let s:status = 2
			call nodeinspect#backtrace#ClearBacktraceWindow('Session ended')
		endif
	endif
endfunction


" called upon startup, setting signs if any.
function! nodeinspect#OnNodeInspectEnter()
	call s:SignInit()
	call s:loadSessionFile()
endfunction


" step over
function! s:NodeInspectStepOver()
	call s:removeSign()
	call nodeinspect#backtrace#ClearBacktraceWindow()
	call nodeinspect#utils#SendEvent('{"m": "nd_next"}')
endfunction

" step into
function! s:NodeInspectStepInto()
	call s:removeSign()
	call nodeinspect#backtrace#ClearBacktraceWindow()
	call nodeinspect#utils#SendEvent('{"m": "nd_into"}')
endfunction

" stop, kills node
function! s:NodeInspectStop()
	call s:removeSign()
	call nodeinspect#backtrace#ClearBacktraceWindow()
	call nodeinspect#utils#SendEvent('{"m": "nd_kill"}')
endfunction

" run (continue)
function! s:NodeInspectRun()
	call s:removeSign()
	call nodeinspect#backtrace#ClearBacktraceWindow()
	call nodeinspect#utils#SendEvent('{"m": "nd_continue"}')
endfunction

" step out
function! s:NodeInspectStepOut()
	call s:removeSign()
	call nodeinspect#backtrace#ClearBacktraceWindow()
	call nodeinspect#utils#SendEvent('{"m": "nd_out"}')
endfunction

" pause - stop a running script
function! s:NodeInspectPause()
	call nodeinspect#utils#SendEvent('{"m": "nd_pause"}')
endfunction


" starts node-inspect. connects to the node bridge.
function! s:NodeInspectStart()
	" set configuration defaults 	
	call  nodeinspect#config#SetConfigurationDefaults(s:session)
	" load configuration. if execution is specified there it shall be used.  
	" clear configuration in here as it can't be done when passing a variable
	let s:configuration = {}
	if nodeinspect#config#LoadConfigFile(s:configuration, s:session) != 0
		return
	endif
	" if app, must start with a file
	if s:session["request"] == "launch" && s:session["script"] == ''
		echom "node-inspect must start with a file."
		return
	endif
	" register global on exit, add signs 
	if s:status == 0
		" start
		let s:status = 1
		let s:start_win = win_getid()
		" show all windows
		call nodeinspect#repl#ShowReplWindow(s:start_win) 
		call nodeinspect#backtrace#ShowBacktraceWindow(s:start_win) 
		call nodeinspect#watches#ShowWatchWindow(s:start_win) 
		" clear backtrace
		call nodeinspect#backtrace#ClearBacktraceWindow()
		" back to repl win
		call nodeinspect#repl#StartNodeInspect(s:session, s:plugin_path)
		" switch back to start buf
		call win_gotoid(s:start_win)
		" wait for bridge conenction
		let connected = nodeinspect#utils#ConnectToBridge()
		if connected == 0
			" can't connect. exit.
			echom 'cant connect to node-bridge'
			return
		endif
		" send a connected message, when connecting to a remote instance
		" (node-inspect doesn't display anything in this case)
		if s:session["request"] == "attach"
			sleep 100m
			call nodeinspect#utils#SendEvent('{"m": "nd_print", "txt":"Connected to '.s:session["port"].'\n"}')
			sleep 100m
		endif
	else
		" the current buffer file might change. get the current.
		if s:session["request"] == "launch" && s:session["configUsed"] == 0
			let gotoStartwin = win_gotoid(s:start_win)
			if gotoStartwin == 1
				let s:session["script"] = expand('%:p')
			endif
		endif
		" set the status to running, might be at ended(2)
		let s:status = 3
		" remove all breakpoint, they will be resolved by node-inspect
		call s:removeSign()
		call nodeinspect#backtrace#ClearBacktraceWindow()
		call nodeinspect#utils#SendEvent('{"m": "nd_restart", "script": "'. s:session["script"] . '","args": ' . json_encode(s:session["args"]) . '}')
		sleep 200m
	endif

	if s:session["request"] == "attach"
		" remove breakpoints if any, they will be re-invalidated after the debugger
		" will (re)start.
		if len(s:breakpoints) > 0
			let remoteBreakpoints = s:getRemoteBreakpointsObj(s:breakpoints)
			" that saves me from deepcopy
			let remoteBreakpointsJson = json_encode(remoteBreakpoints)
			" remove all breakpoint, they will be resolved and set by node-inspect
			call s:NodeInspectRemoveAllBreakpoints(0)
			" send breakpoints, if any
			call nodeinspect#utils#SendEvent('{"m": "nd_setbreakpoints", "breakpoints":' . remoteBreakpointsJson . '}')
			sleep 150m
		endif
	endif
	" redraw the watch window; draws any watches added from the session
	for watch in keys(s:session["watches"])
		call nodeinspect#watches#AddBulk(s:session["watches"])
	endfor

endfunction


" toggle the debugger window
function! s:NodeInspectToggleWindow()
	let s:start_win = win_getid()
	" hide or show the windows together
	let winOpen = nodeinspect#repl#IsWindowVisible() + nodeinspect#backtrace#IsWindowVisible() + nodeinspect#watches#IsWindowVisible()
	if winOpen == 0
		call nodeinspect#repl#ShowReplWindow(s:start_win) 
		call nodeinspect#backtrace#ShowBacktraceWindow(s:start_win) 
		call nodeinspect#watches#ShowWatchWindow(s:start_win) 
	else
		call nodeinspect#repl#HideReplWindow() 
		call nodeinspect#backtrace#HideBacktraceWindow() 
		call nodeinspect#watches#HideWatchWindow() 
	endif
	call win_gotoid(s:start_win)
endfunction


" get the current status (0 - not initialized, 1 - running, 2 - ended (bridge
" exists but no node). Used by modules.
function! s:GetStatus()
	return s:status
endfunction

" Callable functions / plugin API
function! nodeinspect#NodeInspectToggleBreakpoint()
	call s:NodeInspectToggleBreakpoint()
endfunction

function! nodeinspect#NodeInspectRemoveAllBreakpoints()
	call s:NodeInspectRemoveAllBreakpoints(1)
endfunction

function! nodeinspect#NodeInspectStepOver()
	if s:status != 1
		echo "node-inspect not started"
		return
	endif
	call s:NodeInspectStepOver()
endfunction

function! nodeinspect#NodeInspectStepInto()
	if s:status != 1
		echo "node-inspect not started"
		return
	endif
	call s:NodeInspectStepInto()
endfunction

function! nodeinspect#NodeInspectStepOut()
	if s:status != 1
		echo "node-inspect not started"
		return
	endif
	call s:NodeInspectStepOut()
endfunction

function! nodeinspect#NodeInspectPause()
	if s:status != 1
		echo "node-inspect not started"
		return
	endif
	call s:NodeInspectPause()
endfunction

function! nodeinspect#NodeInspectRun(...)
	if &mod == 1
		echom "Can't start while file is dirty, save the file first"
		return
	endif
	let s:session["lastStart"] = 1
	if s:status != 1
		let s:session["startRun"] = 1
		let s:session["port"] = -1
		let s:session["request"] = "launch"
		let s:session["script"] = expand('%:p')
		let s:session["initialLaunchBreak"] = 1
		let s:session["args"] = a:000[:]
    call s:NodeInspectStart()
	else
		call s:NodeInspectRun()
	endif
endfunction

function! nodeinspect#NodeInspectStop()
	if s:status == 0
		echo "node-inspect not started"
		return
	endif
	call s:NodeInspectStop()
endfunction

function! nodeinspect#NodeInspectStart(...)
	if &mod == 1
		echom "Can't start while file is dirty, save the file first"
		return
	endif
	let s:session["lastStart"] = 0
	if s:status != 1
		let s:session["startRun"] = 0
		let s:session["port"] = -1
		let s:session["request"] = "launch"
		let s:session["script"] = expand('%:p')
		let s:session["initialLaunchBreak"] = 1
		let s:session["args"] = a:000[:]
		call s:NodeInspectStart()
	endif
endfunction

function! nodeinspect#NodeInspectConnect(fullAdress)
	if &mod == 1
		echom "Can't start while file is dirty, save the file first"
		return
	endif
	if s:status == 1
		echo "close running instance first"
		return
	endif
	" break the full address into address/port
	let addressParts = split(a:fullAdress, ":")
	if len(addressParts) != 2
		echo "vim-node-inspect: bad address"
	endif
	let s:session["address"] = addressParts[0]
	let s:session["port"] = addressParts[1]
	let s:session["request"] = "attach"
	let s:session["lastStart"] = 0
	let s:session["startRun"] = 0
	let s:session["initialLaunchBreak"] = 0
	call s:NodeInspectStart()
endfunction

function! nodeinspect#NodeInspectAddWatch()
	call nodeinspect#watches#AddCurrentWordAsWatch()
endfunction

function! nodeinspect#GetStatus()
	return s:GetStatus()
endfunction


function! nodeinspect#NodeInspectToggleWindow()
	call s:NodeInspectToggleWindow()
endfunction

