public with sharing class ServiceRequestConsoleController {

    @AuraEnabled(cacheable=true)
    public static List<Service_Request__c> getServiceRequests(
        List<String> statuses,
        String priority,
        String category,
        Date requestedDateFrom,
        Date requestedDateTo,
        Boolean overdueOnly,
        Id technicianId,
        Id propertyId,
        String searchKey,
        String sortDirection
    ) {
        Id currentUserId = UserInfo.getUserId();

        User currentUser = [
            SELECT Department
            FROM User
            WHERE Id = :currentUserId
            LIMIT 1
        ];

        // Default statuses
        if (statuses == null || statuses.isEmpty()) {
            statuses = new List<String>{
                'New',
                'Scheduled',
                'In Progress',
                'On Hold'
            };
        }

        // Search pattern
        String searchPattern;

        if (String.isNotBlank(searchKey)) {
            searchPattern = '%' + searchKey + '%';
        }

        // Base query
        String query =
            'SELECT Id, Name, Subject__c, Status__c, Priority__c, Category__c, Requested_Date__c, Property__r.Name, Technician__r.Name FROM Service_Request__c  WHERE Status__c IN :statuses';

        // Priority filter
        if (priority != null && priority != '') {
            query += ' AND Priority__c = :priority';
        }

        // Category filter
        if (category != null && category != '') {
            query += ' AND Category__c = :category';
        }

        // Requested Date From
        if (requestedDateFrom != null) {
            query += ' AND Requested_Date__c >= :requestedDateFrom';
        }

        // Requested Date To
        if (requestedDateTo != null) {
            query += ' AND Requested_Date__c <= :requestedDateTo';
        }

        // Overdue filter
        if (overdueOnly == true) {
            query += ' AND Is_Overdue__c = true';
        }

        // Technician filter
        if (technicianId != null) {
            query += ' AND Technician__c = :technicianId';
        }

        // Property filter
        if (propertyId != null) {
            query += ' AND Property__c = :propertyId';
        }

        // Search filter
        if (String.isNotBlank(searchKey)) {
            query += ' AND (Name LIKE :searchPattern ' +
                     'OR Subject__c LIKE :searchPattern ' +
                     'OR Property__r.Name LIKE :searchPattern ' +
                     'OR Technician__r.Name LIKE :searchPattern)';
        }
        if (currentUser.Department == 'Technician') {
            query += ' AND Technician__r.UserAssigned__c = :currentUserId';
        }

        // Sorting and limit
        if (sortDirection == 'asc') {
            query += ' ORDER BY Requested_Date__c ASC';
        } else {
            query += ' ORDER BY Requested_Date__c DESC';
        }
        
    

        return Database.query(query);
    }

    @AuraEnabled
    public static void assignTechnician(List<Id> serviceRequestIds, Id technicianId) {
    
        if (serviceRequestIds == null || serviceRequestIds.isEmpty() || technicianId == null) {
            throw new AuraHandledException('Select at least one request and a technician.');
        }
    
        User currentUser = [
            SELECT Department FROM User WHERE Id = :UserInfo.getUserId()
        ];
    
        if (currentUser.Department == 'Technician') {
            throw new AuraHandledException(
                'Technicians are not allowed to assign service requests.'
            );
        }
    
        List<Service_Request__c> toUpdate = new List<Service_Request__c>();
        for (Id srId : serviceRequestIds) {
            toUpdate.add(new Service_Request__c(
                Id = srId,
                Technician__c = technicianId
            ));
        }
    
        try {
            update as user toUpdate;
        } catch (DmlException e) {
            throw new AuraHandledException(e.getDmlMessage(0));
        }
    }
   
}
