import {
	IAuthenticateGeneric,
	ICredentialTestRequest,
	ICredentialType,
	INodeProperties,
} from 'n8n-workflow';

export class RemindersApi implements ICredentialType {
	name = 'remindersApi';
	displayName = 'Reminders API';
	documentationUrl = 'https://github.com/your-username/n8n-nodes-reminders-api';
	properties: INodeProperties[] = [
		{
			displayName: 'API Base URL',
			name: 'baseUrl',
			type: 'string',
			default: 'http://localhost:8080',
			description: 'The base URL of your Reminders API server',
		},
		{
			displayName: 'API Token',
			name: 'apiToken',
			type: 'string',
			typeOptions: { password: true },
			default: '',
			description: 'Your Reminders API authentication token',
		},
		{
			displayName: 'Authentication Required',
			name: 'authRequired',
			type: 'boolean',
			default: false,
			description: 'Whether authentication is required for all API calls',
		},
	];

	authenticate: IAuthenticateGeneric = {
		type: 'generic',
		properties: {
			headers: {
				Authorization: '=Bearer {{$credentials.apiToken}}',
			},
		},
	};

	test: ICredentialTestRequest = {
		request: {
			baseURL: '={{$credentials.baseUrl}}',
			url: '/lists',
			method: 'GET',
		},
	};
}
