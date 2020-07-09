const fs = require('fs');
const esprima = require('../esprima/esprima');
 


function getTokensWrapper(file, lineLocation, rad) {
	let tokens = {};
	let from = lineLocation - rad;
	let to = lineLocation + rad;


	function addToken(token, line) {
		if (tokens[line] == undefined)
			tokens[line] = {};
		tokens[line][token] = 1;
	}

	function processArg(arg) {
		if (!Array.isArray(arg)) {
			getTokens(arg);
		}
		else {
			let y = 0;
			while (y < arg.length) {
				getTokens(arg[y]);
				y++;
			}
		}
	}

	function getTokens(node) {

		if (node.loc && node.loc.start.line <= to && node.loc.end.line >= from) {

			if (node.type == 'Program' || node.type == 'ClassDeclaration' || node.type == 'ClassBody')	{
				processArg(node.body);
			}
			else if (node.type == 'FunctionDeclaration' || node.type == 'FunctionExpression')	{
				if (node.params) {
					processArg(node.params);
				}
				if (node.body) {
					processArg(node.body);
				}
			}
			else if (node.type == 'Identifier' && node.name)	{
				addToken(node.name, node.loc.start.line);
			}
			else if (node.type == 'BlockStatement' && node.body)	{
				processArg(node.body);
			}
			else if (node.type == 'ExpressionStatement' && node.expression && node.expression.arguments)	{
				processArg(node.expression.arguments);
			}
			else if (node.type == 'VariableDeclaration' && node.declarations)	{
				processArg(node.declarations);
			}
			else if (node.type == 'VariableDeclarator' && node.id && node.id.name)	{
				addToken(node.id.name, node.loc.start.line);
				if (node.init) {
					getTokens(node.init);
				}
			}
			else if (node.type == 'MethodDefinition' && node.value)	{
				processArg(node.value);
			}
			else if (node.type == "CallExpression" && node.arguments) {
				processArg(node.arguments);
			}
		}
	}

	try {
		const contents = fs.readFileSync(file, 'utf8');
		var ast = esprima.parseScript(contents,{ loc: true});
		getTokens(ast);
		return tokens;
	} catch(err) {
		console.log("error tokenizing.");
		return {};
	}
}



exports.getTokens = getTokensWrapper;
