# Fastly Client-Side Protection

Base: `https://api.fastly.com` | Auth: `Fastly-Key: $FASTLY_API_TOKEN` | Docs: https://www.fastly.com/documentation/guides/security/client-side-protection

## Key Concepts

**Hierarchical data model.** Websites contain pages, pages contain scripts and policies. Websites represent domains; pages represent URL paths within a domain. Scripts are detected automatically; policies are customer-defined CSP rules.

**Script authorization.** Detected scripts have an `authorization_status` (`authorized` or `unauthorized`). Scripts have `current_hash` and `authorized_hash` fields for tracking content integrity.

**Content Security Policy management.** Policies define CSP directives (e.g., `script-src`, `style-src`) and operate in `report` mode (collect violations without blocking) or `enforce` mode (block violations). Violation reports are collected per-policy.

**Security header monitoring.** CSP tracks security headers observed on pages and records change events when headers are added, removed, or modified.

## Websites

| Action         | Method   | Endpoint                                           |
| -------------- | -------- | -------------------------------------------------- |
| List websites  | `GET`    | `/client-side-protection/v1/websites`              |
| Create website | `POST`   | `/client-side-protection/v1/websites`              |
| Get website    | `GET`    | `/client-side-protection/v1/websites/{website_id}` |
| Update website | `PATCH`  | `/client-side-protection/v1/websites/{website_id}` |
| Delete website | `DELETE` | `/client-side-protection/v1/websites/{website_id}` |

Create requires `domain`. Delete removes all associated pages, scripts, and policies. List supports `limit` and `page` pagination.

## Pages

| Action      | Method   | Endpoint                                     |
| ----------- | -------- | -------------------------------------------- |
| List pages  | `GET`    | `/client-side-protection/v1/pages`           |
| Create page | `POST`   | `/client-side-protection/v1/pages`           |
| Get page    | `GET`    | `/client-side-protection/v1/pages/{page_id}` |
| Update page | `PATCH`  | `/client-side-protection/v1/pages/{page_id}` |
| Delete page | `DELETE` | `/client-side-protection/v1/pages/{page_id}` |

Create requires `website_id` and `name`. Optional fields: `description`, `paths` (URL paths to monitor), `notifications` (array with `type: "mailinglist"` and `config.address`). List accepts optional `website_id` query filter.

## Scripts

| Action        | Method  | Endpoint                                                         |
| ------------- | ------- | ---------------------------------------------------------------- |
| List scripts  | `GET`   | `/client-side-protection/v1/pages/{page_id}/scripts`             |
| Get script    | `GET`   | `/client-side-protection/v1/pages/{page_id}/scripts/{script_id}` |
| Update script | `PATCH` | `/client-side-protection/v1/pages/{page_id}/scripts/{script_id}` |

Scripts are detected automatically -- no create/delete endpoints. Update accepts `authorization_status` (`authorized`/`unauthorized`), `justification`, and `authorized_hash`.

Script fields: `id`, `page_id`, `source`, `urls`, `first_seen_at`, `last_seen_at`, `current_hash`, `authorized_hash`, `authorization_status`, `authorized_at`, `justification`.

## Policies

| Action        | Method  | Endpoint                                                                  |
| ------------- | ------- | ------------------------------------------------------------------------- |
| List policies | `GET`   | `/client-side-protection/v1/pages/{page_id}/policies`                     |
| Create policy | `POST`  | `/client-side-protection/v1/pages/{page_id}/policies`                     |
| Get policy    | `GET`   | `/client-side-protection/v1/pages/{page_id}/policies/{policy_id}`         |
| Update policy | `PATCH` | `/client-side-protection/v1/pages/{page_id}/policies/{policy_id}`         |
| List reports  | `GET`   | `/client-side-protection/v1/pages/{page_id}/policies/{policy_id}/reports` |

Create requires `name` and `mode` (`report` or `enforce`). Optional `directives` array with `name` (e.g., `script-src`) and `values` (array of allowed sources). Reports are CSP violation records with `blocked_uri`, `document_uri`, and `violated_directive`.

## Headers & Events

| Action       | Method | Endpoint                                             |
| ------------ | ------ | ---------------------------------------------------- |
| List headers | `GET`  | `/client-side-protection/v1/pages/{page_id}/headers` |
| List events  | `GET`  | `/client-side-protection/v1/pages/{page_id}/events`  |

Headers show security headers currently observed on the page. Events track header changes over time (`header_name`, `old_value`, `new_value`, `changed_at`).

## Documentation

URLs below serve Markdown (use the `Accept: text/markdown` header).

| Source                           | URL                                                                                                     |
| -------------------------------- | ------------------------------------------------------------------------------------------------------- |
| How Client-Side Protection works | `https://www.fastly.com/documentation/guides/security/client-side-protection/how-it-works`              |
| Script inventory monitoring      | `https://www.fastly.com/documentation/guides/security/client-side-protection/monitoring-your-inventory` |
| Policy management                | `https://www.fastly.com/documentation/guides/security/client-side-protection/managing-your-policy`      |
| API reference                    | `https://www.fastly.com/documentation/reference/api/security/client-side-protection`                    |

For general Fastly platform guidance, documentation source index, and other specialized skills, see the `fastly` skill.
