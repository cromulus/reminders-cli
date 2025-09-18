import {
	IExecuteFunctions,
	INodeExecutionData,
	INodeType,
	INodeTypeDescription,
	NodeOperationError,
} from 'n8n-workflow';

export class SearchReminders implements INodeType {
	description: INodeTypeDescription = {
		displayName: 'Search Reminders',
		name: 'searchReminders',
		icon: 'file:search.svg',
		group: ['transform'],
		version: 1,
		subtitle: '={{$parameter["operation"]}}',
		description: 'Search and filter reminders with advanced criteria',
		defaults: {
			name: 'Search Reminders',
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
						name: 'Search',
						value: 'search',
						description: 'Search reminders with filters',
						action: 'Search reminders',
						routing: {
							request: {
								method: 'GET',
								url: '/search',
								qs: {
									query: '={{$parameter.query}}',
									lists: '={{$parameter.lists}}',
									exclude_lists: '={{$parameter.excludeLists}}',
									calendars: '={{$parameter.calendars}}',
									exclude_calendars: '={{$parameter.excludeCalendars}}',
									completed: '={{$parameter.completed}}',
									dueBefore: '={{$parameter.dueBefore}}',
									dueAfter: '={{$parameter.dueAfter}}',
									modifiedAfter: '={{$parameter.modifiedAfter}}',
									createdAfter: '={{$parameter.createdAfter}}',
									hasNotes: '={{$parameter.hasNotes}}',
									hasDueDate: '={{$parameter.hasDueDate}}',
									priority: '={{$parameter.priority}}',
									priorityMin: '={{$parameter.priorityMin}}',
									priorityMax: '={{$parameter.priorityMax}}',
									sortBy: '={{$parameter.sortBy}}',
									sortOrder: '={{$parameter.sortOrder}}',
									limit: '={{$parameter.limit}}',
								},
							},
						},
					},
					{
						name: 'Find Subtasks',
						value: 'findSubtasks',
						description: 'Find all subtask reminders',
						action: 'Find subtasks',
						routing: {
							request: {
								method: 'GET',
								url: '/search',
								qs: {
									isSubtask: 'true',
								},
							},
						},
					},
					{
						name: 'Find URL Attachments',
						value: 'findUrlAttachments',
						description: 'Find reminders with URL attachments',
						action: 'Find URL attachments',
						routing: {
							request: {
								method: 'GET',
								url: '/search',
								qs: {
									hasAttachedUrl: 'true',
								},
							},
						},
					},
					{
						name: 'Find Overdue',
						value: 'findOverdue',
						description: 'Find overdue reminders',
						action: 'Find overdue reminders',
						routing: {
							request: {
								method: 'GET',
								url: '/search',
								qs: {
									dueBefore: '={{new Date().toISOString()}}',
									completed: 'false',
								},
							},
						},
					},
				],
				default: 'search',
			},
			// Search parameters
			{
				displayName: 'Query',
				name: 'query',
				type: 'string',
				displayOptions: {
					show: {
						operation: ['search'],
					},
				},
				default: '',
				description: 'Text to search for in title and notes',
			},
			{
				displayName: 'Lists',
				name: 'lists',
				type: 'string',
				displayOptions: {
					show: {
						operation: ['search'],
					},
				},
				default: '',
				description: 'Comma-separated list names or UUIDs to include',
			},
			{
				displayName: 'Exclude Lists',
				name: 'excludeLists',
				type: 'string',
				displayOptions: {
					show: {
						operation: ['search'],
					},
				},
				default: '',
				description: 'Comma-separated list names or UUIDs to exclude',
			},
			{
				displayName: 'Calendars',
				name: 'calendars',
				type: 'string',
				displayOptions: {
					show: {
						operation: ['search'],
					},
				},
				default: '',
				description: 'Comma-separated calendar names or UUIDs to include',
			},
			{
				displayName: 'Exclude Calendars',
				name: 'excludeCalendars',
				type: 'string',
				displayOptions: {
					show: {
						operation: ['search'],
					},
				},
				default: '',
				description: 'Comma-separated calendar names or UUIDs to exclude',
			},
			{
				displayName: 'Completion Status',
				name: 'completed',
				type: 'options',
				displayOptions: {
					show: {
						operation: ['search'],
					},
				},
				options: [
					{
						name: 'All',
						value: 'all',
					},
					{
						name: 'Completed Only',
						value: 'true',
					},
					{
						name: 'Incomplete Only',
						value: 'false',
					},
				],
				default: 'false',
				description: 'Filter by completion status',
			},
			{
				displayName: 'Due Before',
				name: 'dueBefore',
				type: 'dateTime',
				displayOptions: {
					show: {
						operation: ['search'],
					},
				},
				default: '',
				description: 'Find reminders due before this date',
			},
			{
				displayName: 'Due After',
				name: 'dueAfter',
				type: 'dateTime',
				displayOptions: {
					show: {
						operation: ['search'],
					},
				},
				default: '',
				description: 'Find reminders due after this date',
			},
			{
				displayName: 'Modified After',
				name: 'modifiedAfter',
				type: 'dateTime',
				displayOptions: {
					show: {
						operation: ['search'],
					},
				},
				default: '',
				description: 'Find reminders modified after this date',
			},
			{
				displayName: 'Created After',
				name: 'createdAfter',
				type: 'dateTime',
				displayOptions: {
					show: {
						operation: ['search'],
					},
				},
				default: '',
				description: 'Find reminders created after this date',
			},
			{
				displayName: 'Has Notes',
				name: 'hasNotes',
				type: 'boolean',
				displayOptions: {
					show: {
						operation: ['search'],
					},
				},
				default: '',
				description: 'Filter by presence of notes',
			},
			{
				displayName: 'Has Due Date',
				name: 'hasDueDate',
				type: 'boolean',
				displayOptions: {
					show: {
						operation: ['search'],
					},
				},
				default: '',
				description: 'Filter by presence of due date',
			},
			{
				displayName: 'Priority',
				name: 'priority',
				type: 'options',
				displayOptions: {
					show: {
						operation: ['search'],
					},
				},
				options: [
					{
						name: 'Any Priority',
						value: 'any',
					},
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
					{
						name: 'Low, Medium',
						value: 'low,medium',
					},
					{
						name: 'Medium, High',
						value: 'medium,high',
					},
				],
				default: '',
				description: 'Filter by priority level',
			},
			{
				displayName: 'Priority Min',
				name: 'priorityMin',
				type: 'number',
				displayOptions: {
					show: {
						operation: ['search'],
					},
				},
				default: 0,
				description: 'Minimum priority level (0-3)',
			},
			{
				displayName: 'Priority Max',
				name: 'priorityMax',
				type: 'number',
				displayOptions: {
					show: {
						operation: ['search'],
					},
				},
				default: 3,
				description: 'Maximum priority level (0-3)',
			},
			{
				displayName: 'Sort By',
				name: 'sortBy',
				type: 'options',
				displayOptions: {
					show: {
						operation: ['search'],
					},
				},
				options: [
					{
						name: 'Title',
						value: 'title',
					},
					{
						name: 'Due Date',
						value: 'dueDate',
					},
					{
						name: 'Creation Date',
						value: 'creationDate',
					},
					{
						name: 'Last Modified',
						value: 'lastModified',
					},
					{
						name: 'Priority',
						value: 'priority',
					},
					{
						name: 'List',
						value: 'list',
					},
				],
				default: 'dueDate',
				description: 'Field to sort by',
			},
			{
				displayName: 'Sort Order',
				name: 'sortOrder',
				type: 'options',
				displayOptions: {
					show: {
						operation: ['search'],
					},
				},
				options: [
					{
						name: 'Ascending',
						value: 'asc',
					},
					{
						name: 'Descending',
						value: 'desc',
					},
				],
				default: 'asc',
				description: 'Sort direction',
			},
			{
				displayName: 'Limit',
				name: 'limit',
				type: 'number',
				displayOptions: {
					show: {
						operation: ['search'],
					},
				},
				default: 100,
				description: 'Maximum number of results to return',
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
