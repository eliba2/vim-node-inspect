let s:status = 0 " 0 - not started. 1 - started 2 - session ended (bridge exists, node exited)
let s:plugin_path = expand('<sfile>:h:h')
let s:sign_id = 2
let s:repl_win = -1
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


function! s:removeSessionKeys(...)
	for uvar in a:000
		if has_key(s:session, uvar)
			call remove(s:session, uvar)
		endif
	endfor
endfunction


" try and load the config file; it migth not exist, in this case use the
" defaults. returns 0 on success, !0 on failure.
function! s:LoadConfigFile()
	let s:configuration = {}
	let configFilePath = getcwd() . '/' . s:configFileName
	let fullFile = ''
	" clear previous sessoin config
	call s:removeSessionKeys("localRoot","remoteRoot")

	if filereadable(configFilePath)
		let lines = readfile(configFilePath)
		for line in lines
			let fullFile = fullFile . line
		endfor
		" loaded the entire file, parse it to object
		let configObj = json_decode(fullFile)
		if type(configObj) == 4 
			if has_key(configObj,"localRoot") == 1 && has_key(configObj,"remoteRoot") == 1
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
			if has_key(configObj,"request") == 1
				if configObj["request"] == 'attach' || configObj["request"] == 'launch'
					let s:configuration["request"] = configObj["request"]
				else
					echom "error reading launch in vim-node-inspect"
					return 1
				endif
			endif
			if has_key(configObj,"program") == 1
				echom "type ".type(configObj["program"])
				if type(configObj["program"]) == 1
					let s:configuration["program"] = configObj["program"]
				else
					echom "error reading program in vim-node-inspect"
					return 1
				endif
			endif
			if has_key(configObj,"address") == 1
				if type(configObj["address"]) == 1
					let s:configuration["address"] = configObj["address"]
				else
					echom "error reading address in vim-node-inspect"
					return 1
				endif
			endif
			if has_key(configObj,"port") == 1
				if type(configObj["port"]) == 0
					let s:configuration["port"] = configObj["port"]
				else
					echom "error reading port in vim-node-inspect"
					return 1
				endif
			endif

			" validate config and setup session
			if has_key(s:configuration, "request") == 1 
				if s:configuration["request"] == 'attach' 
					if has_key(s:configuration, "port") == 0
						echom "vim-node-inspect config error, attach without a port"
						return 1
					else
						let s:session["request"] = s:configuration["request"]
						let s:session["port"] = s:configuration["port"]
						" address defaults to localhost
						if has_key(s:configuration, "address")
							let s:session["address"] = s:configuration["address"]
						else
							let s:session["address"] = "127.0.0.1"
						endif
					endif
				endif
				if s:configuration["request"] == 'launch' 
					if has_key(s:configuration, "program") == 0
						echom "vim-node-inspect config error, launch without a program"
						return 1
					else
						let s:session["request"] = s:configuration["request"]
						let s:session["program"] = s:configuration["program"]
					endif
				endif
			endif
			if (has_key(s:configuration, "localRoot") == 1 || has_key(s:configuration, "remoteRoot") == 1)
				if ((has_key(s:configuration, "localRoot") == 1 && has_key(s:configuration, "remoteRoot") == 0) || (has_key(s:configuration, "localRoot") == 0 && has_key(s:configuration, "remoteRoot") == 1))
					echom 'vim-node-inspect directories set error'
					return 1
				else
					let s:session["localRoot"] = s:configuration["localRoot"]
					let s:session["remoteRoot"] = s:configuration["remoteRoot"]
				endif
			endif
		else
			echom 'error reading vim-node-config.json, not a valid json'
			return 1
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
	" if that's the initial stop, resume.
	if s:session["start"] == 1 
		let s:session["start"] = 0
		if s:session["request"] == "launch" && (has_key(s:breakpoints, localFile) == 0 || has_key(s:breakpoints[localFile], a:mes["line"]) == 0)
			sleep 150m
			call s:NodeInspectRun()
			" we've resumed running, do not process any further
			return
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
			elseif mes["m"] == "nd_brk_failed"
				echom "cant set breakpoint"
			elseif mes["m"] == "nd_sockerror"
				echom "vim-node-inspect: failed to connect to remote host"
			elseif mes["m"] == "nd_restartequired"
				let s:session["start"] = s:session["lastStart"]
				call s:NodeInspectStart()
			elseif mes["m"] == "nd_watchesresolved"
				call nodeinspect#watches#OnWatchesResolved(mes['watches'])
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
	if s:repl_win != -1 && win_gotoid(s:repl_win) == 1
		execute "bd!"
	endif
	call nodeinspect#backtrace#KillBacktraceWindow()
	let inspectWinId = nodeinspect#watches#GetWinId()
	if inspectWinId != -1 && win_gotoid(inspectWinId) == 1
		execute "bd!"
	endif
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
" start (0/1) - start running, do not break on the first line (not supported
" by bridge, simulated in vim)
" tsap - conenction paramters, if any
function! s:NodeInspectStart()
	" load configuration. if execution is specified there it shall be used.
	if s:LoadConfigFile() != 0
		return
	endif
	" if app, must start with a file
	if bufname('') == '' && s:configuration["request"] == "launch"
		echom "node-inspect must start with a file. Save the buffer first"
		return
	endif
	" remove breakpoints if any, they will be re-invalidated after the debugger
	" will (re)start.
	let remoteBreakpoints = s:getRemoteBreakpointsObj(s:breakpoints)
	" that saves me from deepcopy
	let remoteBreakpointsJson = json_encode(remoteBreakpoints)
	" register global on exit, add signs 
	if s:status == 0
		" start
		let s:status = 1
		" remove all breakpoint, they will be resolved by node-inspect
		call s:NodeInspectRemoveAllBreakpoints(0)
		let s:start_win = win_getid()
		"if s:connectionType == 'program'
			"let file = expand('%:p')
		"endif
		" create bottom buffer, switch to it
		execute "bo ".winheight(s:start_win)/3."new"
		let s:repl_win = win_getid()
		set nonu
		" open split for call stack
		call nodeinspect#backtrace#CreateBacktraceWindow(s:start_win) 
		call nodeinspect#backtrace#ClearBacktraceWindow()
		" create inspect window
		call nodeinspect#watches#CreateWatchWindow(s:start_win) 
		" back to repl win
		call win_gotoid(s:repl_win)
		" start according to settings
		if s:session["request"] == "launch"
			if has("nvim")
				execute "let s:term_id = termopen ('node " . s:plugin_path . "/node-inspect/cli.js " . s:session["program"] . "', {'on_exit': 'OnNodeInspectExit'})"
			else
				execute "let s:term_id = term_start ('node " . s:plugin_path . "/node-inspect/cli.js " . s:session["program"] . "', {'curwin': 1, 'exit_cb': 'OnNodeInspectExit', 'term_finish': 'close', 'term_kill': 'kill'})"
			endif
		else
			if has("nvim")
				execute "let s:term_id = termopen ('node " . s:plugin_path . "/node-inspect/cli.js " . s:session["address"].":".s:session["port"] . "', {'on_exit': 'OnNodeInspectExit'})"
			else
				execute "let s:term_id = term_start ('node " . s:plugin_path . "/node-inspect/cli.js " . s:session["address"].":".s:session["port"] . "', {'curwin': 1, 'exit_cb': 'OnNodeInspectExit', 'term_finish': 'close', 'term_kill': 'kill'})"
			endif
		endif
		sleep 200m

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
		" set the status to running, might be ended(2)
		let s:status = 1
		" remove all breakpoint, they will be resolved by node-inspect
		call s:NodeInspectRemoveAllBreakpoints(0)
		sleep 150m
		call s:removeSign()
		call nodeinspect#backtrace#ClearBacktraceWindow()
		call nodeinspect#utils#SendEvent('{"m": "nd_restart"}')
		sleep 200m
	endif

	" send breakpoints, if any
	call nodeinspect#utils#SendEvent('{"m": "nd_setbreakpoints", "breakpoints":' . remoteBreakpointsJson . '}')
	sleep 150m
	" redraw the watch window; draws any watches added from the session
	for watch in keys(s:session["watches"])
		call nodeinspect#watches#AddBulk(s:session["watches"])
	endfor


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

function! nodeinspect#NodeInspectRun()
	if &mod == 1
		echom "Can't start while file is dirty, save the file first"
		return
	endif
	let s:session["lastStart"] = 1
	if s:status != 1
		let s:session["start"] = 1
		let s:session["port"] = -1
		let s:session["request"] = "launch"
		let s:session["program"] = expand('%:p')
    call s:NodeInspectStart()
	else
		call s:NodeInspectRun()
	endif
endfunction

function! nodeinspect#NodeInspectStop()
	if s:status != 1
		echo "node-inspect not started"
		return
	endif
	call s:NodeInspectStop()
endfunction

function! nodeinspect#NodeInspectStart()
	if &mod == 1
		echom "Can't start while file is dirty, save the file first"
		return
	endif
	let s:session["lastStart"] = 0
	if s:status != 1
		let s:session["start"] = 0
		let s:session["port"] = -1
		let s:session["request"] = "launch"
		let s:session["program"] = expand('%:p')
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
	let s:session["start"] = 0
	call s:NodeInspectStart()
endfunction

function! nodeinspect#NodeInspectAddWatch()
	call nodeinspect#watches#AddCurrentWordAsWatch()
endfunction

function! nodeinspect#GetStatus()
	return s:GetStatus()
endfunction

