# Service Request Console (Summit Facility Services)

A Lightning Web Component backed by an Apex controller that lets dispatchers and managers **find, search, filter and sort service requests** inside Salesforce. Paging, sorting, search and filters all run **on the server** and work together. The repo also contains the data model (3 custom objects), a permission set, sample data and Apex tests.

## Prerequisites

- Salesforce CLI (`sf`) v2 or later: `sf --version`
- A **Dev Hub** (for a scratch org) **or** a free Developer Edition org
- Node.js 18+ (only needed for lint / prettier)

## Quick start (about 10 minutes)

### Option A: scratch org

```bash
sf org login web --set-default-dev-hub --alias devhub
sf org create scratch --definition-file config/project-scratch-def.json --alias summit --set-default --duration-days 14
sf project deploy start
sf org assign permset --name Service_Request_Console_User
sf apex run --file scripts/apex/load-sample-data.apex
sf org open --path /lightning/app/standard__Dispatch  # or open the app from the App Launcher
```

### Option B: Developer Edition org

```bash
sf org login web --set-default --alias summit
sf project deploy start
sf org assign permset --name Service_Request_Console_User
sf apex run --file scripts/apex/load-sample-data.apex
sf org open
```

Then open the **App Launcher**, choose **Summit Dispatch**, and open the **Service Request Console** tab.

> The permission set is mainly for non-admin users. System Administrators can already see everything, so to test the "restricted user" behaviour (AC-24, AC-25) create a second user with a standard profile, assign only `Service_Request_Console_User`, and share a Property with them (see below).

### Remove the sample data

```bash
sf apex run --file scripts/apex/cleanup-sample-data.apex
```

Sample records are identified by the fixed account names and the `@summitdemo.example` technician e-mail domain, so your own data is untouched. Deleting a Property also deletes its Service Requests (master-detail).

### What the sample data contains

5 accounts, 15 properties, 8 technicians (1 inactive), **330 service requests** across the last 12 months. About 68 are New and unassigned, about 100 are overdue, some have no scheduled date or cost (blank-sort testing), and a few subjects contain `%`, `'`, `_` and `\` (search-safety testing).

## Running the Apex tests

```bash
sf apex run test --test-level RunLocalTests --code-coverage --result-format human --wait 10
```

Tests live in `ServiceRequestConsoleControllerTest` and use `TestDataFactory` (no `SeeAllData`). They cover the default load, each filter, a combined search + filters + sort scenario, sort order (including Priority and blank values), pagination boundaries, injection-style input, invalid sort / page size, sharing, field-level security, object-access errors and a 250-record bulk case.

## Lint and format

```bash
npm install
npm run lint
npm run prettier:verify
```

## Project layout

```
force-app/main/default/
  objects/        Property__c, Technician__c, Service_Request__c (+ fields, validation rules)
  layouts/        one simple layout per object
  classes/        ServiceRequestConsoleController, ...Test, TestDataFactory
  lwc/serviceRequestConsole/
  flexipages/     Service_Request_Console (App Page)
  tabs/           Service_Request_Console + the three object tabs
  applications/   Summit_Dispatch
  permissionsets/ Service_Request_Console_User
