# vim-node-inspect
Interactive node debugger for (n)vim.

## Description
This plugin adds node debugging capabilities to vim with interactive CLI. Under the hood it wraps a modified version of node-inspect *(https://github.com/nodejs/node-inspect)*.


[![asciicast](https://asciinema.org/a/NOCL8Fc3LcQjVDD0CIR08I698.svg)](https://asciinema.org/a/NOCL8Fc3LcQjVDD0CIR08I698)

## Requirements
Vim**8.1+**/Recent Neovim.
Node in the path.

## Installation
Install with your favorite package manager. For vim-plug its
```
Plug 'eliba2/vim-node-inspect'
```

## How to use
Either start a node script or attach to an already running script. Both can be done manually (NodeIndpectStart/NodeInspectRun) or using the configuration file vim-node-config.json. The later is encouraged.

For full documentation see :h vim-node-inspect.

### Starting Manually ###

Either start debugging a local js file (via NodeInspectStart or NodeInspectRun) or connect to a running instance using NodeInspectConnect. In the later case the target must start with --inspect (e.g. node --inspect server.js). 

### Using the configuration file ###

Use the configuration file to define the starting method. Create a file named **"vim-node-config.json"** in the current working directory. The format is json, and the available options are:

**"request"** - either "launch" or "attach". The former is for executing a script. The second is for connecting to a running node instance.

**"program"** - in the case of "launch", this is the script's filename and must be present.

A sample configuration for launch would be:
```
{
	"request": "launch",
	"program": "/Users/eli/Tests/test.js",
	"args": ["first", "second"],
	"cwd": "/path/to/dir"
}
```

Use absolute paths. "${workspaceFolder}" can be used, it equals to the current working directory (:pwd).

**"args"** - an array list of script arguments. Relevant only to "launch", optional.

**"address"** - in the case of "attach", this is the address to connect to. Can be omitted, in this case it defaults to "127.0.0.1".

**"port"** - in the case of "attach", this is the port to connect to. Must be present.

**"cmd"** - working directory for running the script. Defaults to (n)vims current directory. Optional.

**"envFile"** - path to a file containing environment variables. Optional.

**"env"** - JSON object containing environment variables definition. Takes precedence over envFile. Optional.

A sample configuration for attach would be:

```
{
	"request": "attach",
	"port": 9229
}
```


### Automatically restarting the debug session ###

When using an application to monitor changes and restart the node session (such as nodemon or pm2) it is useful to restart the debug session as well. This can be done with the restart parameter, relevant only to an attach request:

```
{
	"request": "attach",
	"port": 9229,
	"restart": true
}
```


### Other possible configuration file locations

It is possible to have several config files in case the workspace has several projects who share the same root. In case the configuration file is not found in the current working directory, the curent buffer's directory is searched all the way to the top (as long it is a descendant of the working directory).



## Available Commands

The following commands are available:

**NodeInspectStart [args]** - Starts debugger, paused

**NodeInspectRun [args]** - Continue / Start and run immediatly

**NodeInspectConnect** host:port - Connect to a running instance

**NodeInspectStepOver** - Step over

**NodeInspectStepInto** - Step into

**NodeInspectStepOut** - Step out

**NodeInspectStop** - Stop debugging (and kill the node instance)

**NodeInspectToggleBreakpoint** - Toggle breakpoint

**NodeInspectRemoveAllBreakpoints** - Removes all breakpoints

**NodeInspectAddWatch** - Add the word under the cursor to the watch window

**NodeInspectToggleWindow** - Show/Hide the node inspect window


There are no default bindings; the following is added for convinience:
```
nnoremap <silent><F4> :NodeInspectStart<cr>
nnoremap <silent><F5> :NodeInspectRun<cr>
nnoremap <silent><F6> :NodeInspectConnect("127.0.0.1:9229")<cr>
nnoremap <silent><F7> :NodeInspectStepInto<cr>
nnoremap <silent><F8> :NodeInspectStepOver<cr>
nnoremap <silent><F9> :NodeInspectToggleBreakpoint<cr>
nnoremap <silent><F10> :NodeInspectStop<cr>
```

## Breakpoints

The plugin saves your breakpoint's locations between Vim sessions. Once the plugin is started it will try and re-activate the breakpoints for the current location, that's for all the breakpoints which root in the current working directory.

Note breakpoints are triggered through Vim and resolved in node, so resolved locations might differ from the triggered ones. 
The breakpoints signs appear in the resolved locations.


## Watches

There are two ways to add a watch. One is to use the *NodeInspectAddWatch* command which will add the word under the cursor as a watch. The other is by directly editing the watch window: this will resolve the watches, one per line.
Remove a watch by deleting it from the watch window.

### Auto watches

Auto watches will add the variables near the breakpoint location into the watch window (and remove them when of no use). It is done using syntactic analysis using Esprima (http://esprima.org/). It is currently experimental and requires setting the following which defaults to 0:

```
let g:nodeinspect_auto_watch = 1
```

## Connecting to a running container

You'll need to configure the local and remote directories when connecting to a remote host or the local instance will set the wrong breakpoints locations. Use the configuration file to set these directories, such as:

```
{
	"request": "attach",
	"port": 9229,
  	"localRoot": "/Users/eli/projects/my-test-project",
  	"remoteRoot": "/app"
}
```
Make sure to use full paths.


## Other Customizations

The debugger windows appear on the bottom by default. Change it by using

```
let g:nodeinspect_window_pos = 'right'|'left'|'bottom'
```


## Remarks
In beta. Means its useful; things may change or fail.

Tested on Linux (debian), OSX, Windows.


## Roadmap

* Debugging window
	* Detachable 
	* position change
* Watches
	* Auto watches
	* Open/Close properties
	* On the fly evaluation (popup)
* Breakpoints
	* Breakpoints window
* Call stack
	* Auto jump
* Windows Support


## Contributing

PR are welcome. Open a new issue in case you find a bug; you can also create a PR fixing it yourself of course.
Please follow the general code style (look@the code) and in your pull request explain the reason for the proposed change.


## License
MIT.

