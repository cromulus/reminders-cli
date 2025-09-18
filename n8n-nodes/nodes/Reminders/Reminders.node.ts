import {
	IExecuteFunctions,
	INodeExecutionData,
	INodeType,
	INodeTypeDescription,
	NodeOperationError,
} from 'n8n-workflow';

export class Reminders implements INodeType {
	description: INodeTypeDescription = {
		displayName: 'Reminders',
		name: 'reminders',
		icon: 'file:reminders.svg',
		group: ['transform'],
		version: 1,
		subtitle: '={{$parameter["operation"] + ": " + $parameter["resource"]}}',
		description: 'Create, read, update, and delete macOS Reminders',
		defaults: {
			name: 'Reminders',
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
				displayName: 'Resource',
				name: 'resource',
				type: 'options',
				noDataExpression: true,
				options: [
					{
						name: 'Reminder',
						value: 'reminder',
					},
					{
						name: 'List',
						value: 'list',
					},
				],
				default: 'reminder',
			},
			{
				displayName: 'Operation',
				name: 'operation',
				type: 'options',
				noDataExpression: true,
				displayOptions: {
					show: {
						resource: ['reminder'],
					},
				},
				options: [
					{
						name: 'Create',
						value: 'create',
						description: 'Create a new reminder',
						action: 'Create a reminder',
						routing: {
							request: {
								method: 'POST',
								url: '=/lists/{{$parameter.listName}}/reminders',
								body: {
									title: '={{$parameter.title}}',
									notes: '={{$parameter.notes}}',
									dueDate: '={{$parameter.dueDate}}',
									priority: '={{$parameter.priority}}',
								},
							},
						},
					},
					{
						name: 'Get',
						value: 'get',
						description: 'Get a specific reminder by UUID',
						action: 'Get a reminder',
						routing: {
							request: {
								method: 'GET',
								url: '=/reminders/{{$parameter.reminderUuid}}',
							},
						},
					},
					{
						name: 'Get All',
						value: 'getAll',
						description: 'Get all reminders across all lists',
						action: 'Get all reminders',
						routing: {
							request: {
								method: 'GET',
								url: '/reminders',
								qs: {
									completed: '={{$parameter.includeCompleted}}',
								},
							},
						},
					},
					{
						name: 'Update',
						value: 'update',
						description: 'Update an existing reminder',
						action: 'Update a reminder',
						routing: {
							request: {
								method: 'PATCH',
								url: '=/reminders/{{$parameter.reminderUuid}}',
								body: {
									title: '={{$parameter.title}}',
									notes: '={{$parameter.notes}}',
									dueDate: '={{$parameter.dueDate}}',
									priority: '={{$parameter.priority}}',
									isCompleted: '={{$parameter.isCompleted}}',
								},
							},
						},
					},
					{
						name: 'Delete',
						value: 'delete',
						description: 'Delete a reminder',
						action: 'Delete a reminder',
						routing: {
							request: {
								method: 'DELETE',
								url: '=/reminders/{{$parameter.reminderUuid}}',
							},
						},
					},
					{
						name: 'Complete',
						value: 'complete',
						description: 'Mark a reminder as complete',
						action: 'Complete a reminder',
						routing: {
							request: {
								method: 'PATCH',
								url: '=/reminders/{{$parameter.reminderUuid}}/complete',
							},
						},
					},
					{
						name: 'Uncomplete',
						value: 'uncomplete',
						description: 'Mark a reminder as incomplete',
						action: 'Uncomplete a reminder',
						routing: {
							request: {
								method: 'PATCH',
								url: '=/reminders/{{$parameter.reminderUuid}}/uncomplete',
							},
						},
					},
				],
				default: 'create',
			},
			{
				displayName: 'Operation',
				name: 'operation',
				type: 'options',
				noDataExpression: true,
				displayOptions: {
					show: {
						resource: ['list'],
					},
				},
				options: [
					{
						name: 'Get All',
						value: 'getAll',
						description: 'Get all reminder lists',
						action: 'Get all lists',
						routing: {
							request: {
								method: 'GET',
								url: '/lists',
							},
						},
					},
					{
						name: 'Get Reminders',
						value: 'getReminders',
						description: 'Get reminders from a specific list',
						action: 'Get reminders from list',
						routing: {
							request: {
								method: 'GET',
								url: '=/lists/{{$parameter.listName}}',
								qs: {
									completed: '={{$parameter.includeCompleted}}',
								},
							},
						},
					},
				],
				default: 'getAll',
			},
			// Reminder-specific parameters
			{
				displayName: 'List Name',
				name: 'listName',
				type: 'string',
				displayOptions: {
					show: {
						resource: ['reminder'],
						operation: ['create'],
					},
				},
				default: '',
				description: 'Name of the list to create the reminder in',
				required: true,
			},
			{
				displayName: 'Title',
				name: 'title',
				type: 'string',
				displayOptions: {
					show: {
						resource: ['reminder'],
						operation: ['create', 'update'],
					},
				},
				default: '',
				description: 'Title of the reminder',
				required: true,
			},
			{
				displayName: 'Notes',
				name: 'notes',
				type: 'string',
				typeOptions: {
					rows: 3,
				},
				displayOptions: {
					show: {
						resource: ['reminder'],
						operation: ['create', 'update'],
					},
				},
				default: '',
				description: 'Additional notes for the reminder',
			},
			{
				displayName: 'Due Date',
				name: 'dueDate',
				type: 'dateTime',
				displayOptions: {
					show: {
						resource: ['reminder'],
						operation: ['create', 'update'],
					},
				},
				default: '',
				description: 'Due date for the reminder (ISO8601 format)',
			},
			{
				displayName: 'Priority',
				name: 'priority',
				type: 'options',
				displayOptions: {
					show: {
						resource: ['reminder'],
						operation: ['create', 'update'],
					},
				},
				options: [
					{
						name: 'None',
						value: 'none',
					},
					{
						name: 'Low',
						value: 'low',
					},
					{
						name: 'Medium',
						value: 'medium',
					},
					{
						name: 'High',
						value: 'high',
					},
				],
				default: 'none',
				description: 'Priority level of the reminder',
			},
			{
				displayName: 'Is Completed',
				name: 'isCompleted',
				type: 'boolean',
				displayOptions: {
					show: {
						resource: ['reminder'],
						operation: ['update'],
					},
				},
				default: false,
				description: 'Whether the reminder is completed',
			},
			{
				displayName: 'Reminder UUID',
				name: 'reminderUuid',
				type: 'string',
				displayOptions: {
					show: {
						resource: ['reminder'],
						operation: ['get', 'update', 'delete', 'complete', 'uncomplete'],
					},
				},
				default: '',
				description: 'UUID of the reminder',
				required: true,
			},
			{
				displayName: 'Include Completed',
				name: 'includeCompleted',
				type: 'boolean',
				displayOptions: {
					show: {
						resource: ['reminder', 'list'],
						operation: ['getAll', 'getReminders'],
					},
				},
				default: false,
				description: 'Whether to include completed reminders in the results',
			},
			// List-specific parameters
			{
				displayName: 'List Name',
				name: 'listName',
				type: 'string',
				displayOptions: {
					show: {
						resource: ['list'],
						operation: ['getReminders'],
					},
				},
				default: '',
				description: 'Name or UUID of the list to get reminders from',
				required: true,
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
