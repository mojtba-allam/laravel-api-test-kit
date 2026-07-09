# Authorization Model — Review (current)

This document reflects the **reworked** authorization model (system Super Admin +
per-project, per-member granular permissions). It supersedes the previous owner/member
matrices.

## Source of truth

| Concern | File |
| --- | --- |
| System super-admin bypass | `app/Providers/AppServiceProvider.php` (`Gate::before`) |
| Access resolver | `Modules/Project/Support/ProjectAccess.php` |
| Permission catalog | `Modules/Project/Support/PermissionCatalog.php` |
| System roles (user ↔ role) | `user_global_roles` pivot; `User::systemRoles()` |
| Member permissions | `project_member_permissions` pivot; `ProjectMember::permissions()` |
| Policies | `Modules/*/Policies/*Policy.php` |

## Resolution order

For any project-scoped ability the resolver evaluates, in order:

1. **Super Admin** (`User::isSuperAdmin()` via `user_global_roles`) → allow everything
   (also enforced globally by `Gate::before`).
2. **Project Admin** (project `owner_id`, `created_by`, or the workspace `owner_id`) →
   implicitly holds every permission in that project.
3. **Direct member permission** — the slug exists in the member's
   `project_member_permissions` grants.
4. **Active workspace member** → read access (`canView`) to the project and its children.
5. Otherwise → **deny**.

Job-title roles (`project_roles`) are **labels only** and are never consulted for permissions.

## Actor glossary

- **Super Admin** — system role; bypasses all policies.
- **Project Admin** — project owner/creator or workspace owner; all permissions in-project.
- **Member** — `project_members` row; abilities = directly granted permission slugs.
- **Author/Uploader/Owner-of-record** — creator of a specific comment/attachment/time log.
- **Workspace member (active)** — read access to the workspace's projects + children.
- **Other** — authenticated but unrelated → denied on scoped resources.

## Permission catalog (granted per member)

Project: `view_project`, `edit_project`, `delete_project`, `manage_members`, `manage_roles`,
`view_reports`, `view_activity_log`, `export_data` ·
Section: `create_section`, `edit_section`, `delete_section` ·
Column: `create_column`, `edit_column`, `delete_column`, `reorder_column` ·
Task: `create_task`, `edit_task`, `delete_task`, `assign_task`, `move_task` ·
Comment: `create_comment`, `edit_comment`, `delete_comment` ·
Attachment: `upload_attachment`, `delete_attachment` ·
Tag: `create_tag`, `edit_tag`, `delete_tag` ·
TimeLog: `log_time`, `view_timelogs` ·
Other: `manage_custom_fields`, `manage_webhooks`, `manage_automation`.

Default set granted to a new member: `view_project`, `create_task`, `edit_task`, `move_task`,
`create_comment`, `upload_attachment`, `log_time`, `view_timelogs`.

## Per-resource instance rules (view/create/update/delete)

| Resource | view | create | update | delete |
| --- | --- | --- | --- | --- |
| Project | member / ws-member / admin | any auth | `edit_project` or project admin | project admin |
| Section | project access | `create_section` | `edit_section` | `delete_section` |
| Column | project access | `create_column` | `edit_column` | `delete_column` (+`reorder_column`) |
| Task | project access | `create_task` | `edit_task` | `delete_task` **or** task creator |
| Comment | project access | `create_comment` | author **or** `edit_comment`/project admin | author **or** `delete_comment`/project admin |
| Attachment | project access | `upload_attachment` | uploader **or** project admin | uploader **or** `delete_attachment`/project admin |
| Tag | project access | `create_tag` | `edit_tag` | `delete_tag` |
| TimeLog | own log **or** project member | `log_time` | own log (+`log_time`) **or** project admin | same as update |

Super Admin satisfies every cell via `Gate::before`.

## HTTP expectations (key cases)

| Scenario | Expected |
| --- | --- |
| Non-member creates comment/task/attachment/timelog | 403 |
| Member with `create_task` creates a task | 201 |
| Member without `edit_task` updates a task | 403 |
| Member granted `edit_task` updates a task | 200 |
| Comment author edits/deletes own comment | 200 |
| Plain member deletes another's comment | 403 |
| Project owner moderates (deletes) another's comment/attachment | 200 |
| Project member views another member's time log | 200 |
| Super Admin performs any action in any project | 200/201/204 |
| Client supplies `user_id`/`created_by` to spoof authorship | ignored (forced to auth user) |

Verified by:
- `bash tests/api/run-all-api-tests.sh` (28/28 scripts, incl. `test-policy-authorization-api.sh`,
  `test-comment-attachment-policy-api.sh`, `test-project-roles-permissions-api.sh`).
- `php artisan test` (PHPUnit: `ProjectAccessTest`, `ProjectMemberPermissionApiTest`,
  `PolicyEnforcementTest`, `BackfillAuthorizationTest`).

---

# Index / list query scoping audit (task 4.3)

`viewAny` is intentionally permissive (Decision 3); the contract is that **list queries must
be scoped to what the caller can access**. Current state of the list endpoints:

| Endpoint | Scoped to caller? | Notes |
| --- | --- | --- |
| `GET /projects` | ✅ | `getPaginatedProjectsForUser()` |
| `GET /workspaces` | ✅ | `paginateForUser()` |
| `GET /sections?project_id=` | ✅ (when filtered) | authorizes `view` on the project |
| `GET /sections` (no filter) | ❌ | returns all sections (paginated) |
| `GET /columns` | ⚠️ | scoped only when `section_id` provided; otherwise all |
| `GET /comments` | ❌ | returns all comments (paginated) |
| `GET /tasks` | ❌ | returns all / search across all projects |
| `GET /tags` | ❌ | returns all (filterable by `project_id`) |
| `GET /time-logs` | ❌ | returns all (filterable) |
| `GET /attachments` | ⚠️ | scoped only when `task_id` provided; otherwise all |

**Finding:** unfiltered list endpoints for Comment, Task, Tag, TimeLog, Section, and the
no-filter cases of Column/Attachment return cross-project rows. Individual-record access is
correctly gated by the policies, but the *collections* are not yet tenant-scoped.

**Status:** audited and documented. Implementing tenant scoping on these collections is a
behavior change (it alters what each list returns) and is tracked as a follow-up so it can be
rolled out with explicit product confirmation and its own regression pass. Recommended approach:
a shared "accessible project ids for user" resolver applied in each repository's `paginate`,
returning all rows for Super Admin.
