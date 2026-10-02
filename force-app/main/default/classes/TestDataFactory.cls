/**
 * Central place to build test data. Methods either return unsaved records or insert them,
 * depending on the `doInsert` flag.
 */
@IsTest
public class TestDataFactory {
    private static Integer counter = 0;

    public static Account createAccount(String name, Boolean doInsert) {
        Account acc = new Account(Name = name);
        if (doInsert) {
            insert acc;
        }
        return acc;
    }

    public static Property__c createProperty(Id accountId, String name, Boolean doInsert) {
        Property__c prop = new Property__c(
            Name = name,
            Customer__c = accountId,
            City__c = 'Kanpur',
            Property_Type__c = 'Office',
            Active__c = true
        );
        if (doInsert) {
            insert prop;
        }
        return prop;
    }

    public static Technician__c createTechnician(String name, Boolean active, Boolean doInsert) {
        counter++;
        Technician__c tech = new Technician__c(
            Name = name,
            Email__c = 'tech' + counter + '@summit-test.example',
            Primary_Skill__c = 'HVAC',
            Hourly_Rate__c = 20,
            Active__c = active
        );
        if (doInsert) {
            insert tech;
        }
        return tech;
    }

    /** Builds a valid (rule-compliant) request; callers override the fields they care about. */
    public static Service_Request__c buildServiceRequest(Id propertyId, String subject) {
        return new Service_Request__c(
            Property__c = propertyId,
            Subject__c = subject,
            Status__c = 'New',
            Priority__c = 'Medium',
            Category__c = 'HVAC',
            Requested_Date__c = Date.today()
        );
    }

    public static List<Service_Request__c> createServiceRequests(
        Id propertyId,
        Integer count,
        Boolean doInsert
    ) {
        List<Service_Request__c> requests = new List<Service_Request__c>();
        for (Integer i = 0; i < count; i++) {
            Service_Request__c sr = buildServiceRequest(propertyId, 'Bulk request ' + i);
            sr.Requested_Date__c = Date.today().addDays(-Math.mod(i, 300));
            requests.add(sr);
        }
        if (doInsert) {
            insert requests;
        }
        return requests;
    }

    /** A user with a standard profile plus only the console permission set. */
    public static User createConsoleUser(Boolean withPermissionSet) {
        Profile profile = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];
        counter++;
        User u = new User(
            Alias = 'sr' + counter,
            Email = 'srconsole' + counter + '@summit-test.example',
            EmailEncodingKey = 'UTF-8',
            LastName = 'ConsoleUser' + counter,
            LanguageLocaleKey = 'en_US',
            LocaleSidKey = 'en_US',
            ProfileId = profile.Id,
            TimeZoneSidKey = 'Asia/Kolkata',
            Username = 'srconsole' + counter + '.' + System.currentTimeMillis() + '@summit-test.example'
        );
        insert u;
        if (withPermissionSet) {
            PermissionSet ps = [
                SELECT Id
                FROM PermissionSet
                WHERE Name = 'Service_Request_Console_User'
                LIMIT 1
            ];
            insert new PermissionSetAssignment(AssigneeId = u.Id, PermissionSetId = ps.Id);
        }
        return u;
    }
}
