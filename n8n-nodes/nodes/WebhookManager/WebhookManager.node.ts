import {
	IExecuteFunctions,
	INodeExecutionData,
	INodeType,
	INodeTypeDescription,
	NodeOperationError,
} from 'n8n-workflow';

export class WebhookManager implements INodeType {
	description: INodeTypeDescription = {
		displayName: 'Webhook Manager',
		name: 'webhookManager',
		icon: 'file:webhook.svg',
		group: ['transform'],
		version: 1,
		subtitle: '={{$parameter["operation"]}}',
		description: 'Manage webhook configurations for real-time reminder notifications',
		defaults: {
			name: 'Webhook Manager',
		},
		inputs: ['main'],
		outputs: ['main'],
		credentials: [
			{
				name: 'remindersApi',
				required: true,
			},
		],
		requestDefaults: {
			baseURL: '={{$credentials.baseUrl}}',
			headers: {
				Accept: 'application/json',
				'Content-Type': 'application/json',
			},
		},
		properties: [
			{
				displayName: 'Operation',
				name: 'operation',
				type: 'options',
				noDataExpression: true,
				options: [
					{
						name: 'Create',
						value: 'create',
						description: 'Create a new webhook',
						action: 'Create a webhook',
						routing: {
							request: {
								method: 'POST',
								url: '/webhooks',
								body: {
									url: '={{$parameter.webhookUrl}}',
									name: '={{$parameter.webhookName}}',
									filter: {
										listNames: '={{$parameter.listNames}}',
										listUUIDs: '={{$parameter.listUUIDs}}',
										completed: '={{$parameter.completed}}',
										priorityLevels: '={{$parameter.priorityLevels}}',
										hasQuery: '={{$parameter.hasQuery}}',
									},
								},
							},
						},
					},
					{
						name: 'Get All',
						value: 'getAll',
						description: 'Get all webhook configurations',
						action: 'Get all webhooks',
						routing: {
							request: {
								method: 'GET',
								url: '/webhooks',
							},
						},
					},
					{
						name: 'Get',
						value: 'get',
						description: 'Get a specific webhook by ID',
						action: 'Get a webhook',
						routing: {
							request: {
								method: 'GET',
								url: '=/webhooks/{{$parameter.webhookId}}',
							},
						},
					},
					{
						name: 'Update',
						value: 'update',
						description: 'Update an existing webhook',
						action: 'Update a webhook',
						routing: {
							request: {
								method: 'PATCH',
								url: '=/webhooks/{{$parameter.webhookId}}',
								body: {
									url: '={{$parameter.webhookUrl}}',
									name: '={{$parameter.webhookName}}',
									isActive: '={{$parameter.isActive}}',
									filter: {
										listNames: '={{$parameter.listNames}}',
										listUUIDs: '={{$parameter.listUUIDs}}',
										completed: '={{$parameter.completed}}',
										priorityLevels: '={{$parameter.priorityLevels}}',
										hasQuery: '={{$parameter.hasQuery}}',
									},
								},
							},
						},
					},
					{
						name: 'Delete',
						value: 'delete',
						description: 'Delete a webhook',
						action: 'Delete a webhook',
						routing: {
							request: {
								method: 'DELETE',
								url: '=/webhooks/{{$parameter.webhookId}}',
							},
						},
					},
					{
						name: 'Test',
						value: 'test',
						description: 'Test a webhook by sending a test event',
						action: 'Test a webhook',
						routing: {
							request: {
								method: 'POST',
								url: '=/webhooks/{{$parameter.webhookId}}/test',
							},
						},
					},
				],
				default: 'create',
			},
			// Webhook parameters
			{
				displayName: 'Webhook ID',
				name: 'webhookId',
				type: 'string',
				displayOptions: {
					show: {
						operation: ['get', 'update', 'delete', 'test'],
					},
				},
				default: '',
				description: 'UUID of the webhook',
				required: true,
			},
			{
				displayName: 'Webhook URL',
				name: 'webhookUrl',
				type: 'string',
				displayOptions: {
					show: {
						operation: ['create', 'update'],
					},
				},
				default: '',
				description: 'URL to send webhook notifications to',
				required: true,
			},
			{
				displayName: 'Webhook Name',
				name: 'webhookName',
				type: 'string',
				displayOptions: {
					show: {
						operation: ['create', 'update'],
					},
				},
				default: '',
				description: 'Name for the webhook configuration',
				required: true,
			},
			{
				displayName: 'Is Active',
				name: 'isActive',
				type: 'boolean',
				displayOptions: {
					show: {
						operation: ['update'],
					},
				},
				default: true,
				description: 'Whether the webhook is active',
			},
			// Filter parameters
			{
				displayName: 'List Names',
				name: 'listNames',
				type: 'string',
				displayOptions: {
					show: {
						operation: ['create', 'update'],
					},
				},
				default: '',
				description: 'Comma-separated list names to monitor',
			},
			{
				displayName: 'List UUIDs',
				name: 'listUUIDs',
				type: 'string',
				displayOptions: {
					show: {
						operation: ['create', 'update'],
					},
				},
				default: '',
				description: 'Comma-separated list UUIDs to monitor',
			},
			{
				displayName: 'Completion Status',
				name: 'completed',
				type: 'options',
				displayOptions: {
					show: {
						operation: ['create', 'update'],
					},
				},
				options: [
					{
						name: 'All',
						value: 'all',
					},
					{
						name: 'Completed Only',
						value: 'complete',
					},
					{
						name: 'Incomplete Only',
						value: 'incomplete',
					},
				],
				default: 'incomplete',
				description: 'Filter by completion status',
			},
			{
				displayName: 'Priority Levels',
				name: 'priorityLevels',
				type: 'string',
				displayOptions: {
					show: {
						operation: ['create', 'update'],
					},
				},
				default: '',
				description: 'Comma-separated priority levels to monitor (0-3)',
			},
			{
				displayName: 'Has Query',
				name: 'hasQuery',
				type: 'string',
				displayOptions: {
					show: {
						operation: ['create', 'update'],
					},
				},
				default: '',
				description: 'Text that must be present in title/notes',
			},
		],
	};

	async execute(this: IExecuteFunctions): Promise<INodeExecutionData[][]> {
		const items = this.getInputData();
		const returnData: INodeExecutionData[] = [];

		for (let i = 0; i < items.length; i++) {
			try {
				const responseData = await this.helpers.requestWithAuthentication.call(
					this,
					'remindersApi',
					{},
				);

				returnData.push({
					json: responseData,
				});
			} catch (error) {
				if (this.continueOnFail()) {
					returnData.push({
						json: { error: error.message },
					});
					continue;
				}
				throw new NodeOperationError(this.getNode(), error);
			}
		}

		return [returnData];
	}
}
