import { LightningElement } from 'lwc';
import CURRENCY from '@salesforce/i18n/currency';
import getFilterOptions from '@salesforce/apex/ServiceRequestConsoleController.getFilterOptions';
import getServiceRequests from '@salesforce/apex/ServiceRequestConsoleController.getServiceRequests';

const SEARCH_DEBOUNCE_MS = 300;
const MIN_SEARCH_LENGTH = 2;
const ALL = 'ALL';
const DEFAULT_PAGE_SIZE = 25;
const PAGE_SIZE_OPTIONS = [10, 25, 50, 100].map((size) => ({
    label: String(size),
    value: String(size)
}));
const CLOSED_STATUSES = ['Completed', 'Cancelled'];
const SMALL_SCREEN_QUERY = '(max-width: 48em)';
const DEFAULT_SORT = { field: 'requestedDate', direction: 'desc' };
const DATE_FORMAT = { year: 'numeric', month: 'short', day: '2-digit' };

// Table column field name -> field the server is allowed to sort by.
const SORT_FIELD_BY_COLUMN = {
    recordUrl: 'Name',
    subject: 'Subject__c',
    propertyName: 'Property__r.Name',
    technicianLabel: 'Technician__r.Name',
    status: 'Status__c',
    priority: 'Priority__c',
    requestedDate: 'Requested_Date__c',
    scheduledDate: 'Scheduled_Date__c',
    estimatedCost: 'Estimated_Cost__c'
};

const COLUMNS = [
    {
        label: 'SR Number',
        fieldName: 'recordUrl',
        type: 'url',
        sortable: true,
        initialWidth: 130,
        typeAttributes: { label: { fieldName: 'name' }, target: '_self' }
    },
    {
        label: 'Subject',
        fieldName: 'subject',
        type: 'text',
        sortable: true,
        wrapText: true,
        initialWidth: 260,
        cellAttributes: { class: { fieldName: 'subjectClass' } }
    },
    { label: 'Property', fieldName: 'propertyName', type: 'text', sortable: true, initialWidth: 220 },
    { label: 'Customer', fieldName: 'customerName', type: 'text', initialWidth: 170 },
    { label: 'Technician', fieldName: 'technicianLabel', type: 'text', sortable: true, initialWidth: 150 },
    { label: 'Status', fieldName: 'status', type: 'text', sortable: true, initialWidth: 120 },
    {
        label: 'Priority',
        fieldName: 'priority',
        type: 'text',
        sortable: true,
        initialWidth: 120,
        cellAttributes: {
            class: { fieldName: 'priorityClass' },
            iconName: { fieldName: 'priorityIcon' },
            iconPosition: 'left'
        }
    },
    { label: 'Category', fieldName: 'category', type: 'text', initialWidth: 110 },
    {
        label: 'Requested Date',
        fieldName: 'requestedDate',
        type: 'date-local',
        sortable: true,
        initialWidth: 140,
        typeAttributes: DATE_FORMAT
    },
    {
        label: 'Scheduled Date',
        fieldName: 'scheduledDate',
        type: 'date-local',
        sortable: true,
        initialWidth: 140,
        typeAttributes: DATE_FORMAT
    },
    {
        label: 'Estimated Cost',
        fieldName: 'estimatedCost',
        type: 'currency',
        sortable: true,
        initialWidth: 140,
        typeAttributes: { currencyCode: CURRENCY },
        cellAttributes: { alignment: 'left' }
    },
    {
        label: 'Overdue',
        fieldName: 'overdueLabel',
        type: 'text',
        initialWidth: 120,
        cellAttributes: {
            class: { fieldName: 'overdueClass' },
            iconName: { fieldName: 'overdueIcon' },
            iconPosition: 'left'
        }
    }
];

