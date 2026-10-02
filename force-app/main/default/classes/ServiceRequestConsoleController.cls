/**
 * Backend for the Service Request Console LWC.
 *
 * Design notes
 *  - `with sharing` plus AccessLevel.USER_MODE: record sharing, object CRUD and field-level
 *    security are all enforced for the running user.
 *  - Paging is server-side (LIMIT / OFFSET). Only the requested page is returned, together
 *    with the total number of matching records.
 *  - All user input is bound (never concatenated into the query). Sort field, sort direction
 *    and page size come from allow-lists.
 *  - Estimated_Cost__c is only queried when the user can read it.
 */
public with sharing class ServiceRequestConsoleController {
    public static final String GENERIC_ERROR_MESSAGE = 'We could not load service requests. Please try again, or contact your administrator if the problem continues.';

    @TestVisible
    private static final Integer DEFAULT_PAGE_SIZE = 25;
    private static final Set<Integer> ALLOWED_PAGE_SIZES = new Set<Integer>{ 10, 25, 50, 100 };
    // SOQL OFFSET cannot exceed 2,000. Overridable in tests so the limit can be exercised cheaply.
    @TestVisible
    private static Integer maxOffset = 2000;
    private static final Integer MIN_SEARCH_LENGTH = 2;
    private static final Integer MAX_SEARCH_LENGTH = 100;

    private static final String DEFAULT_SORT_FIELD = 'Requested_Date__c';
    private static final String DEFAULT_SORT_DIRECTION = 'DESC';
    private static final String COST_FIELD = 'Estimated_Cost__c';

    // Allow-list: key sent by the client -> field used in ORDER BY.
    private static final Map<String, String> SORT_FIELDS = new Map<String, String>{
        'Name' => 'Name',
        'Subject__c' => 'Subject__c',
        'Property__r.Name' => 'Property__r.Name',
        'Technician__r.Name' => 'Technician__r.Name',
        'Status__c' => 'Status__c',
        'Priority__c' => 'Priority__c',
        'Requested_Date__c' => 'Requested_Date__c',
        'Scheduled_Date__c' => 'Scheduled_Date__c',
        'Estimated_Cost__c' => 'Estimated_Cost__c'
    };

    // ------------------------------------------------------------------
    // Transfer objects
    // ------------------------------------------------------------------
    public class Option {
        @AuraEnabled
        public String label;
        @AuraEnabled
        public String value;
        public Option(String label, String value) {
            this.label = label;
            this.value = value;
        }
    }

    public class FilterOptions {
        @AuraEnabled
        public List<Option> statuses = new List<Option>();
        @AuraEnabled
        public List<Option> priorities = new List<Option>();
        @AuraEnabled
        public List<Option> categories = new List<Option>();
        @AuraEnabled
        public Boolean canViewEstimatedCost = false;
    }

    public class QueryRequest {
        @AuraEnabled
        public String searchTerm;
        @AuraEnabled
        public List<String> statuses;
        @AuraEnabled
        public String priority;
        @AuraEnabled
        public String category;
        @AuraEnabled
        public Date requestedFrom;
        @AuraEnabled
        public Date requestedTo;
        @AuraEnabled
        public String technicianId;
        @AuraEnabled
        public String propertyId;
        @AuraEnabled
        public Boolean overdueOnly;
        @AuraEnabled
        public String sortField;
        @AuraEnabled
        public String sortDirection;
        @AuraEnabled
        public Integer pageNumber;
        @AuraEnabled
        public Integer pageSize;
    }

    public class RequestRow {
        @AuraEnabled
        public Id id;
        @AuraEnabled
        public String name;
        @AuraEnabled
        public String subject;
        @AuraEnabled
        public String propertyName;
        @AuraEnabled
        public String customerName;
        @AuraEnabled
        public String technicianName;
        @AuraEnabled
        public String status;
        @AuraEnabled
        public String priority;
        @AuraEnabled
        public String category;
        @AuraEnabled
        public Date requestedDate;
        @AuraEnabled
        public Date scheduledDate;
        @AuraEnabled
        public Decimal estimatedCost;
        @AuraEnabled
        public Boolean isOverdue;
    }

    public class PageResult {
        @AuraEnabled
        public List<RequestRow> records = new List<RequestRow>();
        @AuraEnabled
        public Integer totalCount = 0;
        @AuraEnabled
        public Integer pageNumber = 1;
        @AuraEnabled
        public Integer pageSize = 25;
        @AuraEnabled
        public Integer totalPages = 1;
        // Highest page that can be reached with OFFSET (see README, "2,000-row limit").
        @AuraEnabled
        public Integer maxReachablePage = 1;
        @AuraEnabled
        public Boolean isTruncated = false;
        // False only when the user can see no service requests at all (drives the empty state).
        @AuraEnabled
        public Boolean hasAnyRecords = false;
        @AuraEnabled
        public Boolean canViewEstimatedCost = false;
    }

    // ------------------------------------------------------------------
    // Public API
    // ------------------------------------------------------------------

    /** Picklist values come from org metadata, so new values appear without code changes. */
    @AuraEnabled(cacheable=true)
    public static FilterOptions getFilterOptions() {
        try {
            FilterOptions options = new FilterOptions();
            options.statuses = toOptions(Service_Request__c.Status__c.getDescribe());
            options.priorities = toOptions(Service_Request__c.Priority__c.getDescribe());
            options.categories = toOptions(Service_Request__c.Category__c.getDescribe());
            options.canViewEstimatedCost = canViewEstimatedCost();
            return options;
        } catch (Exception e) {
            throw toFriendlyException(e);
        }
    }

    @AuraEnabled
    public static PageResult getServiceRequests(QueryRequest request) {
        try {
            return fetchPage(request == null ? new QueryRequest() : request);
        } catch (Exception e) {
            throw toFriendlyException(e);
        }
    }

    // ------------------------------------------------------------------
    // Paging
    // ------------------------------------------------------------------
    private static PageResult fetchPage(QueryRequest req) {
        Integer pageSize = normalizePageSize(req.pageSize);
        Boolean canViewCost = canViewEstimatedCost();

        Map<String, Object> binds = new Map<String, Object>();
        String fromAndWhere = ' FROM Service_Request__c' + buildWhereClause(req, binds);

        Integer total = Database.countQueryWithBinds(
            'SELECT COUNT()' + fromAndWhere,
            binds,
            AccessLevel.USER_MODE
        );

        PageResult result = new PageResult();
        result.pageSize = pageSize;
        result.totalCount = total;
        result.canViewEstimatedCost = canViewCost;
        result.totalPages = Math.max(1, divide(total, pageSize, System.RoundingMode.CEILING));
        result.maxReachablePage = Math.min(
            result.totalPages,
            divide(maxOffset, pageSize, System.RoundingMode.FLOOR) + 1
        );
        result.isTruncated = result.totalPages > result.maxReachablePage;
        result.pageNumber = normalizePageNumber(req.pageNumber, result.maxReachablePage);
        result.hasAnyRecords = total > 0 || anyRecordVisible();

        if (total == 0) {
            return result;
        }

        Integer offset = (result.pageNumber - 1) * pageSize;
        String soql =
            buildSelectClause(canViewCost) +
            fromAndWhere +
            buildOrderByClause(req, canViewCost) +
            ' LIMIT ' +
            pageSize +
            ' OFFSET ' +
            offset;

        for (SObject record : Database.queryWithBinds(soql, binds, AccessLevel.USER_MODE)) {
            result.records.add(toRow((Service_Request__c) record, canViewCost));
        }
        return result;
    }

    private static Integer normalizePageSize(Integer requested) {
        return (requested != null && ALLOWED_PAGE_SIZES.contains(requested))
            ? requested
            : DEFAULT_PAGE_SIZE;
    }

    /** Anything outside the reachable range falls back to page 1, never an empty page. */
    private static Integer normalizePageNumber(Integer requested, Integer maxPage) {
        return (requested == null || requested < 1 || requested > maxPage) ? 1 : requested;
    }

    private static Integer divide(Integer numerator, Integer denominator, System.RoundingMode mode) {
        return (Decimal.valueOf(numerator) / denominator).setScale(0, mode).intValue();
    }

    private static Boolean anyRecordVisible() {
        return ![SELECT Id FROM Service_Request__c WITH USER_MODE LIMIT 1].isEmpty();
    }

    // ------------------------------------------------------------------
    // Query building
    // ------------------------------------------------------------------
    private static String buildSelectClause(Boolean canViewCost) {
        String fields =
            'Id, Name, Subject__c, Property__r.Name, Property__r.Customer__r.Name, ' +
            'Technician__r.Name, Status__c, Priority__c, Category__c, ' +
            'Requested_Date__c, Scheduled_Date__c, Is_Overdue__c';
        if (canViewCost) {
            fields += ', ' + COST_FIELD;
        }
        return 'SELECT ' + fields;
    }

    /** Every condition uses a bind variable; nothing from the client is concatenated. */
    private static String buildWhereClause(QueryRequest req, Map<String, Object> binds) {
        List<String> conditions = new List<String>();

        String term = normalizeSearchTerm(req.searchTerm);
        if (term != null) {
            binds.put('searchPattern', '%' + escapeLike(term) + '%');
            conditions.add(
                '(Name LIKE :searchPattern OR Subject__c LIKE :searchPattern ' +
                    'OR Property__r.Name LIKE :searchPattern OR Technician__r.Name LIKE :searchPattern)'
            );
        }

        List<String> statuses = keepKnown(
            req.statuses,
            valuesOf(Service_Request__c.Status__c.getDescribe())
        );
        if (!statuses.isEmpty()) {
            binds.put('statuses', statuses);
            conditions.add('Status__c IN :statuses');
        }

        String priority = knownValue(
            req.priority,
            valuesOf(Service_Request__c.Priority__c.getDescribe())
        );
        if (priority != null) {
            binds.put('priority', priority);
            conditions.add('Priority__c = :priority');
        }

        String category = knownValue(
            req.category,
            valuesOf(Service_Request__c.Category__c.getDescribe())
        );
        if (category != null) {
            binds.put('category', category);
            conditions.add('Category__c = :category');
        }

        if (req.requestedFrom != null) {
            binds.put('requestedFrom', req.requestedFrom);
            conditions.add('Requested_Date__c >= :requestedFrom');
        }
        if (req.requestedTo != null) {
            binds.put('requestedTo', req.requestedTo);
            conditions.add('Requested_Date__c <= :requestedTo');
        }

        Id technicianId = toId(req.technicianId, Technician__c.SObjectType);
        if (technicianId != null) {
            binds.put('technicianId', technicianId);
            conditions.add('Technician__c = :technicianId');
        }

        Id propertyId = toId(req.propertyId, Property__c.SObjectType);
        if (propertyId != null) {
            binds.put('propertyId', propertyId);
            conditions.add('Property__c = :propertyId');
        }

        if (req.overdueOnly == true) {
            conditions.add('Is_Overdue__c = true');
        }

        return conditions.isEmpty() ? '' : ' WHERE ' + String.join(conditions, ' AND ');
    }

    /**
     * Sort field and direction are validated against allow-lists. Anything invalid (or a cost
     * sort for a user who cannot read cost) falls back to the default sort.
     * NULLS LAST keeps blanks at the bottom in both directions; Name is the stable tie-breaker.
     * Picklist fields sort in picklist-definition order in SOQL, which gives
     * Critical -> High -> Medium -> Low for Priority.
     */
    private static String buildOrderByClause(QueryRequest req, Boolean canViewCost) {
        String field = req.sortField == null ? null : SORT_FIELDS.get(req.sortField);
        String direction = req.sortDirection == null ? null : req.sortDirection.toUpperCase();
        Boolean valid =
            field != null &&
            (direction == 'ASC' ||
            direction == 'DESC') &&
            (field != COST_FIELD ||
            canViewCost);
        if (!valid) {
            field = DEFAULT_SORT_FIELD;
            direction = DEFAULT_SORT_DIRECTION;
        }
        String orderBy = ' ORDER BY ' + field + ' ' + direction + ' NULLS LAST';
        if (field != 'Name') {
            orderBy += ', Name ' + direction;
        }
        return orderBy;
    }

    // ------------------------------------------------------------------
    // Input helpers
    // ------------------------------------------------------------------
    private static String normalizeSearchTerm(String raw) {
        if (raw == null) {
            return null;
        }
        String term = raw.trim();
        if (term.length() < MIN_SEARCH_LENGTH) {
            return null;
        }
        return term.length() > MAX_SEARCH_LENGTH ? term.substring(0, MAX_SEARCH_LENGTH) : term;
    }

    /** Makes %, _ and \ behave as plain text inside a LIKE pattern. */
    private static String escapeLike(String term) {
        return term.replace('\\', '\\\\').replace('%', '\\%').replace('_', '\\_');
    }

    private static Id toId(String value, Schema.SObjectType expectedType) {
        if (String.isBlank(value)) {
            return null;
        }
        try {
            Id parsed = Id.valueOf(value.trim());
            return parsed.getSObjectType() == expectedType ? parsed : null;
        } catch (Exception e) {
            return null;
        }
    }

    private static List<String> keepKnown(List<String> requested, Set<String> known) {
        List<String> result = new List<String>();
        if (requested != null) {
            for (String value : requested) {
                if (value != null && known.contains(value)) {
                    result.add(value);
                }
            }
        }
        return result;
    }

    private static String knownValue(String requested, Set<String> known) {
        return (requested != null && known.contains(requested)) ? requested : null;
    }

    // ------------------------------------------------------------------
    // Describe / mapping helpers
    // ------------------------------------------------------------------
    private static Set<String> valuesOf(Schema.DescribeFieldResult describe) {
        Set<String> values = new Set<String>();
        for (Schema.PicklistEntry entry : describe.getPicklistValues()) {
            if (entry.isActive()) {
                values.add(entry.getValue());
            }
        }
        return values;
    }

    private static List<Option> toOptions(Schema.DescribeFieldResult describe) {
        List<Option> options = new List<Option>();
        for (Schema.PicklistEntry entry : describe.getPicklistValues()) {
            if (entry.isActive()) {
                options.add(new Option(entry.getLabel(), entry.getValue()));
            }
        }
        return options;
    }

    private static Boolean canViewEstimatedCost() {
        return Schema.SObjectType.Service_Request__c.fields.Estimated_Cost__c.isAccessible();
    }

    private static RequestRow toRow(Service_Request__c sr, Boolean canViewCost) {
        RequestRow row = new RequestRow();
        row.id = sr.Id;
        row.name = sr.Name;
        row.subject = sr.Subject__c;
        row.propertyName = sr.Property__r?.Name;
        row.customerName = sr.Property__r?.Customer__r?.Name;
        row.technicianName = sr.Technician__r?.Name;
        row.status = sr.Status__c;
        row.priority = sr.Priority__c;
        row.category = sr.Category__c;
        row.requestedDate = sr.Requested_Date__c;
        row.scheduledDate = sr.Scheduled_Date__c;
        row.isOverdue = sr.Is_Overdue__c;
        // Estimated_Cost__c is only queried when readable; otherwise it stays null.
        row.estimatedCost = canViewCost ? sr.Estimated_Cost__c : null;
        return row;
    }

    /** Never leak internal exception text to the browser. Details go to the debug log. */
    private static AuraHandledException toFriendlyException(Exception e) {
        System.debug(
            LoggingLevel.ERROR,
            'ServiceRequestConsole error: ' + e.getMessage() + '\n' + e.getStackTraceString()
        );
        AuraHandledException friendly = new AuraHandledException(GENERIC_ERROR_MESSAGE);
        friendly.setMessage(GENERIC_ERROR_MESSAGE);
        return friendly;
    }
}
