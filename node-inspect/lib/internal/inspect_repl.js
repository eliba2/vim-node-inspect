/*
 * Copyright Node.js contributors. All rights reserved.
 *
 * Permission is hereby granted, free of charge, to any person obtaining a copy
 * of this software and associated documentation files (the "Software"), to
 * deal in the Software without restriction, including without limitation the
 * rights to use, copy, modify, merge, publish, distribute, sublicense, and/or
 * sell copies of the Software, and to permit persons to whom the Software is
 * furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included in
 * all copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
 * FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS
 * IN THE SOFTWARE.
 */
'use strict';
const FS = require('fs');
const Path = require('path');
const Repl = require('repl');
const util = require('util');
const vm = require('vm');
const fileURLToPath = require('url').fileURLToPath;

const debuglog = util.debuglog('inspect');

const SHORTCUTS = {
  cont: 'c',
  next: 'n',
  step: 's',
  out: 'o',
  backtrace: 'bt',
  setBreakpoint: 'sb',
  clearBreakpoint: 'cb',
  run: 'r',
};

const HELP = `
run, restart, r       Run the application or reconnect
kill                  Kill a running application or disconnect

cont, c               Resume execution
next, n               Continue to next line in current file
step, s               Step into, potentially entering a function
out, o                Step out, leaving the current function
backtrace, bt         Print the current backtrace
list                  Print the source around the current line where execution
                      is currently paused

setBreakpoint, sb     Set a breakpoint
clearBreakpoint, cb   Clear a breakpoint
breakpoints           List all known breakpoints
breakOnException      Pause execution whenever an exception is thrown
breakOnUncaught       Pause execution whenever an exception isn't caught
breakOnNone           Don't pause on exceptions (this is the default)

watch(expr)           Start watching the given expression
unwatch(expr)         Stop watching an expression
watchers              Print all watched expressions and their current values

exec(expr)            Evaluate the expression and print the value
repl                  Enter a debug repl that works like exec

scripts               List application scripts that are currently loaded
scripts(true)         List all scripts (including node-internals)

profile               Start CPU profiling session.
profileEnd            Stop current CPU profiling session.
profiles              Array of completed CPU profiling sessions.
profiles[n].save(filepath = 'node.cpuprofile')
                      Save CPU profiling session to disk as JSON.

takeHeapSnapshot(filepath = 'node.heapsnapshot')
                      Take a heap snapshot and save to disk as JSON.
`.trim();

