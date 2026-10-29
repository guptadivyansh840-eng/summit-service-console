import { LightningElement, wire } from 'lwc';

import getServiceRequests
    from '@salesforce/apex/ServiceRequestConsoleController.getServiceRequests';
import assignTechnician
    from '@salesforce/apex/ServiceRequestConsoleController.assignTechnician';

import { getPicklistValues, getObjectInfo }
    from 'lightning/uiObjectInfoApi';

import USER_ID from '@salesforce/user/Id';

import { getRecord, getFieldValue }
    from 'lightning/uiRecordApi';

import { ShowToastEvent }
    from 'lightning/platformShowToastEvent';
    import { refreshApex } from '@salesforce/apex';


export default class ServiceRequestConsole extends LightningElement {

    // -------------------------
    // Datatable Columns
    // -------------------------

    columns = [
        { label: 'SR Number', fieldName: 'Name' },
        { label: 'Subject', fieldName: 'Subject__c' },
        { label: 'Status', fieldName: 'Status__c' },
        { label: 'Priority', fieldName: 'Priority__c' },
        { label: 'Category', fieldName: 'Category__c' },
        { label: 'Requested Date', fieldName: 'Requested_Date__c', sortable: true },
        { label: 'Property', fieldName: 'PropertyName'},
        {label : 'Technician Name' , fieldName: 'TechnicianAssigned'}
     
    ];

    // -------------------------
    // Technician Assignment
    // -------------------------

    selectedRowsId = [];
    assignmentTechnicianId = null;
    isAssigning = false;

    activeTechnicianFilter = {
        criteria: [
            {
                fieldPath: 'Active__c',
                operator: 'eq',
                value: true
            }
        ]
    };

    // -------------------------
    // Technician Access
    // -------------------------

    isTechnician = false;

    @wire(getRecord, {
        recordId: USER_ID,
        fields: ['User.Department']
    })
    wiredUser({ data, error }) {
        if (data) {
            const department = getFieldValue(
                data,
                'User.Department'
            );

            this.isTechnician = department === 'Technician';

        } else if (error) {
            this.isTechnician = false;
        }
    }

    // -------------------------
    // Service Request Data
    // -------------------------

    serviceRequests = [];
    error;

    currentPage = 1;
    pageSize = 10;

    totalRecords = 0;
    currentPageRecords = [];
    totalPages = 0;
    wiredServiceRequestResult;

    @wire(getServiceRequests, {
        statuses: '$selectedStatuses',
        priority: '$selectedPriority',
        category: '$selectedCategory',
        requestedDateFrom: '$requestedDateFrom',
        requestedDateTo: '$requestedDateTo',
        overdueOnly: '$showOverdueOnly',
        technicianId: '$selectedTechnicianId',
        propertyId: '$selectedPropertyId',
        searchKey: '$searchKey',
        sortDirection: '$sortDirection'
    })
    wiredServiceRequests(result) {
        this.wiredServiceRequestResult = result;
        

        const {data ,error} = result;
       
        if (data) {

            this.serviceRequests = data.map(request => ({
                ...request,
                PropertyName: request.Property__r
                    ? request.Property__r.Name
                    : '',
                TechnicianAssigned: request.Technician__r? request.Technician__r.Name : ''
            }));

            this.totalRecords = this.serviceRequests.length;

            this.totalPages = Math.ceil(
                this.totalRecords / this.pageSize
            );

            this.currentPage = 1;

            this.currentPageRecords =
                this.serviceRequests.slice(0, this.pageSize);

            this.error = undefined;

        } else if (error) {
            console.log(
                'FULL APEX ERROR:',
                JSON.stringify(error)
            );

            this.error = error;
            this.serviceRequests = [];
            this.totalRecords = 0;
            this.totalPages = 0;
            this.currentPageRecords = [];
        }
    }

    // -------------------------
    // Category Picklist
    // -------------------------

    @wire(getObjectInfo, {
        objectApiName: 'Service_Request__c'
    })
    objectInfo;

    @wire(getPicklistValues, {
        recordTypeId: '$objectInfo.data.defaultRecordTypeId',
        fieldApiName: 'Service_Request__c.Category__c'
    })
    categoryPicklist;

    get categoryOptions() {
        if (this.categoryPicklist.data) {
            return this.categoryPicklist.data.values;
        }

        return [];
    }

    // -------------------------
    // Status Filter
    // -------------------------

    selectedStatuses = [];

    statusOptions = [
        { label: 'New', value: 'New' },
        { label: 'Scheduled', value: 'Scheduled' },
        { label: 'In Progress', value: 'In Progress' },
        { label: 'On Hold', value: 'On Hold' },
        { label: 'Completed', value: 'Completed' },
        { label: 'Cancelled', value: 'Cancelled' }
    ];

    handleStatusChange(event) {
        this.selectedStatuses = event.detail.value;
        this.currentPage = 1;
    }

    // -------------------------
    // Priority Filter
    // -------------------------

    selectedPriority = '';

    priorityOptions = [
        { label: 'Critical', value: 'Critical' },
        { label: 'High', value: 'High' },
        { label: 'Medium', value: 'Medium' },
        { label: 'Low', value: 'Low' }
    ];

