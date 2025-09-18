module.exports = {
	root: true,
	env: {
		node: true,
		es6: true,
	},
	parserOptions: {
		ecmaVersion: 2020,
	},
	extends: ['eslint:recommended', 'plugin:n8n-nodes-base/nodes'],
	rules: {
		'n8n-nodes-base/node-param-default-missing': 'off',
		'n8n-nodes-base/node-param-placeholder-miscased-id': 'off',
	},
};
