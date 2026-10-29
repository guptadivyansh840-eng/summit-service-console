@IsTest
private class ServiceRequestConsoleControllerTest {
    private static final String SUBJECT_CHILLER_A = 'Chiller unit not cooling';
    private static final String SUBJECT_LEAK = 'Leak at 50% capacity';
    private static final String SUBJECT_OBRIEN = 'O\'Brien\'s cafe AC';
    private static final String SUBJECT_PUMP = 'Pump_02 failure';
    private static final String SUBJECT_LIGHTS = 'Replace lobby lights';
    private static final String SUBJECT_CHILLER_F = 'Chiller maintenance';

  
    @TestSetup
    static void makeData() {
        Account acc = TestDataFactory.createAccount('Greenfield Realty', true);
        Property__c p1 = TestDataFactory.createProperty(acc.Id, 'Greenfield Tech Park - Tower B', false);
        Property__c p2 = TestDataFactory.createProperty(acc.Id, 'Lotus Hospital Annex', false);
        insert new List<Property__c>{ p1, p2 };

        Technician__c ravi = TestDataFactory.createTechnician('Ravi Menon', true, false);
        Technician__c anita = TestDataFactory.createTechnician('Anita Rao', true, false);
        insert new List<Technician__c>{ ravi, anita };

        Date today = Date.today();
        Service_Request__c a = TestDataFactory.buildServiceRequest(p1.Id, SUBJECT_CHILLER_A);
        a.Priority__c = 'High';
        a.Status__c = 'Scheduled';
        a.Technician__c = ravi.Id;
        a.Requested_Date__c = today.addDays(-30);
        a.Scheduled_Date__c = today.addDays(-5);
        a.Estimated_Cost__c = 1000;

        Service_Request__c b = TestDataFactory.buildServiceRequest(p1.Id, SUBJECT_LEAK);
        b.Priority__c = 'Critical';
        b.Category__c = 'Plumbing';
        b.Requested_Date__c = today.addDays(-10);

        Service_Request__c c = TestDataFactory.buildServiceRequest(p2.Id, SUBJECT_OBRIEN);
        c.Status__c = 'In Progress';
        c.Technician__c = anita.Id;
        c.Requested_Date__c = today.addDays(-60);
        c.Scheduled_Date__c = today.addDays(-50);
        c.Estimated_Cost__c = 250;

        Service_Request__c d = TestDataFactory.buildServiceRequest(p2.Id, SUBJECT_PUMP);
        d.Priority__c = 'Low';
        d.Category__c = 'Plumbing';
        d.Status__c = 'Completed';
        d.Technician__c = ravi.Id;
        d.Requested_Date__c = today.addDays(-90);
        d.Scheduled_Date__c = today.addDays(-85);
        d.Completed_Date__c = today.addDays(-80);
        d.Estimated_Cost__c = 500;

        Service_Request__c e = TestDataFactory.buildServiceRequest(p1.Id, SUBJECT_LIGHTS);
        e.Category__c = 'Electrical';
        e.Status__c = 'Cancelled';
        e.Requested_Date__c = today.addDays(-5);

        Service_Request__c f = TestDataFactory.buildServiceRequest(p2.Id, SUBJECT_CHILLER_F);
        f.Priority__c = 'High';
        f.Status__c = 'Scheduled';
        f.Technician__c = ravi.Id;
        f.Requested_Date__c = today.addDays(-20);
        f.Scheduled_Date__c = today.addDays(5);
        f.Estimated_Cost__c = 2000;

        insert new List<Service_Request__c>{ a, b, c, d, e, f };
    }

    // ------------------------------------------------------------------
    // Helpers
    // ------------------------------------------------------------------
    private static ServiceRequestConsoleController.QueryRequest req() {
        return new ServiceRequestConsoleController.QueryRequest();
    }

    private static ServiceRequestConsoleController.PageResult run(
        ServiceRequestConsoleController.QueryRequest request
    ) {
        return ServiceRequestConsoleController.getServiceRequests(request);
    }

    private static List<String> subjects(ServiceRequestConsoleController.PageResult result) {
        List<String> subjects = new List<String>();
        for (ServiceRequestConsoleController.RequestRow row : result.records) {
            subjects.add(row.subject);
        }
        return subjects;
    }

    private static Id idOfProperty(String name) {
        return [SELECT Id FROM Property__c WHERE Name = :name LIMIT 1].Id;
    }

    private static Id idOfTechnician(String name) {
        return [SELECT Id FROM Technician__c WHERE Name = :name LIMIT 1].Id;
    }