export default class ServiceRequestConsole extends LightningElement {
    // ---- Criteria (everything the server needs) ----
    searchInput = '';
    searchTerm = '';
    statuses = [];
    priority = ALL;
    category = ALL;
    dateFrom = null;
    dateTo = null;
    technicianId = null;
    propertyId = null;
    overdueOnly = false;
    sortedBy = DEFAULT_SORT.field;
    sortedDirection = DEFAULT_SORT.direction;
    pageNumber = 1;
    pageSize = DEFAULT_PAGE_SIZE;

    // ---- Server results ----
    rows = [];
    totalCount = 0;
    totalPages = 1;
    maxReachablePage = 1;
    isTruncated = false;
    hasAnyRecords = false;
    canViewCost = false;

    // ---- Picklist metadata (loaded once) ----
    statusOptions = [];
    priorityOptions = [];
    categoryOptions = [];
    defaultStatuses = [];

    // ---- UI state ----
    isFirstLoad = true;
    isLoading = false;
    hasError = false;
    filtersExpanded = true;
    pageSizeOptions = PAGE_SIZE_OPTIONS;

    _debounceTimer;
    _latestRequestId = 0;
    _optionsLoaded = false;

    connectedCallback() {
        this.filtersExpanded = !this.isSmallScreen();
        this.initialize();
    }

    disconnectedCallback() {
        clearTimeout(this._debounceTimer);
    }

    // ------------------------------------------------------------------
    // Loading
    // ------------------------------------------------------------------
    async initialize() {
        this.isLoading = true;
        this.hasError = false;
        try {
            const options = await getFilterOptions();
            this.statusOptions = options.statuses;
            this.priorityOptions = [{ label: 'All', value: ALL }, ...options.priorities];
            this.categoryOptions = [{ label: 'All', value: ALL }, ...options.categories];
            this.canViewCost = options.canViewEstimatedCost;
            this.defaultStatuses = options.statuses
                .map((option) => option.value)
                .filter((value) => !CLOSED_STATUSES.includes(value));
            this.statuses = [...this.defaultStatuses];
            this._optionsLoaded = true;
        } catch (error) {
            this.hasError = true;
            this.isFirstLoad = false;
            this.isLoading = false;
            return;
        }
        await this.loadData();
    }

    async loadData() {
        if (this.hasDateError) {
            // Invalid range: do not call the server, and ignore anything still in flight.
            this._latestRequestId++;
            this.isLoading = false;
            return;
        }
        const requestId = ++this._latestRequestId;
        this.isLoading = true;
        this.hasError = false;
        try {
            const result = await getServiceRequests({ request: this.buildRequest() });
            if (requestId !== this._latestRequestId) {
                return; // a newer request has been sent; drop this stale response
            }
            this.applyResult(result);
        } catch (error) {
            if (requestId === this._latestRequestId) {
                this.hasError = true; // fixed, friendly text is shown; error details stay hidden
            }
        } finally {
            if (requestId === this._latestRequestId) {
                this.isLoading = false;
                this.isFirstLoad = false;
            }
        }
    }

    buildRequest() {
        return {
            searchTerm: this.searchTerm || null,
            statuses: this.statuses,
            priority: this.priority === ALL ? null : this.priority,
            category: this.category === ALL ? null : this.category,
            requestedFrom: this.dateFrom || null,
            requestedTo: this.dateTo || null,
            technicianId: this.technicianId,
            propertyId: this.propertyId,
            overdueOnly: this.overdueOnly,
            sortField: SORT_FIELD_BY_COLUMN[this.sortedBy],
            sortDirection: this.sortedDirection,
            pageNumber: this.pageNumber,
            pageSize: this.pageSize
        };
    }

    applyResult(result) {
        this.rows = result.records.map((record) => this.toRow(record));
        this.totalCount = result.totalCount;
        this.totalPages = result.totalPages;
        this.maxReachablePage = result.maxReachablePage;
        this.isTruncated = result.isTruncated;
        this.hasAnyRecords = result.hasAnyRecords;
        this.canViewCost = result.canViewEstimatedCost;
        this.pageNumber = result.pageNumber; // server is the source of truth
    }

