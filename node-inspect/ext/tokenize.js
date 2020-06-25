const fs = require('fs');
const esprima = require('../esprima/esprima');
 
//var ast = esprima.parseScript(contents,{ tokens: true, loc: true});

var varsFound = [];

//console.log(JSON.stringify(ast, null, 2));

let reserved = {
	'abstract': true,
	'arguments': true,
	'async': true,
	'await': true,
	'boolean': true,
	'break': true,
	'byte': true,
	'case': true,
	'catch': true,
	'char': true,
	'class': true,
	'const': true,
	'continue': true,
	'debugger': true,
	'default': true,
	'delete': true,
	'do': true,
	'double': true,
	'else': true,
	'enum': true,
	'eval': true,
	'export*': true,
	'extends*': true,
	'false': true,
	'final': true,
	'finally': true,
	'float': true,
	'for': true,
	'function': true,
	'goto': true,
	'if': true,
	'implements': true,
	'import': true,
	'in': true,
	'instanceof': true,
	'int': true,
	'interface': true,
	'let': true,
	'long': true,
	'native': true,
	'new': true,
	'null': true,
	'package': true,
	'private': true,
	'protected': true,
	'public': true,
	'return': true,
	'require': true,
	'short': true,
	'static': true,
	'super': true,
	'switch': true,
	'synchronized': true,
	'this': true,
	'throw': true,
	'throws': true,
	'transient': true,
	'true': true,
	'try': true,
	'typeof': true,
	'var': true,
	'void': true,
	'volatile': true,
	'while': true,
	'with': true,
	'yield': true };


const getArgs = (file, pos, rad) => {

	try {
		const contents = fs.readFileSync(file, 'utf8');
		var ast = esprima.tokenize(contents,{ loc: true});
		let out = {};
		let x = 0;
		while (x < ast.length) {
			if (ast[x].type == 'Identifier') {
				
				// verify we're in location
				if (ast[x].loc.start.line >= pos - rad && ast[x].loc.start.line <= pos + rad) {

					// add and continue to read, greedy
					let value = ast[x].value;
					let initialValue = value;
					let endLocation = ast[x].loc.end;
					let y = x + 1;
					let skip = false;
					while (y < ast.length &&  ast[y].loc.start.line == ast[x].loc.end.line && ast[y].loc.start.column == ast[x].loc.end.column) {
							if (ast[y].value == '=' || ast[y].value == "++") {
								// if not already skipped, try and add it till this part, and skip the rest
								if (!skip && reserved[initialValue] !== true) {
									let outLine = endLocation.line + '';
									if (out[outLine] == undefined)
										out[outLine] = {};
										//out[outLine] = [];
									//out[outLine].push(value);
									out[outLine][value] = true;
								}
								skip = true;
							}
							
							// skip this whole expression in some cases
							if (ast[y].value == '(' || ast[y].value == ':')
								skip = true;
							value += ast[y].value;
							x++;
							y++;
					}

					if (!skip && reserved[initialValue] !== true) {
						let outLine = endLocation.line + '';
						//console.log("outline = ",outLine);
						if (out[outLine] == undefined)
							out[outLine] = {}
							//out[outLine] = [];
						//out[outLine].push(value);
						out[outLine][value] = true;
					}

				}
			}
			x++;
		}
	//console.log(JSON.stringify(out, null, '\n'));
		return out;
	} catch (err) {
		console.log("tokenizer error", err);
		return {};
	}
}

exports.getArgs = getArgs;
