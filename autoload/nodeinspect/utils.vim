let s:channel = 0


" send event to node bridge
function! nodeinspect#utils#SendEvent(e)
	if has("nvim") && s:channel > 0
		call chansend(s:channel, a:e)
	elseif ch_status(s:channel) == "open"
		call ch_sendraw(s:channel, a:e)
	endif
endfunction


" connects to the bridge, up to 3s. 
" returns 1 if connected successfully, otherwise 0
function! nodeinspect#utils#ConnectToBridge()
	let retries = 15
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


function nodeinspect#utils#CloseChannel()
	if has("nvim") && s:channel > 0
		call chanclose(s:channel)
	elseif ch_status(s:channel) == "open"
		call ch_close(s:channel)
	endif	
endfunction