    toRow(record) {
        const isCritical = record.priority === 'Critical';
        return {
            ...record,
            recordUrl: `/lightning/r/Service_Request__c/${record.id}/view`,
            technicianLabel: record.technicianName || 'Unassigned',
            subjectClass: record.isOverdue ? 'slds-text-color_error' : '',
            priorityClass: isCritical ? 'slds-text-color_error slds-text-title_bold' : '',
            priorityIcon: isCritical ? 'utility:warning' : undefined,
            overdueLabel: record.isOverdue ? 'Overdue' : '',
            overdueClass: 'slds-text-color_error slds-text-title_bold',
            overdueIcon: record.isOverdue ? 'utility:clock' : undefined
        };
    }

    // ------------------------------------------------------------------
    // Event handlers: every criteria change resets to page 1
    // ------------------------------------------------------------------
    handleSearchChange(event) {
        this.searchInput = event.target.value;
        clearTimeout(this._debounceTimer);
        this._debounceTimer = setTimeout(() => this.commitSearch(), SEARCH_DEBOUNCE_MS);
    }

    commitSearch() {
        const trimmed = (this.searchInput || '').trim();
        const effective = trimmed.length >= MIN_SEARCH_LENGTH ? trimmed : '';
        if (effective === this.searchTerm) {
            return; // nothing effectively changed (e.g. typing the first character)
        }
        this.searchTerm = effective;
        this.resetToFirstPageAndLoad();
    }

    handleStatusChange(event) {
        this.statuses = event.detail.value;
        this.resetToFirstPageAndLoad();
    }

    handlePriorityChange(event) {
        this.priority = event.detail.value;
        this.resetToFirstPageAndLoad();
    }

    handleCategoryChange(event) {
        this.category = event.detail.value;
        this.resetToFirstPageAndLoad();
    }

    handleDateFromChange(event) {
        this.dateFrom = event.detail.value || null;
        this.syncDateValidity();
        this.resetToFirstPageAndLoad();
    }

    handleDateToChange(event) {
        this.dateTo = event.detail.value || null;
        this.syncDateValidity();
        this.resetToFirstPageAndLoad();
    }

    handleTechnicianChange(event) {
        const recordId = event.detail.recordId || null;
        if (recordId !== this.technicianId) {
            this.technicianId = recordId;
            this.resetToFirstPageAndLoad();
        }
    }

    handlePropertyChange(event) {
        const recordId = event.detail.recordId || null;
        if (recordId !== this.propertyId) {
            this.propertyId = recordId;
            this.resetToFirstPageAndLoad();
        }
    }

    handleOverdueChange(event) {
        this.overdueOnly = event.detail.checked;
        this.resetToFirstPageAndLoad();
    }

    handleSort(event) {
        this.sortedBy = event.detail.fieldName;
        this.sortedDirection = event.detail.sortDirection;
        this.resetToFirstPageAndLoad();
    }

    handlePageSizeChange(event) {
        this.pageSize = parseInt(event.detail.value, 10);
        this.resetToFirstPageAndLoad();
    }

    handleFirst() {
        this.goToPage(1);
    }

    handlePrevious() {
        this.goToPage(this.pageNumber - 1);
    }

    handleNext() {
        this.goToPage(this.pageNumber + 1);
    }

    handleLast() {
        this.goToPage(this.totalPages);
    }

    handleToggleFilters() {
        this.filtersExpanded = !this.filtersExpanded;
    }

    handleRetry() {
        if (this._optionsLoaded) {
            this.loadData();
        } else {
            this.initialize();
        }
    }

