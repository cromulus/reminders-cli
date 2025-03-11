# reminders-cli

A simple CLI for interacting with OS X reminders.

## Usage:

#### Show all lists

```
$ reminders show-lists
Soon
Eventually

# Show lists with UUIDs
$ reminders show-lists --show-u-u-i-ds
Soon [5F6D3A2B-C8E7-4591-A03F-D83E2CB27591]
Eventually [3B6C4A9D-E7F8-5192-B04E-A72F3DC38692]
```

#### Show reminders on a specific list

```
$ reminders show Soon
0 Write README
1 Ship reminders-cli

# Show reminders with UUIDs
$ reminders show Soon --show-u-u-i-ds
0 Write README [UUID: x-apple-reminder://F3A0B3D8-E153-4AB9-B341-0C32A9AC6C2D]
1 Ship reminders-cli [UUID: x-apple-reminder://18F92A5D-7D64-45A8-BC2F-6D1B3217A251]

# You can also use the list UUID instead of name
$ reminders show 5F6D3A2B-C8E7-4591-A03F-D83E2CB27591
0 Write README
1 Ship reminders-cli
```

#### Complete an item on a list

```
$ reminders complete Soon 0
Completed 'Write README'
$ reminders show Soon
0 Ship reminders-cli

# You can also use UUID instead of index
$ reminders complete Soon x-apple-reminder://18F92A5D-7D64-45A8-BC2F-6D1B3217A251
Completed 'Ship reminders-cli'
```

#### Undo a completed item

```
$ reminders show Soon --only-completed
0 Write README
$ reminders uncomplete Soon 0
Uncompleted 'Write README'
$ reminders show Soon
0 Write README
```

#### Edit an item on a list

```
$ reminders edit Soon 0 Some edited text
Updated reminder 'Some edited text'
$ reminders show Soon
0 Ship reminders-cli
1 Some edited text
```

#### Delete an item on a list

```
$ reminders delete Soon 0
Completed 'Write README'
$ reminders show Soon
0 Ship reminders-cli
```

#### Add a reminder to a list

```
$ reminders add Soon Contribute to open source
$ reminders add Soon Go to the grocery store --due-date "tomorrow 9am"
$ reminders add Soon Something really important --priority high
$ reminders show Soon
0: Ship reminders-cli
1: Contribute to open source
2: Go to the grocery store (in 10 hours)
3: Something really important (priority: high)
```

#### Show reminders due on or by a date

```
$ reminders show-all --due-date today
1: Contribute to open source (in 3 hours)
$ reminders show-all --due-date today --include-overdue
0: Ship reminders-cli (2 days ago)
1: Contribute to open source (in 3 hours)
$ reminders show-all --due-date 2025-02-16
1: Contribute to open source (in 3 hours)
$ reminders show Soon --due-date today --include-overdue
0: Ship reminders-cli (2 days ago)
1: Contribute to open source (in 3 hours)
```

#### See help for more examples

```
$ reminders --help
$ reminders show -h
```

## Installation:

#### With [Homebrew](http://brew.sh/)

```
$ brew install keith/formulae/reminders-cli
```

#### From GitHub releases

