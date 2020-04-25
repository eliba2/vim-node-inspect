let s:configFileName = 'vim-node-config.json' 

function! s:removeSessionKeys(session,...)
	for uvar in a:000
		if has_key(a:session, uvar)
			call remove(a:session, uvar)
		endif
	endfor
endfunction


" configuration defualts, for parameters which might or might not appear in
" the configuration.
function! nodeinspect#config#SetConfigurationDefaults(session)
	let a:session["restart"] = 0
endfunction


" replace macros for a string. current recognizable macros (well, one):
" ${workspaceFolder} = pwd
function! s:ReplaceMacros(str)
	let replaced = a:str
	if match(replaced, "${workspaceFolder}") != -1
		let currentDirectory = getcwd()
		let replaced = substitute(a:str,	"${workspaceFolder}", currentDirectory ,"")
	endif
	return replaced
endfunction


" try and load the config file; it migth not exist, in this case use the
" defaults. returns 0 on success, !0 on failure.
function! nodeinspect#config#LoadConfigFile(configuration, session)
	"let a:configuration = {}
	let configFilePath = getcwd() . '/' . s:configFileName
	let fullFile = ''
	" clear previous sessoin config
	call s:removeSessionKeys(a:session,"localRoot","remoteRoot")

	if filereadable(configFilePath)
		let lines = readfile(configFilePath)
		for line in lines
			let fullFile = fullFile . line
		endfor
		" loaded the entire file, parse it to object
		let configObj = json_decode(fullFile)
		if type(configObj) == 4 
			if has_key(configObj,"localRoot") == 1 && has_key(configObj,"remoteRoot") == 1
				let a:configuration["localRoot"] = s:ReplaceMacros(configObj["localRoot"])
				let a:configuration["remoteRoot"] = configObj["remoteRoot"]
				" add trailing backslash if not present. it will normalize both inputs
				" in case the user add one with and one without
				if a:configuration["localRoot"][-1:-1] != '/' 
					let a:configuration["localRoot"] = a:configuration["localRoot"] . '/'
				endif
				if a:configuration["remoteRoot"][-1:-1] != '/' 
					let a:configuration["remoteRoot"] = a:configuration["remoteRoot"] . '/'
				endif
			endif
			if has_key(configObj,"request") == 1
				if configObj["request"] == 'attach' || configObj["request"] == 'launch'
					let a:configuration["request"] = configObj["request"]
				else
					echom "error reading launch in vim-node-inspect"
					return 1
				endif
			endif
			if has_key(configObj,"program") == 1
				if type(configObj["program"]) == 1
					let a:configuration["program"] = s:ReplaceMacros(configObj["program"])
				else
					echom "error reading program in vim-node-inspect"
					return 1
				endif
			endif
			if has_key(configObj,"address") == 1
				if type(configObj["address"]) == 1
					let a:configuration["address"] = configObj["address"]
				else
					echom "error reading address in vim-node-inspect"
					return 1
				endif
			endif
			if has_key(configObj,"port") == 1
				if type(configObj["port"]) == 0
					let a:configuration["port"] = configObj["port"]
				else
					echom "error reading port in vim-node-inspect"
					return 1
				endif
			endif
			if has_key(configObj,"restart") == 1
				if configObj["restart"] == v:true || configObj["restart"] == 1
					let a:session["restart"] = 1
				else
					let a:session["restart"] = 0
				endif
			endif

			" validate config and setup session
			if has_key(a:configuration, "request") == 1 
				if a:configuration["request"] == 'attach' 
					if has_key(a:configuration, "port") == 0
						echom "vim-node-inspect config error, attach without a port"
						return 1
					else
						let a:session["request"] = a:configuration["request"]
						let a:session["port"] = a:configuration["port"]
						" address defaults to localhost
						if has_key(a:configuration, "address")
							let a:session["address"] = a:configuration["address"]
						else
							let a:session["address"] = "127.0.0.1"
						endif
					endif
				endif
				if a:configuration["request"] == 'launch' 
					if has_key(a:configuration, "restart") == 1
						echom "vim-node-inspect config error, restart in invalid in launch mode"
						return 1
					endif
					if has_key(a:configuration, "program") == 0
						echom "vim-node-inspect config error, launch without a program"
						return 1
					else
						let a:session["request"] = a:configuration["request"]
						let a:session["program"] = a:configuration["program"]
					endif
				endif
			endif
			if (has_key(a:configuration, "localRoot") == 1 || has_key(a:configuration, "remoteRoot") == 1)
				if ((has_key(a:configuration, "localRoot") == 1 && has_key(a:configuration, "remoteRoot") == 0) || (has_key(a:configuration, "localRoot") == 0 && has_key(a:configuration, "remoteRoot") == 1))
					echom 'vim-node-inspect directories set error'
					return 1
				else
					let a:session["localRoot"] = a:configuration["localRoot"]
					let a:session["remoteRoot"] = a:configuration["remoteRoot"]
				endif
			endif
		else
			echom 'error reading vim-node-config.json, not a valid json'
			return 1
		endif
	endif
endfunction

