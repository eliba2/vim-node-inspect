# vim-node-inspect
A wrapper over node-inspect.

## Description
Wraps node-inspect (https://github.com/nodejs/node-inspect). An interactive node debugger in (n)vim.


[![asciicast](https://asciinema.org/a/292793.svg)](https://asciinema.org/a/292793)

## Requirements
Vim8.1/Neovim.

## Installation
Install with your favorite package manager. For vim-plug its

Plug 'eliba2/vim-node-inspect'

## How to use
Either start debugging a local js file (via NodeInspectStart or NodeInspectRun) or connect to a running instance using NodeInspectConnect. In the later case the target must start with --inspect (e.g. node --inspect server.js).
To run arbitrary js code in the debugger use "exec".


The following commands are available. No default bindings.

NodeInspectStart - Starts node inspect, paused

NodeInspectRun - Continue / Start and run immediatly

NodeInspectConnect host:port - Connect to a running instance

NodeInspectStepOver - Step over

NodeInspectStepInto - Step into

NodeInspectStepOut - Step out

NodeInspectContinue - Continue running

NodeInspectStop - Stop debugging (and kill the node instance)

NodeInspectToggleBreakpoint - Toggle breakpoint

NodeInspectRemoveAllBreakpoints - Removes all breakpoints

## Remarks
In beta. Means its useful; things may change or fail.
NOT tested on Windows.

## License
Whatever node-inspect is.

