import {
	IExecuteFunctions,
	INodeExecutionData,
	INodeType,
	INodeTypeDescription,
	NodeOperationError,
} from 'n8n-workflow';

export class RemindersTrigger implements INodeType {
	description: INodeTypeDescription = {
		displayName: 'Reminders Trigger',
		name: 'remindersTrigger',
		icon: 'file:trigger.svg',
		group: ['trigger'],
		version: 1,
		subtitle: '={{$parameter["eventType"]}}',
		description: 'Trigger workflow when reminder events occur via webhook',
		defaults: {
			name: 'Reminders Trigger',
		},
		inputs: [],
		outputs: ['main'],
		credentials: [
			{
				name: 'remindersApi',
				required: true,
			},
		],
		webhooks: [
			{
				name: 'default',
				httpMethod: 'POST',
				responseMode: 'onReceived',
				path: 'reminders-webhook',
			},
		],
		properties: [
			{
				displayName: 'Event Type',
				name: 'eventType',
				type: 'options',
				noDataExpression: true,
				options: [
					{
						name: 'Created',
						value: 'created',
						description: 'When a new reminder is created',
					},
					{
						name: 'Updated',
						value: 'updated',
						description: 'When a reminder is modified',
					},
					{
						name: 'Deleted',
						value: 'deleted',
						description: 'When a reminder is deleted',
					},
					{
						name: 'Completed',
						value: 'completed',
						description: 'When a reminder is marked complete',
					},
					{
						name: 'Uncompleted',
						value: 'uncompleted',
						description: 'When a reminder is marked incomplete',
					},
					{
						name: 'All Events',
						value: 'all',
						description: 'All reminder events',
					},
				],
				default: 'all',
				description: 'Type of reminder events to listen for',
			},
			{
				displayName: 'List Names',
				name: 'listNames',
				type: 'string',
				default: '',
				description: 'Comma-separated list names to monitor (leave empty for all lists)',
			},
			{
				displayName: 'Priority Levels',
				name: 'priorityLevels',
				type: 'string',
				default: '',
				description: 'Comma-separated priority levels to monitor (0-3, leave empty for all)',
			},
			{
				displayName: 'Completion Status',
				name: 'completed',
				type: 'options',
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
				displayName: 'Has Query',
				name: 'hasQuery',
				type: 'string',
				default: '',
				description: 'Text that must be present in title/notes',
			},
			{
				displayName: 'Webhook URL',
				name: 'webhookUrl',
				type: 'string',
				default: '',
				description: 'The webhook URL to register with the Reminders API',
				required: true,
			},
		],
	};

	async webhook(this: IExecuteFunctions): Promise<INodeExecutionData[][]> {
		const webhookData = this.getInputData();
		const returnData: INodeExecutionData[] = [];

		for (const item of webhookData) {
			const webhookPayload = item.json as any;
			
			// Extract reminder data from webhook payload
			const reminderData = webhookPayload.reminder || webhookPayload;
			const eventType = webhookPayload.event || 'unknown';
			
			// Add event metadata
			const enrichedData = {
				...reminderData,
				eventType,
				timestamp: webhookPayload.timestamp || new Date().toISOString(),
				webhookId: webhookPayload.webhookId,
			};

			returnData.push({
				json: enrichedData,
			});
		}

		return [returnData];
	}

	async execute(this: IExecuteFunctions): Promise<INodeExecutionData[][]> {
		// This method is called when the node is executed manually
		// For trigger nodes, we typically don't need to implement this
		// as the webhook method handles the actual triggering
		return [[]];
	}
}
