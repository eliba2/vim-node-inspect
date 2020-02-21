
let s:inspect_win = -1
let s:watches = {}

autocmd InsertLeave * call OnTextModification()
autocmd TextChanged * call OnTextModification()


function! OnTextModification()
	if win_getid() != s:inspect_win 
		return
	endif
	call s:RecalcWatchesKeys()
	call s:Draw()
endfunction


function s:DrawKeysOnly()
	let cur_win = win_getid()
	let gotoResult = win_gotoid(s:inspect_win)
	if gotoResult == 1
		" execute "set modifiable"
		execute "%d"
		" execute "set nomodifiable"
		
		" loop here over all watches and update their values
		for watch in keys(s:watches)
			call append(getline('$'), watch)
		endfor
		
		" endofupdate
		call win_gotoid(cur_win)
		" execute "set modifiable"
	endif
endfunction



function s:Draw()
	let cur_win = win_getid()
	let gotoResult = win_gotoid(s:inspect_win)
	if gotoResult == 1
		" execute "set modifiable"
		execute "%d"
		" execute "set nomodifiable"
		
		" loop here over all watches and update their values
		for watch in keys(s:watches)
			call append(getline('$'), watch."      ".s:watches[watch])
		endfor
		
		" endofupdate
		call win_gotoid(cur_win)
		" execute "set modifiable"
	endif
endfunction



function s:RecalcWatchesKeys()
	let cur_win = win_getid()
	let gotoResult = win_gotoid(s:inspect_win)
	if gotoResult == 1
		let s:watches = {}
		" execute "set modifiable"
		execute 'normal! 1G'
		let currentLine = 1
		let totalLines = line('$')
		while currentLine <= totalLines
			let line = trim(getline(currentLine))
			if len(line) != 0
				let firstWord = split(line)[0]	
				let s:watches[firstWord] = "n/a"
			endif
			let currentLine += 1
		endwhile
		" execute "set nomodifiable"
		call win_gotoid(cur_win)
		" execute "set modifiable"
	endif
endfunction




function! nodeinspect#watches#GetWatches()
	return s:watches
endfunction


function! nodeinspect#watches#GetWinId()
	return s:inspect_win
endfunction


function! nodeinspect#watches#SetWinId(id)
	let s:inspect_win = a:id
endfunction


function! nodeinspect#watches#Draw()
	call s:Draw()
endfunction



" add a watch, input by vim's input
function! nodeinspect#watches#AddWatch()
	call inputsave()
  let watch = input('Enter name: ')
  call inputrestore()
	if len(watch) > 0
		if has_key(s:watches, watch) == 0
			let s:watches[watch] = 'n/a'
			call s:Draw()
		else
			echom "watch already exists"
		endif
	endif
endfunction

" remove a watch, input by vim's input
function! nodeinspect#watches#RemoveWatch()
	call inputsave()
  let watch = input('Enter name: ')
  call inputrestore()
	if len(watch) > 0
		if has_key(s:watches, watch) == 1
			call Draw()
		else
			echom "watch does not exist"
		endif
	endif
endfunction


