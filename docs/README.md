# Finolo API Test Suite

This directory contains curl-based API integration tests for Finolo.

## Test Files

- `run-all-api-tests.sh` - Runs every curl-based API suite
- `api-test-helpers.sh` - Shared curl/assertion/data setup helpers
- `test-user-api.sh` - User Module, Skills, and User Skills API tests
- `test-task-required-skills-api.sh` - Task Required Skills API tests
- `test-workspace-api.sh` - Workspace Module API tests
- `test-project-api.sh` - Project Module API tests
- `test-task-api.sh` - Task Module API tests
- `test-task-checklist-api.sh` - Task Checklists and Checklist Items API tests
- `test-task-advanced-api.sh` - Task Dependencies, Relationships, Hierarchy, Templates, Custom Fields, and Recurring Task API tests
- `test-simple-modules-api.sh` - Column, Section, Tag, and Comment API tests
- `test-timelog-notification-api.sh` - Time Log and Notification API tests
- `test-workspace-project-extended-api.sh` - Workspace Settings, Collections, Exports, Reporting, Invites, Members, and Project Team API tests
- `test-attachment-api.sh` - Attachment upload, metadata, download, and version API tests
- `test-search-activity-analytics-api.sh` - Search, Activity, and Analytics API tests
- `test-webhook-realtime-api.sh` - Webhook and Realtime Notification API tests
- `test-timelog-notification-extended-api.sh` - Extended Time Log and Notification Preference API tests

## Running Tests

### Prerequisites

1. Start the Laravel development server:
```bash
php artisan serve --host=127.0.0.1 --port=8000
```

2. Ensure the database is seeded:
```bash
php artisan db:seed
```

### Run Tests

```bash
./tests/api/run-all-api-tests.sh
```

To run one focused suite:

```bash
./tests/api/test-webhook-realtime-api.sh
```

## Test Coverage

The full suite currently runs 14 curl scripts and covers every Phase 10 API module listed in `FINOLO_PRODUCTION_UPGRADE_PLAN.md`:

- Auth, Users, Skills, User Skills, and Task Required Skills
- Workspaces, Workspace Settings, Collections, Exports, Reporting, Invites, and Members
- Projects, Project Watchers, and Project Teams
- Tasks, Task Watchers, Checklists, Dependencies, Relationships, Hierarchy, Templates, Custom Fields, and Recurring Tasks
- Columns, Sections, Tags, Comments, and Attachments
- Time Logs, Notifications, Notification Preferences, and Realtime Notifications
- Search, Activities, Analytics, Webhooks, and Webhook Deliveries

The endpoint-by-endpoint audit checklist lives in `FINOLO_PRODUCTION_UPGRADE_PLAN.md`.

## Test Principles

- **No Mocks**: All tests use real database records
- **Dynamic Resources**: Tests create unique resources (timestamps in names/emails) to avoid conflicts
- **Real HTTP**: Tests use curl to make actual HTTP requests
- **Multipart Coverage**: Attachment tests use curl multipart uploads for file APIs
- **Cleanup**: Shared helpers remove records created by the suite where direct API cleanup is not enough
- **Production-Ready**: Tests verify endpoints work as they would in production

## Exit Codes

- `0` - All tests passed
- `1` - One or more tests failed
