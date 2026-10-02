// Removes everything created by load-sample-data.apex.
//   sf apex run --file scripts/apex/cleanup-sample-data.apex
// Sample records are identified by the fixed account names and the @summitdemo.example
// technician e-mail domain, so your own data is left alone.
List<String> accountNames = new List<String>{
    'Greenfield Realty', 'Lotus Hospitals', 'Metro Retail Group', 'Skyline Offices Ltd', 'Harbor Logistics'
};

// Deleting a Property also deletes its Service Requests (master-detail).
delete [SELECT Id FROM Property__c WHERE Customer__r.Name IN :accountNames];
delete [SELECT Id FROM Technician__c WHERE Email__c LIKE '%@summitdemo.example'];
delete [SELECT Id FROM Account WHERE Name IN :accountNames];

System.debug('Sample data removed. Service requests left: ' + [SELECT COUNT() FROM Service_Request__c]);