scripts/apex/     load-sample-data.apex, cleanup-sample-data.apex
manifest/package.xml, config/project-scratch-def.json
```

## Design decisions

**Server-side pagination.** `getServiceRequests` runs one `COUNT()` query and one page query (`LIMIT` + `OFFSET`). The browser only ever receives one page plus the total, so the response size does not grow with the data. The server also returns `totalPages`, the page it actually served, and whether the data is truncated by the OFFSET limit. The client treats the server as the source of truth for the page number.

**Sorting.** The client sends a field key and a direction. The server maps the key through an **allow-list**; anything else (including `Name; DELETE`) falls back to `Requested_Date__c DESC`. Every query ends with `NULLS LAST` so blanks are last in both directions, plus `Name` as a tie-breaker so page boundaries are stable. Priority uses SOQL's picklist ordering, which follows the order defined in Setup (Critical, High, Medium, Low), so no extra field is needed. *Consequence: do not reorder the Priority picklist values.* This is noted in the field description.

**Search.** The input is trimmed, ignored below 2 characters, and capped at 100 characters. It becomes a **bind variable** used in `LIKE` conditions on SR Number, Subject, Property Name and Technician Name. `%`, `_` and `\` are escaped so they behave as plain text, so `p_mp` does not match `Pump`. The LWC debounces for 300 ms.

**Out-of-order responses.** Every request gets an incrementing id. A response that is not the latest is ignored, so a slow old response can never overwrite newer results.

**Filters.** Status (multi-select), Priority, Category, requested date range, Technician, Property and Overdue only. All use bind variables. Picklist values and defaults come from the org metadata via `getFilterOptions` (called **once**), so a new Category value shows up without code changes. Malformed or wrong-type record Ids are ignored. If *From* is after *To*, an inline error is shown and **no server call is made**.

**Security.**
- The class is `with sharing` and every query runs with `AccessLevel.USER_MODE`, so record sharing, object access and FLS are enforced by the platform.
- `Estimated_Cost__c` is only added to the `SELECT` when the user can read it. Otherwise the value is `null`, the column is hidden, and sorting by it falls back to the default sort.
- No user input is concatenated into SOQL. Page size, sort field, sort direction and picklist values are validated on the server.
- Errors are caught and turned into one fixed friendly message. The real exception goes to the debug log only. The LWC also shows fixed text, never the error body.

**UI states.** First load shows a spinner in the table area. Later loads keep the rows visible, show an overlay spinner and disable paging controls. Separate messages exist for "no matches" (with a Clear button), "no data at all", and errors (with Try again). Critical priority and overdue rows use an **icon + text label + colour**, so colour is never the only signal. The range text is an `aria-live` region and the datatable announces sort state.

**Responsive.** The filter panel collapses by default at small widths and is toggled with an `aria-expanded` button showing "Filters (n)". The datatable scrolls horizontally on phones.

## Assumptions (please confirm with Atul)

1. **Account read access.** The Customer column needs `Account` read access, so the permission set grants Read on Account as well as the three custom objects.
2. **Required fields in the permission set.** Salesforce does not allow required fields (`Subject__c`, `Requested_Date__c`, `Property__c`, `Customer__c`, `Name`) in a permission set, because they are always visible with the object. So only optional fields are listed. `Estimated_Cost__c` is left out on purpose.
3. **Status filter with nothing selected** means "no status filter" (all statuses), not "show nothing".
4. **Requested page beyond the range** returns **page 1**, consistent with FR-7.4.
5. **Overdue** is computed by the formula exactly as specified in the brief (Scheduled Date before today and not Completed/Cancelled), so a "New" request with a past scheduled date also counts.
6. **Record links** use `/lightning/r/Service_Request__c/<id>/view`, which works in Lightning Experience and the mobile app without any org-specific URL.
7. **Tab icon.** The tabs use the `Custom70: Handsaw` icon. If your org rejects it at deploy time, replace the `<motif>` value in `force-app/main/default/tabs/*.tab-meta.xml` with any valid icon.
8. **External sharing model.** Only the internal org-wide defaults are set in metadata (Property Private, Technician Public Read Only, Service Request Controlled by Parent).

## Known limitations

- **2,000-row OFFSET limit (FR-3.7).** SOQL `OFFSET` cannot exceed 2,000. The server computes `maxReachablePage` for the current page size (for example page 81 at 25 rows). Beyond that, Next is disabled, **Last is disabled**, and a message asks the user to narrow the search or filters. A page number past the limit falls back to page 1. A full solution is *keyset (cursor) paging*: sort by the chosen field plus `Name`, remember the last row's sort values, and query `WHERE (sortField, Name) > (:lastValue, :lastName)`. The trade-offs are that "jump to page N" and "Last" become hard, null handling is more complex, and every sortable field needs its own comparison logic.
- Sorting by Status uses picklist order (as defined in Setup), not alphabetical.
- Search is a plain `LIKE '%term%'` on four fields. That is fine for tens of thousands of rows, but beyond that it should move to SOSL or an indexed search field.
- The permission set grants no create/edit rights because editing is out of scope.

## Handover note

**Done:** the data model (objects, fields, roll-up, three validation rules, layouts), permission set, Summit Dispatch app, tab and App Page; the Apex controller; the LWC with search, all filters, sorting, paging and loading/empty/error states; sample data scripts; and the Apex tests with a data factory.

**Not done / still to do before delivery:**
- Deploy to a real org and tick through the Section 9 checklist (the code was written without access to an org, so expect small fixes on first deploy).
- Screenshots in `docs/screenshots/` and the 3 to 5 minute demo video.
- Jest tests for the LWC and the other stretch goals (keyset paging, summary tiles, CSV export, saved view, inline edit, URL state, card layout, column chooser).

**With more time:** keyset paging past 2,000 rows, summary tiles that apply a filter on click, and Jest tests for debounce and page-reset logic.