Download the latest release from
[here](https://github.com/keith/reminders-cli/releases)

```
$ tar -zxvf reminders.tar.gz
$ mv reminders /usr/local/bin
$ rm reminders.tar.gz
```

#### Building manually

This requires a recent Xcode installation.

```
$ cd reminders-cli
$ make build-release
$ cp .build/apple/Products/Release/reminders /usr/local/bin/reminders
```

## REST API Server

This project includes a REST API server that allows you to interact with your reminders via HTTP requests. This is useful for building web applications, integrating with other services, or automating reminders management.

### Installation and Setup

#### Build the API server

```bash
# Build with Swift Package Manager
$ swift build
$ ./.build/debug/reminders-api

# Or build a release version
$ make build-release
$ ./.build/apple/Products/Release/reminders-api

# Or package for distribution
$ make package-api
$ ./reminders-api
```

The server runs on `localhost:8080` by default. The first time you run it, you'll need to grant permission to access your reminders, just like with the CLI.

### API Endpoints

| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | `/lists` | List all reminder lists |
| GET | `/lists/:name` | Get reminders from a specific list |
| GET | `/reminders` | Get all reminders across all lists |
| POST | `/lists/:name/reminders` | Add a new reminder to a list |
| DELETE | `/lists/:listName/reminders/:id` | Delete a reminder |
| PATCH | `/lists/:listName/reminders/:id/complete` | Mark a reminder as complete |
| PATCH | `/lists/:listName/reminders/:id/uncomplete` | Mark a reminder as incomplete |

### Query Parameters

- For GET requests to `/lists/:name` and `/reminders`:
  - `completed=true` - Include completed items in the results (by default, only incomplete items are returned)

### Request and Response Examples

#### GET /lists

Request:
```bash
curl http://localhost:8080/lists
```

Response:
```json
[
  "Work",
  "Personal",
  "Shopping",
  "Soon"
]
```

#### GET /lists/:name

Request:
```bash
# Get incomplete reminders from a list
curl http://localhost:8080/lists/Soon

# Include completed reminders
curl "http://localhost:8080/lists/Soon?completed=true"
```

Response:
```json
[
  {
    "creationDate": "2025-03-10T14:30:00Z",
    "dueDate": "2025-03-15T09:00:00Z",
    "id": "x-apple-reminder://F3A0B3D8-E153-4AB9-B341-0C32A9AC6C2D",
    "isCompleted": false,
    "lastModifiedDate": "2025-03-10T14:30:00Z",
    "listName": "Soon",
    "notes": "Important deadline",
    "priority": 5,
    "title": "Finish project proposal"
  },
  {
    "creationDate": "2025-03-09T10:15:00Z",
    "dueDate": "2025-03-12T17:00:00Z",
    "id": "x-apple-reminder://18F92A5D-7D64-45A8-BC2F-6D1B3217A251",
    "isCompleted": false,
    "lastModifiedDate": "2025-03-09T10:15:00Z",
    "listName": "Soon",
    "notes": null,
    "priority": 0,
    "title": "Buy groceries"
  }
]
```

#### GET /reminders

Request:
```bash
# Get all incomplete reminders across all lists
curl http://localhost:8080/reminders

# Include completed reminders
curl "http://localhost:8080/reminders?completed=true"
```

Response:
```json
[
  {
    "creationDate": "2025-03-10T14:30:00Z",
    "dueDate": "2025-03-15T09:00:00Z",
    "id": "x-apple-reminder://F3A0B3D8-E153-4AB9-B341-0C32A9AC6C2D",
    "isCompleted": false,
    "lastModifiedDate": "2025-03-10T14:30:00Z",
    "listName": "Soon",
    "notes": "Important deadline",
    "priority": 5,
    "title": "Finish project proposal"
  },
  {
    "creationDate": "2025-03-08T11:20:00Z",
    "dueDate": "2025-03-11T13:00:00Z",
    "id": "x-apple-reminder://C4D92F3E-8A7B-4C97-B6F1-2E5D9F87A3E1",
    "isCompleted": false,
    "lastModifiedDate": "2025-03-08T11:20:00Z",
    "listName": "Work",
    "notes": null,
    "priority": 9,
    "title": "Team meeting"
  }
]
```

#### POST /lists/:name/reminders

Request:
```bash
curl -X POST http://localhost:8080/lists/Soon/reminders \
  -H "Content-Type: application/json" \
  -d '{
    "title": "API reminder",
    "notes": "Created via REST API",
    "dueDate": "2025-03-11T09:00:00Z",
    "priority": "high"
  }'
```

Response:
```json
{
  "creationDate": "2025-03-10T15:05:23Z",
  "dueDate": "2025-03-11T09:00:00Z",
  "id": "x-apple-reminder://D1E8F7C6-5A4B-3C2D-9E8F-7A6B5C4D3E2F",
  "isCompleted": false,
  "lastModifiedDate": "2025-03-10T15:05:23Z",
  "listName": "Soon",
  "notes": "Created via REST API",
  "priority": 5,
  "title": "API reminder"
}
```

#### DELETE /lists/:listName/reminders/:id

Request:
```bash
curl -X DELETE http://localhost:8080/lists/Soon/reminders/x-apple-reminder://D1E8F7C6-5A4B-3C2D-9E8F-7A6B5C4D3E2F
```

Response:
- Status code 204 No Content

#### PATCH /lists/:listName/reminders/:id/complete

Request:
```bash
curl -X PATCH http://localhost:8080/lists/Soon/reminders/x-apple-reminder://F3A0B3D8-E153-4AB9-B341-0C32A9AC6C2D/complete
```

Response:
- Status code 200 OK

#### PATCH /lists/:listName/reminders/:id/uncomplete

Request:
```bash
curl -X PATCH http://localhost:8080/lists/Soon/reminders/x-apple-reminder://F3A0B3D8-E153-4AB9-B341-0C32A9AC6C2D/uncomplete
```

Response:
- Status code 200 OK

### Using with JavaScript/Fetch API

```javascript
// Get all reminder lists
fetch('http://localhost:8080/lists')
  .then(response => response.json())
  .then(lists => console.log(lists));

// Create a new reminder
fetch('http://localhost:8080/lists/Soon/reminders', {
  method: 'POST',
  headers: {
    'Content-Type': 'application/json',
  },
  body: JSON.stringify({
    title: 'Web reminder',
    notes: 'Created from web app',
    dueDate: '2025-03-15T10:00:00Z',
    priority: 'medium'
  }),
})
  .then(response => response.json())
  .then(reminder => console.log(reminder));

// Mark a reminder as complete
fetch('http://localhost:8080/lists/Soon/reminders/x-apple-reminder://F3A0B3D8-E153-4AB9-B341-0C32A9AC6C2D/complete', {
  method: 'PATCH'
})
  .then(response => {
    if (response.ok) console.log('Reminder marked as complete');
  });
```