    // ------------------------------------------------------------------
    // Default load, picklists
    // ------------------------------------------------------------------
    @IsTest
    static void defaultLoadReturnsAllRowsNewestFirst() {
        ServiceRequestConsoleController.PageResult result = run(req());

        System.assertEquals(6, result.totalCount, 'All requests are counted');
        System.assertEquals(25, result.pageSize, 'Default page size is 25');
        System.assertEquals(1, result.pageNumber);
        System.assertEquals(1, result.totalPages);
        System.assertEquals(true, result.hasAnyRecords);
        System.assertEquals(
            new List<String>{
                SUBJECT_LIGHTS,
                SUBJECT_LEAK,
                SUBJECT_CHILLER_F,
                SUBJECT_CHILLER_A,
                SUBJECT_OBRIEN,
                SUBJECT_PUMP
            },
            subjects(result),
            'Default sort is Requested Date descending'
        );
        ServiceRequestConsoleController.RequestRow chillerF = result.records[2];
        System.assertEquals('Greenfield Realty', chillerF.customerName);
        System.assertEquals('Lotus Hospital Annex', chillerF.propertyName);
        System.assertEquals('Ravi Menon', chillerF.technicianName);
        System.assertEquals(Decimal.valueOf(2000), chillerF.estimatedCost, 'Admins can see cost');
    }

    @IsTest
    static void nullRequestFallsBackToDefaults() {
        ServiceRequestConsoleController.PageResult result = ServiceRequestConsoleController.getServiceRequests(
            null
        );
        System.assertEquals(6, result.totalCount);
        System.assertEquals(1, result.pageNumber);
    }

    @IsTest
    static void filterOptionsComeFromMetadata() {
        ServiceRequestConsoleController.FilterOptions options = ServiceRequestConsoleController.getFilterOptions();
        System.assertEquals('Critical', options.priorities[0].value, 'Priority keeps business order');
        System.assertEquals('Low', options.priorities[3].value);
        System.assertEquals(6, options.statuses.size());
        System.assertEquals(6, options.categories.size());
        System.assertEquals(true, options.canViewEstimatedCost);
    }

    // ------------------------------------------------------------------
    // Individual filters
    // ------------------------------------------------------------------
    @IsTest
    static void statusFilterMatchesAnySelectedValue() {
        ServiceRequestConsoleController.QueryRequest r = req();
        r.statuses = new List<String>{ 'New' };
        System.assertEquals(1, run(r).totalCount);

        r.statuses = new List<String>{ 'Completed', 'Cancelled' };
        System.assertEquals(
            new List<String>{ SUBJECT_LIGHTS, SUBJECT_PUMP },
            subjects(run(r))
        );

        r.statuses = new List<String>{ 'Scheduled', 'In Progress', 'Bogus' };
        System.assertEquals(3, run(r).totalCount, 'Unknown status values are ignored');
    }

    @IsTest
    static void priorityAndCategoryFilters() {
        ServiceRequestConsoleController.QueryRequest r = req();
        r.priority = 'High';
        System.assertEquals(2, run(r).totalCount);

        r = req();
        r.category = 'HVAC';
        System.assertEquals(3, run(r).totalCount);

        r = req();
        r.priority = 'ALL';
        r.category = 'NotACategory';
        System.assertEquals(6, run(r).totalCount, 'ALL / unknown values add no condition');
    }

    @IsTest
    static void requestedDateRangeIsInclusiveAndAcceptsOneSide() {
        Date today = Date.today();
        ServiceRequestConsoleController.QueryRequest r = req();
        r.requestedFrom = today.addDays(-30);
        r.requestedTo = today.addDays(-20);
        System.assertEquals(
            new List<String>{ SUBJECT_CHILLER_F, SUBJECT_CHILLER_A },
            subjects(run(r)),
            'Both boundary dates are included'
        );

        r = req();
        r.requestedFrom = today.addDays(-12);
        System.assertEquals(2, run(r).totalCount, 'From only');

        r = req();
        r.requestedTo = today.addDays(-70);
        System.assertEquals(new List<String>{ SUBJECT_PUMP }, subjects(run(r)), 'To only');
    }

    @IsTest
    static void technicianPropertyAndOverdueFilters() {
        ServiceRequestConsoleController.QueryRequest r = req();
        r.technicianId = idOfTechnician('Ravi Menon');
        System.assertEquals(3, run(r).totalCount);

        r = req();
        r.propertyId = idOfProperty('Lotus Hospital Annex');
        System.assertEquals(3, run(r).totalCount);

        r = req();
        r.overdueOnly = true;
        ServiceRequestConsoleController.PageResult overdue = run(r);
        System.assertEquals(
            new List<String>{ SUBJECT_CHILLER_A, SUBJECT_OBRIEN },
            subjects(overdue)
        );
        System.assertEquals(true, overdue.records[0].isOverdue);
    }