    handlePriorityChange(event) {
        this.selectedPriority = event.detail.value;
        this.currentPage = 1;
    }

    // -------------------------
    // Category Filter
    // -------------------------

    selectedCategory = '';

    handleCategoryChange(event) {
        this.selectedCategory = event.detail.value;
        this.currentPage = 1;
    }

    // -------------------------
    // Requested Date Filters
    // -------------------------

    requestedDateFrom = null;
    requestedDateTo = null;

    handleDateFromChange(event) {
        this.requestedDateFrom = event.detail.value;
        this.currentPage = 1;
    }

    handleDateToChange(event) {
        this.requestedDateTo = event.detail.value;
        this.currentPage = 1;
    }

    // -------------------------
    // Overdue Filter
    // -------------------------

    showOverdueOnly = false;

    handleOverdueChange(event) {
        this.showOverdueOnly = event.target.checked;
        this.currentPage = 1;
    }

    // -------------------------
    // Technician Filter
    // -------------------------

    selectedTechnicianId = null;

    handleTechnicianChange(event) {
        this.selectedTechnicianId =
            event.detail.recordId || null;

        this.currentPage = 1;
    }

    // -------------------------
    // Property Filter
    // -------------------------

    selectedPropertyId = null;

    handlePropertyChange(event) {
        this.selectedPropertyId =
            event.detail.recordId || null;

        this.currentPage = 1;
    }

    // -------------------------
    // Search With Debounce
    // -------------------------

    searchTerm = '';
    searchKey = '';
    searchTimeout;

    handleSearchChange(event) {
        this.searchTerm = event.target.value;

        clearTimeout(this.searchTimeout);

        this.searchTimeout = setTimeout(() => {
            const value = this.searchTerm.trim();

            if (value.length >= 2) {
                this.searchKey = value;
            } else {
                this.searchKey = '';
            }

            this.currentPage = 1;
        }, 300);
    }

    disconnectedCallback() {
        clearTimeout(this.searchTimeout);
    }

    // -------------------------
    // Clear All Filters
    // -------------------------

    handleClearAll() {
        clearTimeout(this.searchTimeout);

        this.selectedStatuses = [];
        this.selectedPriority = '';
        this.selectedCategory = '';

        this.requestedDateFrom = null;
        this.requestedDateTo = null;

        this.showOverdueOnly = false;
        this.selectedTechnicianId = null;
        this.selectedPropertyId = null;

        this.searchTerm = '';
        this.searchKey = '';

        this.sortDirection = 'desc';
        this.currentPage = 1;
    }

    // -------------------------
    // Pagination
    // -------------------------

    handleNext() {
        if (this.currentPage >= this.totalPages) {
            return;
        }

        this.currentPage++;

        const start =
            (this.currentPage - 1) * this.pageSize;

        const end = start + this.pageSize;

        this.currentPageRecords =
            this.serviceRequests.slice(start, end);
    }

    handlePrevious() {
        if (this.currentPage <= 1) {
            return;
        }

        this.currentPage--;

        const start =
            (this.currentPage - 1) * this.pageSize;

        const end = start + this.pageSize;

        this.currentPageRecords =
            this.serviceRequests.slice(start, end);
    }

    // -------------------------
    // Sorting
    // -------------------------

    sortDirection = 'desc';

    handleSort(event) {
        this.sortDirection = event.detail.sortDirection;
        this.currentPage = 1;
    }

    // -------------------------
    // Select Datatable Rows
    // -------------------------

    handleRowSelection(event) {
        this.selectedRowsId =
            event.detail.selectedRows.map(row => row.Id);

        console.log(
            'Selected Service Request IDs:',
            JSON.stringify(this.selectedRowsId)
        );
    }

    // -------------------------
    // Choose Assignment Technician
    // -------------------------

    handleAssignmentTechnicianChange(event) {
        this.assignmentTechnicianId =
            event.detail.recordId || null;

        console.log(
            'Technician selected for assignment:',
            this.assignmentTechnicianId
        );
    }

    // -------------------------
    // Bulk Technician Assignment
    // -------------------------

    async handleAssignClick() {
        if (
            this.isTechnician ||
            this.selectedRowsId.length === 0 ||
            !this.assignmentTechnicianId
        ) {
            return;
        }

        this.isAssigning = true;

        try {
            await assignTechnician({
                serviceRequestIds: this.selectedRowsId,
                technicianId: this.assignmentTechnicianId
            });
            await refreshApex(this.wiredServiceRequestResult);

        

        } catch (error) {
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Assignment Failed',
                    message:
                        error?.body?.message ||
                        'An error occurred while assigning the technician.',
                    variant: 'error'
                })
            );

        } finally {
            this.isAssigning = false;
        }
    }

    get disableAssignButton() {
        return (
            this.isTechnician ||
            this.isAssigning ||
            this.selectedRowsId.length === 0 ||
            !this.assignmentTechnicianId
        );
    }

    // -------------------------
    // Pagination Information
    // -------------------------

    get pageInfo() {
        return `Page ${this.currentPage} of ${this.totalPages}`;
    }

    get disablePrevious() {
        return this.currentPage <= 1;
    }

    get disableNext() {
        return (
            this.totalPages === 0 ||
            this.currentPage >= this.totalPages
        );
    }
}