const FUNCTION_NAME_PATTERN = /^(?:function\*? )?([^(\s]+)\(/;
function extractFunctionName(description) {
  const fnNameMatch = description.match(FUNCTION_NAME_PATTERN);
  return fnNameMatch ? `: ${fnNameMatch[1]}` : '';
}

const NATIVES = process.binding('natives');
function isNativeUrl(url) {
  return url.replace('.js', '') in NATIVES || url === 'bootstrap_node.js';
}

function getAbsolutePath(filenameOrURL) {
	var filename;

	if (filenameOrURL.startsWith('file://')) {

		filename = filenameOrURL;
		try {
			filename = fileURLToPath(filenameOrURL);
		} catch(e) {
			// fileURLToPath added in Node 10+
			filename = filenameOrURL[7] === '/' ? filenameOrURL.substring(8) : filenameOrURL.substring(7);
		}
	}
	else
		filename = filenameOrURL;

  return filename;
}


function getRelativePath(filenameOrURL) {
  const dir = Path.join(Path.resolve(), 'x').slice(0, -1);
	var filename = getAbsolutePath(filenameOrURL);

  // Change path to relative, if possible
	if (filename.indexOf(dir) === 0) {
		return filename.slice(dir.length);
	}
  return filename;
}


function toCallback(promise, callback) {
  function forward(...args) {
    process.nextTick(() => callback(...args));
  }
  promise.then(forward.bind(null, null), forward);
}

// Adds spaces and prefix to number
// maxN is a maximum number we should have space for
function leftPad(n, prefix, maxN) {
  const s = n.toString();
  const nchars = Math.max(2, String(maxN).length) + 1;
  const nspaces = nchars - s.length - 1;

  return prefix + ' '.repeat(nspaces) + s;
}

function markSourceColumn(sourceText, position, useColors) {
  if (!sourceText) return '';

  const head = sourceText.slice(0, position);
  let tail = sourceText.slice(position);

  // Colourize char if stdout supports colours
  if (useColors) {
    tail = tail.replace(/(.+?)([^\w]|$)/, '\u001b[32m$1\u001b[39m$2');
  }

  // Return source line with coloured char at `position`
  return [head, tail].join('');
}

function extractErrorMessage(stack) {
  if (!stack) return '<unknown>';
  const m = stack.match(/^\w+: ([^\n]+)/);
  return m ? m[1] : stack;
}

function convertResultToError(result) {
  const { className, description } = result;
  const err = new Error(extractErrorMessage(description));
  err.stack = description;
  Object.defineProperty(err, 'name', { value: className });
  return err;
}

class RemoteObject {
  constructor(attributes) {
    Object.assign(this, attributes);
    if (this.type === 'number') {
      this.value =
        this.unserializableValue ? +this.unserializableValue : +this.value;
    }
  }

  [util.inspect.custom](depth, opts) {
    function formatProperty(prop) {
      switch (prop.type) {
        case 'string':
        case 'undefined':
          return util.inspect(prop.value, opts);

        case 'number':
        case 'boolean':
          return opts.stylize(prop.value, prop.type);

        case 'object':
        case 'symbol':
          if (prop.subtype === 'date') {
            return util.inspect(new Date(prop.value), opts);
          }
          if (prop.subtype === 'array') {
            return opts.stylize(prop.value, 'special');
          }
          return opts.stylize(prop.value, prop.subtype || 'special');

        default:
          return prop.value;
      }
    }
    switch (this.type) {
      case 'boolean':
      case 'number':
      case 'string':
      case 'undefined':
        return util.inspect(this.value, opts);

      case 'symbol':
        return opts.stylize(this.description, 'special');

      case 'function': {
        const fnName = extractFunctionName(this.description);
        const formatted = `[${this.className}${fnName}]`;
        return opts.stylize(formatted, 'special');
      }

      case 'object':
        switch (this.subtype) {
          case 'date':
            return util.inspect(new Date(this.description), opts);

          case 'null':
            return util.inspect(null, opts);

          case 'regexp':
            return opts.stylize(this.description, 'regexp');

          default:
            break;
        }
        if (this.preview) {
          const props = this.preview.properties
            .map((prop, idx) => {
              const value = formatProperty(prop);
              if (prop.name === `${idx}`) return value;
              return `${prop.name}: ${value}`;
            });
          if (this.preview.overflow) {
            props.push('...');
          }
          const singleLine = props.join(', ');
          const propString =
            singleLine.length > 60 ? props.join(',\n  ') : singleLine;

          return this.subtype === 'array' ?
            `[ ${propString} ]` : `{ ${propString} }`;
        }
        return this.description;

      default:
        return this.description;
    }
  }

  static fromEvalResult({ result, wasThrown }) {
    if (wasThrown) return convertResultToError(result);
    return new RemoteObject(result);
  }
}

class ScopeSnapshot {
  constructor(scope, properties) {
    Object.assign(this, scope);
    this.properties = new Map(properties.map((prop) => {
      const value = new RemoteObject(prop.value);
      return [prop.name, value];
    }));
    this.completionGroup = properties.map((prop) => prop.name);
  }

  [util.inspect.custom](depth, opts) {
    const type = `${this.type[0].toUpperCase()}${this.type.slice(1)}`;
    const name = this.name ? `<${this.name}>` : '';
    const prefix = `${type}${name} `;
    return util.inspect(this.properties, opts)
      .replace(/^Map /, prefix);
  }
}

function copyOwnProperties(target, source) {
  Object.getOwnPropertyNames(source).forEach((prop) => {
    const descriptor = Object.getOwnPropertyDescriptor(source, prop);
    Object.defineProperty(target, prop, descriptor);
  });
}

function aliasProperties(target, mapping) {
  Object.keys(mapping).forEach((key) => {
    const descriptor = Object.getOwnPropertyDescriptor(target, key);
    Object.defineProperty(target, mapping[key], descriptor);
  });
}

function createRepl(inspector, nvim_bridge_p) {
  const { Debugger, HeapProfiler, Profiler, Runtime } = inspector;

  let repl; // eslint-disable-line prefer-const

  // Things we want to keep around
  const history = { control: [], debug: [] };
  const watchedExpressions = [];
  const knownBreakpoints = [];
  let pauseOnExceptionState = 'none';
  let lastCommand;

  // Things we need to reset when the app restarts
  let knownScripts;
  let currentBacktrace;
  let selectedFrame;
  let exitDebugRepl;
	var isRunning = false;

	let nvim_bridge = nvim_bridge_p;

  function resetOnStart() {
    knownScripts = {};
    currentBacktrace = null;
    selectedFrame = null;

    if (exitDebugRepl) exitDebugRepl();
    exitDebugRepl = null;
  }
  resetOnStart();

  const INSPECT_OPTIONS = { colors: inspector.stdout.isTTY };
  function inspect(value) {
    return util.inspect(value, INSPECT_OPTIONS);
  }

  function print(value, oneline = false) {
    const text = typeof value === 'string' ? value : inspect(value);
    return inspector.print(text, oneline);
  }

  function getCurrentLocation() {
    if (!selectedFrame) {
      throw new Error('Requires execution to be paused');
    }
    return selectedFrame.location;
  }

  function isCurrentScript(script) {
    return selectedFrame && getCurrentLocation().scriptId === script.scriptId;
  }

  function formatScripts(displayNatives = false) {
    function isVisible(script) {
      if (displayNatives) return true;
      return !script.isNative || isCurrentScript(script);
    }

    return Object.keys(knownScripts)
      .map((scriptId) => knownScripts[scriptId])
      .filter(isVisible)
      .map((script) => {
        const isCurrent = isCurrentScript(script);
        const { isNative, url } = script;
        const name = `${getRelativePath(url)}${isNative ? ' <native>' : ''}`;
        return `${isCurrent ? '*' : ' '} ${script.scriptId}: ${name}`;
      })
      .join('\n');
  }
  function listScripts(displayNatives = false) {
    print(formatScripts(displayNatives));
  }
  listScripts[util.inspect.custom] = function listWithoutInternal() {
    return formatScripts();
  };

	/* for vim api, get mapping of current scripts */
  function vimGetScripts() {
    function isVisible(script) {
      return !script.isNative || isCurrentScript(script);
    }
		let scripts = {};
    Object.keys(knownScripts)
			.map((scriptId) => knownScripts[scriptId])
			.filter(isVisible)
			.map((script) => {
				const { url } = script;
				scripts[url] = true;
			});
		return scripts;
  }

  const profiles = [];
  class Profile {
    constructor(data) {
      this.data = data;
    }

    static createAndRegister({ profile }) {
      const p = new Profile(profile);
      profiles.push(p);
      return p;
    }

    [util.inspect.custom](depth, { stylize }) {
      const { startTime, endTime } = this.data;
      return stylize(`[Profile ${endTime - startTime}μs]`, 'special');
    }

    save(filename = 'node.cpuprofile') {
      const absoluteFile = Path.resolve(filename);
      const json = JSON.stringify(this.data);
      FS.writeFileSync(absoluteFile, json);
      print('Saved profile to ' + absoluteFile);
    }
  }

  class SourceSnippet {
    constructor(location, delta, scriptSource) {
      Object.assign(this, location);
      this.scriptSource = scriptSource;
      this.delta = delta;
    }

    [util.inspect.custom](depth, options) {
      const { scriptId, lineNumber, columnNumber, delta, scriptSource } = this;
      const start = Math.max(1, lineNumber - delta + 1);
      const end = lineNumber + delta + 1;

      const lines = scriptSource.split('\n');
      return lines.slice(start - 1, end).map((lineText, offset) => {
        const i = start + offset;
        const isCurrent = i === (lineNumber + 1);

        const markedLine = isCurrent
          ? markSourceColumn(lineText, columnNumber, options.colors)
          : lineText;

        let isBreakpoint = false;
        knownBreakpoints.forEach(({ location }) => {
          if (!location) return;
          if (scriptId === location.scriptId &&
              i === (location.lineNumber + 1)) {
            isBreakpoint = true;
          }
        });

        let prefixChar = ' ';
        if (isCurrent) {
          prefixChar = '>';
        } else if (isBreakpoint) {
          prefixChar = '*';
        }
        return `${leftPad(i, prefixChar, end)} ${markedLine}`;
      }).join('\n');
    }
  }

  function getSourceSnippet(location, delta = 5) {
    const { scriptId } = location;
    return Debugger.getScriptSource({ scriptId })
      .then(({ scriptSource }) =>
        new SourceSnippet(location, delta, scriptSource));
  }

  class CallFrame {
    constructor(callFrame) {
      Object.assign(this, callFrame);
    }

    loadScopes() {
      return Promise.all(
        this.scopeChain
          .filter((scope) => scope.type !== 'global')
          .map((scope) => {
            const { objectId } = scope.object;
            return Runtime.getProperties({
              objectId,
              generatePreview: true,
            }).then(({ result }) => new ScopeSnapshot(scope, result));
          })
      );
    }

    list(delta = 5) {
      return getSourceSnippet(this.location, delta);
    }
  }

  class Backtrace extends Array {
    [util.inspect.custom]() {
      return this.map((callFrame, idx) => {
        const {
          location: { scriptId, lineNumber, columnNumber },
          functionName
        } = callFrame;
        const name = functionName || '(anonymous)';

        const script = knownScripts[scriptId];
        const relativeUrl =
          (script && getRelativePath(script.url)) || '<unknown>';
        const frameLocation =
          `${relativeUrl}:${lineNumber + 1}:${columnNumber}`;

        return `#${idx} ${name} ${frameLocation}`;
      }).join('\n');
    }

		// for vim-node-inspect
		static getList(callFrames) {
      return callFrames.map((callFrame, idx) => {
        const {
          location: { scriptId, lineNumber, columnNumber },
          functionName
        } = callFrame;
        const name = functionName || '(anonymous)';

        const script = knownScripts[scriptId];
        const relativeUrl =
          (script && getRelativePath(script.url)) || '<unknown>';
        const frameLocation =
          `${relativeUrl}:${lineNumber + 1}`;
        return {name, frameLocation};
			}).reverse();
		}

    static from(callFrames) {
      return super.from(Array.from(callFrames).map((callFrame) => {
        if (callFrame instanceof CallFrame) {
          return callFrame;
        }
        return new CallFrame(callFrame);
      }));
    }
  }

  function prepareControlCode(input) {
    if (input === '\n') return lastCommand;
    // exec process.title => exec("process.title");
    const match = input.match(/^\s*exec\s+([^\n]*)/);
    if (match) {
      lastCommand = `exec(${JSON.stringify(match[1])})`;
    } else {
      lastCommand = input;
    }
    return lastCommand;
  }

  function evalInCurrentContext(code) {
    // Repl asked for scope variables
    if (code === '.scope') {
      if (!selectedFrame) {
        return Promise.reject(new Error('Requires execution to be paused'));
      }
      return selectedFrame.loadScopes().then((scopes) => {
        return scopes.map((scope) => scope.completionGroup);
      });
    }

    if (selectedFrame) {
      return Debugger.evaluateOnCallFrame({
        callFrameId: selectedFrame.callFrameId,
        expression: code,
        objectGroup: 'node-inspect',
        generatePreview: true,
      }).then(RemoteObject.fromEvalResult);
    }
    return Runtime.evaluate({
      expression: code,
      objectGroup: 'node-inspect',
      generatePreview: true,
    }).then(RemoteObject.fromEvalResult);
  }

  function controlEval(input, context, filename, callback) {
    debuglog('eval:', input);
    function returnToCallback(error, result) {
      debuglog('end-eval:', input, error);
      callback(error, result);
    }

    try {
      const code = prepareControlCode(input);
      const result = vm.runInContext(code, context, filename);

      if (result && typeof result.then === 'function') {
        toCallback(result, returnToCallback);
        return;
      }
      returnToCallback(null, result);
    } catch (e) {
      returnToCallback(e);
    }
  }

  function debugEval(input, context, filename, callback) {
    debuglog('eval:', input);
    function returnToCallback(error, result) {
      debuglog('end-eval:', input, error);
      callback(error, result);
    }

    try {
      const result = evalInCurrentContext(input);

      if (result && typeof result.then === 'function') {
        toCallback(result, returnToCallback);
        return;
      }
      returnToCallback(null, result);
    } catch (e) {
      returnToCallback(e);
    }
  }

  function formatWatchers(verbose = false) {
    if (!watchedExpressions.length) {
      return Promise.resolve('');
    }

    const inspectValue = (expr) =>
      evalInCurrentContext(expr)
        // .then(formatValue)
        .catch((error) => `<${error.message}>`);
    const lastIndex = watchedExpressions.length - 1;

    return Promise.all(watchedExpressions.map(inspectValue))
      .then((values) => {
        const lines = watchedExpressions
          .map((expr, idx) => {
            const prefix = `${leftPad(idx, ' ', lastIndex)}: ${expr} =`;
            const value = inspect(values[idx], { colors: true });
            if (value.indexOf('\n') === -1) {
              return `${prefix} ${value}`;
            }
            return `${prefix}\n    ${value.split('\n').join('\n    ')}`;
          });
        return lines.join('\n');
      })
      .then((valueList) => {
        return verbose ? `Watchers:\n${valueList}\n` : valueList;
      });
  }

  function watchers(verbose = false) {
    return formatWatchers(verbose).then(print);
  }

  // List source code
  function list(delta = 5) {
    return selectedFrame.list(delta)
      .then(null, (error) => {
        print('You can\'t list source code right now');
        throw error;
      });
  }

  function handleBreakpointResolved({ breakpointId, location }) {
    const script = knownScripts[location.scriptId];
    const scriptUrl = script && script.url;
    if (scriptUrl) {
      Object.assign(location, { scriptUrl });
    }
    const isExisting = knownBreakpoints.some((bp) => {
      if (bp.breakpointId === breakpointId) {
        Object.assign(bp, { location });
        return true;
      }
      return false;
    });
    if (!isExisting) {
      knownBreakpoints.push({ breakpointId, location });
    }
		// notify vim the breakpoint was resolved
		let resolveFile = location.scriptUrl;
		if (location.scriptUrl.indexOf("file://") == 0) {
			resolveFile = location.scriptUrl.slice(7);
		}
		// container might use pattern of .*<file>$
		if (location.scriptUrl.startsWith(".*//")) {
			resolveFile = resolveFile.slice(3);
		}
		else // that's for double check
			if (location.scriptUrl.startsWith(".*")) {
				resolveFile = resolveFile.slice(2);
			}
		if (location.scriptUrl.endsWith("$")) {
			resolveFile = resolveFile.slice(0,-1);
		}
		let m = { m: 'nd_brk_resolved', file: resolveFile, line: location.lineNumber + 1 };
		nvim_bridge.send(m);
  }

	function startCliRepl() {
		// Don't display any default messages
		const listeners = repl.listeners('SIGINT').slice(0);
		repl.removeAllListeners('SIGINT');

		const oldContext = repl.context;

		exitDebugRepl = () => {
			// Restore all listeners
			process.nextTick(() => {
				listeners.forEach((listener) => {
					repl.on('SIGINT', listener);
				});
			});

			// Exit debug repl
			repl.eval = controlEval;

			// Swap history
			history.debug = repl.history;
			repl.history = history.control;

			repl.context = oldContext;
			repl.setPrompt('debug> ');
			repl.displayPrompt();

			repl.removeListener('SIGINT', exitDebugRepl);
			repl.removeListener('exit', exitDebugRepl);

			exitDebugRepl = null;
		};

		// Exit debug repl on SIGINT
		repl.on('SIGINT', exitDebugRepl);

		// Exit debug repl on repl exit
		repl.on('exit', exitDebugRepl);

		// Set new
		repl.eval = debugEval;
		repl.context = {};

		// Swap history
		history.control = repl.history;
		repl.history = history.debug;

		repl.setPrompt('> ');

		print('Press Ctrl + C to leave debug repl');
		repl.displayPrompt();
	}

  function listBreakpoints() {
    if (!knownBreakpoints.length) {
      print('No breakpoints yet');
      return;
    }

    function formatLocation(location) {
      if (!location) return '<unknown location>';
      const script = knownScripts[location.scriptId];
      const scriptUrl = script ? script.url : location.scriptUrl;
      return `${getRelativePath(scriptUrl)}:${location.lineNumber + 1}`;
    }
    const breaklist = knownBreakpoints
      .map((bp, idx) => `#${idx} ${formatLocation(bp.location)}`)
      .join('\n');
    print(breaklist);
  }

  async function setBreakpoint(script, line, condition, silent) {
    function registerBreakpoint({ breakpointId, actualLocation }) {
      handleBreakpointResolved({ breakpointId, location: actualLocation });
      if (actualLocation && actualLocation.scriptId) {
        if (!silent) return '';// getSourceSnippet(actualLocation, 5);
      } else {
				// skip for vim
				//print(`Warning: script '${script}' was not loaded yet.`);
      }
      return undefined;
    }

    // setBreakpoint(): set breakpoint at current location
    if (script === undefined) {
      return Debugger
        .setBreakpoint({ location: getCurrentLocation(), condition })
        .then(registerBreakpoint)
				.catch(e => {
					// failed (already exists?)
					let m = { m: 'nd_brk_failed', file: script, line: getCurrentLocation().lineNumber };
					nvim_bridge.send(m);
				});
    }

    // setBreakpoint(line): set breakpoint in current script at specific line
    if (line === undefined && typeof script === 'number') {
      const location = {
        scriptId: getCurrentLocation().scriptId,
        lineNumber: script - 1,
      };
      return Debugger.setBreakpoint({ location, condition })
        .then(registerBreakpoint)
				.catch(e => {
					// failed (already exists?) remove it
					let m = { m: 'nd_brk_failed', file: script, line: line };
					nvim_bridge.send(m);
				});
    }

    if (typeof script !== 'string') {
      throw new TypeError(`setBreakpoint() expects a string, got ${script}`);
    }

    // setBreakpoint('fn()'): Break when a function is called
    if (script.endsWith('()')) {
      const debugExpr = `debug(${script.slice(0, -2)})`;
      const debugCall = selectedFrame
        ? Debugger.evaluateOnCallFrame({
          callFrameId: selectedFrame.callFrameId,
          expression: debugExpr,
          includeCommandLineAPI: true,
        })
        : Runtime.evaluate({
          expression: debugExpr,
          includeCommandLineAPI: true,
        });
      return debugCall.then(({ result, wasThrown }) => {
        if (wasThrown) return convertResultToError(result);
        return undefined; // This breakpoint can't be removed the same way
      });
    }

    // setBreakpoint('scriptname')
    let scriptId = null;
    let ambiguous = false;
    if (knownScripts[script]) {
      scriptId = script;
    } else {
      for (const id of Object.keys(knownScripts)) {
        const scriptUrl = knownScripts[id].url;
        if (scriptUrl && scriptUrl.indexOf(script) !== -1) {
          if (scriptId !== null) {
            ambiguous = true;
          }
          scriptId = id;
        }
      }
    }

    if (ambiguous) {
      print('Script name is ambiguous');
      return undefined;
    }
    if (line <= 0) {
      print('Line should be a positive value');
      return undefined;
    }

    if (scriptId !== null) {
      const location = { scriptId, lineNumber: line - 1 };

      return Debugger.setBreakpoint({ location, condition })
        .then(registerBreakpoint)
				.catch(e => {
					// failed (already exists?)
					let m = { m: 'nd_brk_failed', file: script, line: line };
					nvim_bridge.send(m);
				});
    }

    const escapedPath = script.replace(/([/\\.?*()^${}|[\]])/g, '\\$1');
    const urlRegex = `^(.*[\\/\\\\])?${escapedPath}$`;

    return Debugger
      .setBreakpointByUrl({ urlRegex, lineNumber: line - 1, condition })
      .then((bp) => {
        // TODO: handle bp.locations in case the regex matches existing files
        if (!bp.location) { // Fake it for now.
          Object.assign(bp, {
            actualLocation: {
              scriptUrl: `.*/${script}$`,
              lineNumber: line - 1,
            },
          });
        }
        return registerBreakpoint(bp);
      })
			.catch(e => {
				// failed (already exists?) remove it
				let m = { m: 'nd_brk_failed', file: script, line: line };
				nvim_bridge.send(m);
			});
  }

  function clearBreakpoint(url, line) {
    const breakpoint = knownBreakpoints.find(({ location }) => {
      if (!location) return false;
      const script = knownScripts[location.scriptId];
      if (!script) return false;
      return (
        script.url.indexOf(url) !== -1 && (location.lineNumber + 1) === line
      );
    });
    if (!breakpoint) {
      print(`Could not find breakpoint at ${url}:${line}`);
      return Promise.resolve();
    }
    return Debugger.removeBreakpoint({ breakpointId: breakpoint.breakpointId })
      .then(() => {
        const idx = knownBreakpoints.indexOf(breakpoint);
        knownBreakpoints.splice(idx, 1);
      });
  }

  function restoreBreakpoints() {
    const lastBreakpoints = knownBreakpoints.slice();
    knownBreakpoints.length = 0;
    const newBreakpoints = lastBreakpoints
      .filter(({ location }) => !!location.scriptUrl)
      .map(({ location }) =>
        setBreakpoint(location.scriptUrl, location.lineNumber + 1));
    if (!newBreakpoints.length) return Promise.resolve();
    return Promise.all(newBreakpoints).then((results) => {
      print(`${results.length} breakpoints restored.`);
    });
  }

  function setPauseOnExceptions(state) {
    return Debugger.setPauseOnExceptions({ state })
      .then(() => {
        pauseOnExceptionState = state;
      });
  }

	// gets a method arguments, if exists. called on break
	function getArguments() {
		//console.log(evalInCurrentContext(f);
	}

  Debugger.on('paused', ({ callFrames, reason /* , hitBreakpoints */ }) => {
		isRunning = false;
    // Save execution context's data
    currentBacktrace = Backtrace.from(callFrames);
    selectedFrame = currentBacktrace[0];
    const { scriptId, lineNumber } = selectedFrame.location;

    const breakType = reason === 'other' ? 'break' : reason;
    const script = knownScripts[scriptId];
		const scriptUrl = script ? getAbsolutePath(script.url) : '[unknown]';

    const header = `${breakType} in ${scriptUrl}:${lineNumber + 1}`;
		/* notify nvim */
		//getArguments(); // call get arguments and set the parameters to the stop function to display in the watch window
		let scriptPrefix = ''; 
		if (scriptUrl && scriptUrl.length && scriptUrl[0] != '/' && scriptUrl[0] != '[') {
			scriptPrefix = '/';
		}
		let m = { m: 'nd_stopped', file: `${scriptPrefix}${scriptUrl}`, line: lineNumber + 1, backtrace: Backtrace.getList(callFrames)};
		nvim_bridge.send(m);

    inspector.suspendReplWhile(() =>
      Promise.all([formatWatchers(true)]) // selectedFrame.list(2)]  don't display lines 
        .then(([watcherList, context]) => {
          if (watcherList) {
            //return `${watcherList}\n${inspect(context)}`;
            return `${watcherList}\n`;
          }
          return inspect(context);
        }).then((breakContext) => {
          //print(`${header}\n${breakContext}`);
          print(`${header}\n`);
        }));
  });

  function handleResumed() {
		isRunning = true;
    currentBacktrace = null;
    selectedFrame = null;
  }

	function resolveWatches(watches) {
    if (Object.keys(watches).length == 0) {
			return {};
    }
    const inspectValue = async (expr) => {
			try {
				let val = await evalInCurrentContext(expr);
				if (val && val.subtype == 'error')
					return "n\\a";
				if (typeof val == 'object' && val.preview && val.preview.properties) {
					let propertiesVal = '';
					val.preview.properties.map(s => propertiesVal += `${s.name}: ${s.value} `);
					return propertiesVal;
				}
				else
					return val.value || "n\\a";
			} catch (e) {
        return "n\\a";
			}
		}
    const lastIndex = watchedExpressions.length - 1;
		let output = {};
    return Promise.all(Object.keys(watches).map(inspectValue))
      .then((values) => {
        const lines = Object.keys(watches)
          .map((expr, idx) => {
						output[expr] = values[idx];
          });
      })
      .then((valueList) => {
        return output;
      });
	}

  Debugger.on('resumed', handleResumed);

  Debugger.on('breakpointResolved', handleBreakpointResolved);

  Debugger.on('scriptParsed', (script) => {
    const { scriptId, url } = script;
    if (url) {
      knownScripts[scriptId] = Object.assign({
        isNative: isNativeUrl(url),
      }, script);
    }
  });

  Profiler.on('consoleProfileFinished', ({ profile }) => {
    Profile.createAndRegister({ profile });
    print([
      'Captured new CPU profile.',
      `Access it with profiles[${profiles.length - 1}]`
    ].join('\n'));
  });

  function initializeContext(context) {
    inspector.domainNames.forEach((domain) => {
      Object.defineProperty(context, domain, {
        value: inspector[domain],
        enumerable: true,
        configurable: true,
        writeable: false,
      });
    });

    copyOwnProperties(context, {
      get help() {
        print(HELP);
      },

      get run() {
				let m = { m: 'nd_repl_cont' };
				nvim_bridge.send(m);
				return
        //return inspector.run();
      },

      get kill() {
				let m = { m: 'nd_repl_kill' };
				nvim_bridge.send(m);
				return;
        //return inspector.killChild();
      },

      get restart() {
				let m = { m: 'nd_repl_cont' };
				nvim_bridge.send(m);
				return
        //return inspector.run();
      },

      get cont() {
				let m = { m: 'nd_repl_cont' };
				nvim_bridge.send(m);
				return;
        //handleResumed();
        //return Debugger.resume();
      },

      get next() {
				let m = { m: 'nd_repl_stepover' };
				nvim_bridge.send(m);
				return;
        //handleResumed();
        //return Debugger.stepOver();
      },

      get step() {
				let m = { m: 'nd_repl_stepinto' };
				nvim_bridge.send(m);
				return;
        //handleResumed();
        //return Debugger.stepInto();
      },

      get out() {
				let m = { m: 'nd_repl_stepout' };
				nvim_bridge.send(m);
				return;
        //handleResumed();
        //return Debugger.stepOut();
      },

      get pause() {
        return Debugger.pause();
      },

      get backtrace() {
        return currentBacktrace;
      },

      get breakpoints() {
        return listBreakpoints();
      },

      exec(expr) {
        return evalInCurrentContext(expr);
      },

      get profile() {
        return Profiler.start();
      },

      get profileEnd() {
        return Profiler.stop()
          .then(Profile.createAndRegister);
      },

      get profiles() {
        return profiles;
      },

      takeHeapSnapshot(filename = 'node.heapsnapshot') {
        return new Promise((resolve, reject) => {
          const absoluteFile = Path.resolve(filename);
          const writer = FS.createWriteStream(absoluteFile);
          let sizeWritten = 0;
          function onProgress({ done, total, finished }) {
            if (finished) {
              print('Heap snaphost prepared.');
            } else {
              print(`Heap snapshot: ${done}/${total}`, true);
            }
          }
          function onChunk({ chunk }) {
            sizeWritten += chunk.length;
            writer.write(chunk);
            print(`Writing snapshot: ${sizeWritten}`, true);
          }
          function onResolve() {
            writer.end(() => {
              teardown();
              print(`Wrote snapshot: ${absoluteFile}`);
              resolve();
            });
          }
          function onReject(error) {
            teardown();
            reject(error);
          }
          function teardown() {
            HeapProfiler.removeListener(
              'reportHeapSnapshotProgress', onProgress);
            HeapProfiler.removeListener('addHeapSnapshotChunk', onChunk);
          }

          HeapProfiler.on('reportHeapSnapshotProgress', onProgress);
          HeapProfiler.on('addHeapSnapshotChunk', onChunk);

          print('Heap snapshot: 0/0', true);
          HeapProfiler.takeHeapSnapshot({ reportProgress: true })
            .then(onResolve, onReject);
        });
      },

      get watchers() {
        return watchers();
      },

      watch(expr) {
        watchedExpressions.push(expr);
      },

      unwatch(expr) {
        const index = watchedExpressions.indexOf(expr);

        // Unwatch by expression
        // or
        // Unwatch by watcher number
        watchedExpressions.splice(index !== -1 ? index : +expr, 1);
      },

      get repl() {
				startCliRepl()
      },

      get version() {
        return Runtime.evaluate({
          expression: 'process.versions.v8',
          contextId: 1,
          returnByValue: true,
        }).then(({ result }) => {
          print(result.value);
        });
      },

      scripts: listScripts,

      setBreakpoint,
      clearBreakpoint,
      setPauseOnExceptions,
      get breakOnException() {
        return setPauseOnExceptions('all');
      },
      get breakOnUncaught() {
        return setPauseOnExceptions('uncaught');
      },
      get breakOnNone() {
        return setPauseOnExceptions('none');
      },

			list,
    });
    aliasProperties(context, SHORTCUTS);
  }

  function initAfterStart() {
    const setupTasks = [
      Runtime.enable(),
      Profiler.enable(),
      Profiler.setSamplingInterval({ interval: 100 }),
      Debugger.enable(),
      Debugger.setPauseOnExceptions({ state: 'none' }),
      Debugger.setAsyncCallStackDepth({ maxDepth: 0 }),
      Debugger.setBlackboxPatterns({ patterns: [] }),
      Debugger.setPauseOnExceptions({ state: pauseOnExceptionState }),
      //restoreBreakpoints(), // disabled for vim
      Runtime.runIfWaitingForDebugger(),
    ];
    return Promise.all(setupTasks);
  }

	async function handleVimEvents(message) {

		switch (message.m) {
			case 'nd_next':
				if (isRunning) {
					print(`Only available when paused(1)`);
					return;
				}
				handleResumed();
				Debugger.stepOver();
				break;
			case 'nd_into':
				if (isRunning) {
					print(`Only available when paused(2)`);
					return;
				}
				handleResumed();
				Debugger.stepInto();
				break;
			case 'nd_out':
				if (isRunning) {
					print(`Only available when paused(3)`);
					return;
				}
				handleResumed();
				Debugger.stepOut();
				break;
			case 'nd_pause':
				if (!isRunning) {
					print(`Only available when running(4)`);
					return;
				}
        Debugger.pause();
				break;
			case 'nd_kill':
				inspector.killChild();
				process.exit(0)
				break;
			case 'nd_continue':
				if (isRunning) {
					print(`Only available when paused(5)`);
					return;
				}
				handleResumed();
				Debugger.resume();
				break;
			case 'nd_restart':
				// make an js array out of args, argv-argc style
				inspector.rerun(message.script, message.args);
				break;
			case 'nd_print':
				print(message.txt);
				break;
			case 'nd_addbrkpt':
				await setBreakpoint(message.file, message.line);	
				break;
			case 'nd_removebrkpt':
				await clearBreakpoint(message.file, message.line);	
				break;
			case 'nd_removeallbrkpts':
				Object.keys(message.breakpoints).map(file => { 
					Object.keys(message.breakpoints[file]).map(line => clearBreakpoint(file, Number(line)) );
				});
				break;
			case 'nd_setbreakpoints':
				Object.keys(message.breakpoints).map(file => { 
					Object.keys(message.breakpoints[file]).map(async (line) => await setBreakpoint(file, Number(line)) );
				});
				break;
			case 'nd_removebreakpoints':
				Object.keys(message.breakpoints).map(file => { 
					Object.keys(message.breakpoints[file]).map(async (line) => await removeBreakpoint(file, Number(line)) );
				});
				break;
			case 'nd_verifyrestart':
				if (vimGetScripts()[message.file]) {
					let m = { m: 'nd_restartrequired' };
					nvim_bridge.send(m);
				}
				break;
			case 'nd_updatewatches':
				let watches = await resolveWatches(message.watches);
				let m = { 
					m: 'nd_watchesresolved',
					watches,
				};
				nvim_bridge.send(m);
				break;
			default:
				console.error("unknown message from vim",JSON.stringify(message));
		}

	}
	// vim events
	nvim_bridge.setEventCallback(handleVimEvents);

  return function startRepl() {
    inspector.client.on('close', () => {
      resetOnStart();
    });
    inspector.client.on('ready', () => {
      initAfterStart();
    });

    const replOptions = {
      prompt: '>> ',
      input: inspector.stdin,
      output: inspector.stdout,
      eval: controlEval,
      useGlobal: false,
      ignoreUndefined: true,
    };

    repl = Repl.start(replOptions); // eslint-disable-line prefer-const
    initializeContext(repl.context);
    repl.on('reset', initializeContext);

    repl.defineCommand('interrupt', () => {
      // We want this for testing purposes where sending CTRL-C can be tricky.
      repl.emit('SIGINT');
    });

		// Init once for the initial connection
		initAfterStart();

    return repl;
  };
}
module.exports = createRepl;