    @IsTest
    static void malformedOrWrongTypeIdsAreIgnored() {
        ServiceRequestConsoleController.QueryRequest r = req();
        r.technicianId = 'not-an-id';
        r.propertyId = idOfTechnician('Ravi Menon'); // valid Id but wrong object type
        System.assertEquals(6, run(r).totalCount, 'Invalid ids add no condition and cause no error');
    }

    // ------------------------------------------------------------------
    // Search
    // ------------------------------------------------------------------
    @IsTest
    static void searchIsPartialCaseInsensitiveAcrossFourFields() {
        ServiceRequestConsoleController.QueryRequest r = req();
        r.searchTerm = '  CHILLER ';
        System.assertEquals(2, run(r).totalCount, 'Subject, trimmed, ignoring case');

        r.searchTerm = 'tower b';
        System.assertEquals(3, run(r).totalCount, 'Property name');

        r.searchTerm = 'ravi';
        System.assertEquals(3, run(r).totalCount, 'Technician name');

        String srNumber = [SELECT Name FROM Service_Request__c WHERE Subject__c = :SUBJECT_PUMP].Name;
        r.searchTerm = srNumber.toLowerCase();
        System.assertEquals(new List<String>{ SUBJECT_PUMP }, subjects(run(r)), 'SR number');
    }

    @IsTest
    static void searchBelowMinimumLengthIsIgnored() {
        ServiceRequestConsoleController.QueryRequest r = req();
        r.searchTerm = 'x';
        System.assertEquals(6, run(r).totalCount);
        r.searchTerm = '   ';
        System.assertEquals(6, run(r).totalCount);
    }

    @IsTest
    static void searchTreatsSpecialCharactersAsPlainText() {
        ServiceRequestConsoleController.QueryRequest r = req();
        r.searchTerm = '50%';
        System.assertEquals(new List<String>{ SUBJECT_LEAK }, subjects(run(r)), 'Percent is literal');

        r.searchTerm = '%%';
        System.assertEquals(0, run(r).totalCount, 'No subject contains a literal %%; % is not a wildcard');

        r.searchTerm = 'Pump_02';
        System.assertEquals(new List<String>{ SUBJECT_PUMP }, subjects(run(r)), 'Underscore is literal');

        r.searchTerm = 'p_mp';
        System.assertEquals(0, run(r).totalCount, 'Underscore is not a single-char wildcard');

        r.searchTerm = 'O\'Brien';
        System.assertEquals(new List<String>{ SUBJECT_OBRIEN }, subjects(run(r)), 'Quote is literal');

        r.searchTerm = 'back\\slash';
        System.assertEquals(0, run(r).totalCount, 'Backslash does not break the query');
    }

    @IsTest
    static void overlongSearchTermIsTruncatedNotRejected() {
        ServiceRequestConsoleController.QueryRequest r = req();
        r.searchTerm = 'a'.repeat(500);
        System.assertEquals(0, run(r).totalCount);
    }

    @IsTest
    static void injectionStyleInputReturnsNothingAndDoesNotFail() {
        ServiceRequestConsoleController.QueryRequest r = req();
        r.searchTerm = '\' OR Name != \'';
        System.assertEquals(0, run(r).totalCount);

        r.searchTerm = 'x%\') OR (Subject__c LIKE \'%';
        System.assertEquals(0, run(r).totalCount);
        System.assertEquals(6, [SELECT COUNT() FROM Service_Request__c], 'Nothing was modified');
    }

    // ------------------------------------------------------------------
    // Sorting
    // ------------------------------------------------------------------
    @IsTest
    static void prioritySortsInBusinessOrder() {
        ServiceRequestConsoleController.QueryRequest r = req();
        r.sortField = 'Priority__c';
        r.sortDirection = 'asc';
        ServiceRequestConsoleController.PageResult ascResult = run(r);
        System.assertEquals('Critical', ascResult.records[0].priority);
        System.assertEquals('Low', ascResult.records[5].priority);

        r.sortDirection = 'DESC';
        ServiceRequestConsoleController.PageResult descResult = run(r);
        System.assertEquals('Low', descResult.records[0].priority);
        System.assertEquals('Critical', descResult.records[5].priority);
    }