    handleClearAll() {
        clearTimeout(this._debounceTimer);
        this.searchInput = '';
        this.searchTerm = '';
        this.statuses = [...this.defaultStatuses];
        this.priority = ALL;
        this.category = ALL;
        this.dateFrom = null;
        this.dateTo = null;
        this.technicianId = null;
        this.propertyId = null;
        this.overdueOnly = false;
        this.sortedBy = DEFAULT_SORT.field;
        this.sortedDirection = DEFAULT_SORT.direction;
        this.pageNumber = 1;
        this.template
            .querySelectorAll('lightning-record-picker')
            .forEach((picker) => picker.clearSelection());
        this.syncDateValidity();
        this.loadData();
    }

    resetToFirstPageAndLoad() {
        this.pageNumber = 1;
        this.loadData();
    }

    goToPage(page) {
        if (this.isLoading || page < 1 || page > this.maxReachablePage) {
            return;
        }
        this.pageNumber = page;
        this.loadData();
    }

    // ------------------------------------------------------------------
    // Validation
    // ------------------------------------------------------------------
    get hasDateError() {
        return Boolean(this.dateFrom && this.dateTo && this.dateFrom > this.dateTo);
    }

    syncDateValidity() {
        const fromInput = this.template.querySelector('[data-id="dateFrom"]');
        if (!fromInput) {
            return;
        }
        fromInput.setCustomValidity(
            this.hasDateError ? '"From" date must be on or before the "To" date.' : ''
        );
        fromInput.reportValidity();
    }

    isSmallScreen() {
        return typeof window !== 'undefined' && window.matchMedia(SMALL_SCREEN_QUERY).matches;
    }

    // ------------------------------------------------------------------
    // Template getters
    // ------------------------------------------------------------------
    get columns() {
        return this.canViewCost ? COLUMNS : COLUMNS.filter((col) => col.fieldName !== 'estimatedCost');
    }

    get showInitialSpinner() {
        return this.isFirstLoad && this.isLoading;
    }

    get showError() {
        return this.hasError && !this.showInitialSpinner;
    }

    get showEmpty() {
        return !this.hasError && !this.isFirstLoad && this.totalCount === 0;
    }

    get showTable() {
        return !this.hasError && !this.isFirstLoad && this.totalCount > 0;
    }

    get hasNoDataAtAll() {
        return !this.hasAnyRecords;
    }

    get statusFilterActive() {
        const current = [...this.statuses].sort().join('|');
        const defaults = [...this.defaultStatuses].sort().join('|');
        return current !== defaults;
    }

    get activeFilterCount() {
        return [
            this.statusFilterActive,
            this.priority !== ALL,
            this.category !== ALL,
            Boolean(this.dateFrom),
            Boolean(this.dateTo),
            Boolean(this.technicianId),
            Boolean(this.propertyId),
            this.overdueOnly
        ].filter(Boolean).length;
    }

    get filtersLabel() {
        return `Filters (${this.activeFilterCount})`;
    }

    get filtersIcon() {
        return this.filtersExpanded ? 'utility:chevronup' : 'utility:chevrondown';
    }

    get pageSizeValue() {
        return String(this.pageSize);
    }

    get pageLabel() {
        return `Page ${this.pageNumber} of ${this.totalPages}`;
    }

    get rangeLabel() {
        if (this.totalCount === 0) {
            return '0 service requests';
        }
        const start = (this.pageNumber - 1) * this.pageSize + 1;
        const end = start + this.rows.length - 1;
        return `Showing ${start}\u2013${end} of ${this.totalCount} service requests`;
    }

    get truncationMessage() {
        return `Salesforce limits how deep paging can go. Only pages 1 to ${this.maxReachablePage} are available for these ${this.totalCount} results. Narrow your search or filters to see the rest.`;
    }

    get disableFirstPrevious() {
        return this.isLoading || this.pageNumber <= 1;
    }

    get disableNext() {
        return this.isLoading || this.pageNumber >= this.maxReachablePage;
    }

    get disableLast() {
        return this.isLoading || this.isTruncated || this.pageNumber >= this.totalPages;
    }

    get disablePageSize() {
        return this.isLoading;
    }

    get showOverlaySpinner() {
        return this.isLoading && !this.showInitialSpinner;
    }
}
