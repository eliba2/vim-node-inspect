
let nodeinspect#watches#inspect_win = -1
let s:watches = {}



function! nodeinspect#watches#Draw()
endif


" add a watch, input by vim's input
function! nodeinspect#watches#AddWatch()
	call inputsave()
  let watch = input('Enter name: ')
  call inputrestore()
	if len(watch) > 0
		if has_key(watch, s:watches) == 0
			let s:watches[watch] = 1
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
		if has_key(watch, s:watches) == 1
		else
			echom "watch does not exist"
		endif
	endif
endfunction


