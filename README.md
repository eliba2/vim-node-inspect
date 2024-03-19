# vim-node-inspect
Interactive node debugger for (n)vim.

## Description
Node debugging capabilities for (n)vim using the devtools protocol.


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

Use the plugin to start a script with *NodeInspectStart*/*NodeInspectRun* or attach to an already running script using *NodeInspectConnect*. Additional configuration can be set with the vim-node-config.json configuration file.

For full documentation see `:h vim-node-inspect`.

### W/O A configuration file ###

Use NodeInspectStart or NodeInspectRun which starts the script in the current buffer using `node --inspect <script>`. An already running script can be attached using NodeInspectConnect address:port. In the later case the target must start with --inspect (e.g. `node --inspect server.js`). 

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

**"cwd"** - working directory for running the script. Defaults to (n)vims current directory. Optional.

**"envFile"** - path to a file containing environment variables. Optional.

**"env"** - JSON object containing environment variables definition. Takes precedence over envFile. Optional.

A sample configuration for attach would be:

```
{
	"request": "attach",
	"port": 9229
}
```


### Exiting ###

**NodeInspectStop** will stop debugging and close the debugging windows. It will kill the node session in the case it was launched. Exiting (n)vim will also kill the node session if such was launched.

Pressing Crtl+D or CTRL+C twice in the command window has a similar effect. 



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


### Multiple configurations

Multiple configurations can be defined by setting a **"configurations"** object which lists the possible configurations, each having a **"name"** key which uniquly identifies it. **"NodeInspectStart"** or **"NodeInspectRun"** must be used followed by at least one parameter which is the configuration name. Other starting parameters might follow.


A sample configuration would be:
```
{
	"configurations": [
		{
			"name": "connect",
			"request": "attach",
			"port": 9229
		},
		{
			"name": "run",
			"request": "launch",
			"program": "${workspaceFolder}/server.js"
		}
	]
}

```

Usage in this case would be either *NodeInspectStart "run"* or *NodeInspectStart "connect"* .


## Available Commands

**NodeInspectStart [config name] [args]** - Starts debugger, paused

**NodeInspectRun [config name] [args]** - Continue / Start and run immediatly

**NodeInspectConnect host:port** - Connect to a running instance

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
nnoremap <silent><leader>dd :NodeInspectStart<cr>
nnoremap <silent><leader>dr :NodeInspectRun<cr>
nnoremap <silent><leader>dc :NodeInspectConnect("127.0.0.1:9229")<cr>
nnoremap <silent><leader>ds :NodeInspectStepOver<cr>
nnoremap <silent><leader>di :NodeInspectStepInto<cr>
nnoremap <silent><leader>do :NodeInspectStepOut<cr>
nnoremap <silent><leader>dq :NodeInspectStop<cr>
nnoremap <silent><leader>db :NodeInspectToggleBreakpoint<cr>
nnoremap <silent><leader>da :NodeInspectRemoveAllBreakpoints<cr>
nnoremap <silent><leader>dw :NodeInspectToggleWindow<cr>
```

## Breakpoints

The plugin saves your breakpoint's locations between Vim sessions. Once the plugin is started it will try and re-activate the breakpoints for the current location, that's for all the breakpoints which root in the current working directory.

Note breakpoints are triggered through Vim and resolved in node, so resolved locations might differ from the triggered ones. 
The breakpoints signs appear in the resolved locations.


## Watches

There are two ways to add a watch. One is to use the *NodeInspectAddWatch* command which will add the word under the cursor as a watch. The other is by directly editing the watch window: this will resolve the watches, one per line.
Remove a watch by deleting it from the watch window.

### Auto watches

The variables in the current scope will be automatically displayed in the watches window prefixed by an 'A'. This behavior can be disabled by setting g:nodeinspect_auto_watch to 0 (1 is default).


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
	* ~~position change~~
* Watches
	* ~~Auto watches~~
	* ~~Open/Close properties~~
	* On the fly evaluation (popup)
* Breakpoints
	* Breakpoints window
* Call stack
	* Auto jump
* ~~Windows Support~~


## Contributing

PRs welcome. Open a new issue in case you find a bug; you can also create a PR fixing it yourself of course.
Please follow the general code style (look@the code) and in your pull request explain the reason for the proposed change.


## License
MIT.