    @IsTest
    static void blankValuesAlwaysSortLast() {
        ServiceRequestConsoleController.QueryRequest r = req();
        r.sortField = 'Technician__r.Name';
        for (String direction : new List<String>{ 'ASC', 'DESC' }) {
            r.sortDirection = direction;
            ServiceRequestConsoleController.PageResult result = run(r);
            System.assertEquals(null, result.records[4].technicianName, direction + ': blank technician last');
            System.assertEquals(null, result.records[5].technicianName, direction + ': blank technician last');
            System.assertNotEquals(null, result.records[3].technicianName);
        }

        r.sortField = 'Scheduled_Date__c';
        for (String direction : new List<String>{ 'ASC', 'DESC' }) {
            r.sortDirection = direction;
            ServiceRequestConsoleController.PageResult result = run(r);
            System.assertEquals(null, result.records[4].scheduledDate, direction + ': blank date last');
            System.assertEquals(null, result.records[5].scheduledDate, direction + ': blank date last');
        }
    }

    @IsTest
    static void sortByScheduledDateAndCostRespectsDirection() {
        ServiceRequestConsoleController.QueryRequest r = req();
        r.sortField = 'Scheduled_Date__c';
        r.sortDirection = 'ASC';
        System.assertEquals(SUBJECT_PUMP, run(r).records[0].subject, 'Oldest scheduled date first');
        r.sortDirection = 'DESC';
        System.assertEquals(SUBJECT_CHILLER_F, run(r).records[0].subject, 'Newest scheduled date first');

        r.sortField = 'Estimated_Cost__c';
        System.assertEquals(Decimal.valueOf(2000), run(r).records[0].estimatedCost);
        r.sortDirection = 'ASC';
        System.assertEquals(Decimal.valueOf(250), run(r).records[0].estimatedCost);
    }

    @IsTest
    static void everyAllowListedSortFieldRunsWithoutError() {
        for (String field : new List<String>{ 'Name', 'Subject__c', 'Property__r.Name', 'Status__c' }) {
            ServiceRequestConsoleController.QueryRequest r = req();
            r.sortField = field;
            r.sortDirection = 'ASC';
            System.assertEquals(6, run(r).totalCount, field);
        }
    }

    @IsTest
    static void invalidSortFallsBackToDefaultSort() {
        List<String> defaultOrder = subjects(run(req()));

        ServiceRequestConsoleController.QueryRequest r = req();
        r.sortField = 'Name; DELETE';
        r.sortDirection = 'ASC';
        System.assertEquals(defaultOrder, subjects(run(r)), 'Unknown field');

        r = req();
        r.sortField = 'Priority__c';
        r.sortDirection = 'sideways';
        System.assertEquals(defaultOrder, subjects(run(r)), 'Unknown direction');

        r = req();
        r.sortField = 'Subject__c, Name';
        r.sortDirection = 'ASC NULLS FIRST';
        System.assertEquals(defaultOrder, subjects(run(r)), 'Injection-style values');
    }

    // ------------------------------------------------------------------
    // Combined behaviour
    // ------------------------------------------------------------------
    @IsTest
    static void searchFiltersAndSortCombineWithAnd() {
        Date today = Date.today();
        ServiceRequestConsoleController.QueryRequest r = req();
        r.searchTerm = 'chiller';
        r.priority = 'High';
        r.technicianId = idOfTechnician('Ravi Menon');
        r.statuses = new List<String>{ 'Scheduled' };
        r.requestedFrom = today.addDays(-40);
        r.requestedTo = today;
        r.sortField = 'Scheduled_Date__c';
        r.sortDirection = 'DESC';

        ServiceRequestConsoleController.PageResult result = run(r);
        System.assertEquals(2, result.totalCount);
        System.assertEquals(
            new List<String>{ SUBJECT_CHILLER_F, SUBJECT_CHILLER_A },
            subjects(result),
            'Matches both requests, scheduled date descending'
        );

        r.category = 'Electrical';
        ServiceRequestConsoleController.PageResult none = run(r);
        System.assertEquals(0, none.totalCount, 'One more condition removes everything');
        System.assertEquals(true, none.hasAnyRecords, 'Requests exist, they just do not match');
        System.assertEquals(1, none.totalPages);
        System.assertEquals(0, none.records.size());
    }

    static void userWithoutObjectAccessGetsFriendlyError() {
        User u = consoleUser(false);
        System.runAs(u) {
            try {
                run(req());
                System.assert(false, 'Expected an exception');
            } catch (AuraHandledException e) {
                System.assertEquals(
                    ServiceRequestConsoleController.GENERIC_ERROR_MESSAGE,
                    e.getMessage(),
                    'The user sees a readable message, never internal details'
                );
            }
        }
    }
}
