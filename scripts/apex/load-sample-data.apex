// Loads demo data for the Service Request Console.
//   sf apex run --file scripts/apex/load-sample-data.apex
// Safe to run once. Run scripts/apex/cleanup-sample-data.apex first if you want to reload.
// Data is deterministic (no randomness), so every run produces the same shape of data.

if ([SELECT COUNT() FROM Account WHERE Name = 'Greenfield Realty'] > 0) {
    System.debug(LoggingLevel.WARN, 'Sample data already present. Run cleanup-sample-data.apex first.');
    return;
}

Date today = Date.today();

// ---------------- Accounts (5) ----------------
List<String> accountNames = new List<String>{
    'Greenfield Realty', 'Lotus Hospitals', 'Metro Retail Group', 'Skyline Offices Ltd', 'Harbor Logistics'
};
List<Account> accounts = new List<Account>();
for (String n : accountNames) {
    accounts.add(new Account(Name = n));
}
insert accounts;

// ---------------- Properties (15, three per account) ----------------
List<String> propertyNames = new List<String>{
    'Greenfield Tech Park - Tower A', 'Greenfield Tech Park - Tower B', 'Greenfield Residency',
    'Lotus Hospital Main Block', 'Lotus Hospital Annex', 'Lotus Diagnostics Centre',
    'Metro Mall Central', 'Metro Retail Outlet - Civil Lines', 'Metro Warehouse Hub',
    'Skyline Plaza', 'Skyline Business Centre', 'Skyline Annexe Offices',
    'Harbor Cold Storage', 'Harbor Distribution Centre', 'Harbor Staff Quarters'
};
List<String> propertyCities = new List<String>{
    'Kanpur', 'Kanpur', 'Lucknow', 'Lucknow', 'Lucknow', 'Pune', 'Mumbai', 'Kanpur', 'Delhi',
    'Bengaluru', 'Bengaluru', 'Pune', 'Mumbai', 'Delhi', 'Mumbai'
};
List<String> propertyTypes = new List<String>{
    'Office', 'Office', 'Residential Complex', 'Hospital', 'Hospital', 'Hospital', 'Retail', 'Retail',
    'Warehouse', 'Office', 'Office', 'Office', 'Warehouse', 'Warehouse', 'Residential Complex'
};
List<Property__c> properties = new List<Property__c>();
Integer accountIndex = 0;
for (Integer i = 0; i < propertyNames.size(); i++) {
    if (i > 0 && Math.mod(i, 3) == 0) {
        accountIndex++; // three properties per account
    }
    properties.add(new Property__c(
        Name = propertyNames[i],
        Customer__c = accounts[accountIndex].Id,
        City__c = propertyCities[i],
        Property_Type__c = propertyTypes[i],
        Active__c = Math.mod(i, 7) != 6
    ));
}
insert properties;

// ---------------- Technicians (8, one inactive) ----------------
List<String> techNames = new List<String>{
    'Ravi Menon', 'Anita Rao', 'Imran Sheikh', 'Priya Nair', 'Sandeep Yadav', 'Meera Iyer', 'Karan Malhotra', 'Old Hand (Retired)'
};
List<String> techSkills = new List<String>{
    'HVAC', 'Electrical', 'Plumbing', 'Carpentry', 'General', 'HVAC', 'Electrical', 'Plumbing'
};
List<Technician__c> technicians = new List<Technician__c>();
for (Integer i = 0; i < techNames.size(); i++) {
    technicians.add(new Technician__c(
        Name = techNames[i],
        Email__c = 'tech' + (i + 1) + '@summitdemo.example',
        Phone__c = '+91 98000 0000' + i,
        Primary_Skill__c = techSkills[i],
        Hourly_Rate__c = 15 + (i * 2.5),
        Active__c = (i != 7)
    ));
}
insert technicians;
List<Technician__c> activeTechs = new List<Technician__c>();
for (Technician__c t : technicians) {
    if (t.Active__c) {
        activeTechs.add(t);
    }
}

// ---------------- Service requests (330) ----------------
List<String> subjectTemplates = new List<String>{
    'Chiller unit not cooling', 'AC compressor noise', 'Replace faulty circuit breaker', 'Clogged drain in basement',
    'Flickering corridor lights', 'Water heater not working', 'Broken door hinge', 'Elevator lobby deep clean',
    'Generator service due', 'Tap leaking in pantry', 'Ventilation fan failure', 'Socket sparking in server room'
};
List<String> categories = new List<String>{ 'HVAC', 'Electrical', 'Plumbing', 'Carpentry', 'Cleaning', 'Other' };
// Subjects with special characters, used to test search safety.
Map<Integer, String> specialSubjects = new Map<Integer, String>{
    8 => 'Leak at 50% capacity',
    21 => 'O\'Brien\'s caf\u00e9 AC',
    34 => 'Pump_02 failure',
    47 => 'Chiller plant 100% shutdown',
    60 => 'Back\\up generator test'
};

List<Service_Request__c> requests = new List<Service_Request__c>();
for (Integer i = 0; i < 330; i++) {
    Integer bucket = Math.mod(i, 20);
    Integer ago = Math.mod(i * 11, 360); // requested dates spread over the last 12 months

    String priority;
    Integer p = Math.mod(i, 20);
    if (p < 2) { priority = 'Critical'; }
    else if (p < 7) { priority = 'High'; }
    else if (p < 15) { priority = 'Medium'; }
    else { priority = 'Low'; }

    Service_Request__c sr = new Service_Request__c(
        Property__c = properties[Math.mod(i * 7, properties.size())].Id,
        Subject__c = specialSubjects.containsKey(i)
            ? specialSubjects.get(i)
            : subjectTemplates[Math.mod(i, subjectTemplates.size())] + ' - floor ' + (1 + Math.mod(i, 9)),
        Description__c = 'Sample request ' + i + ' created by load-sample-data.apex',
        Category__c = categories[Math.mod(i, categories.size())],
        Priority__c = priority
    );
    Technician__c tech = activeTechs[Math.mod(i * 3, activeTechs.size())];

    if (bucket < 4) {
        // 20%: brand-new, unassigned, nothing scheduled
        sr.Status__c = 'New';
    } else if (bucket < 8) {
        // 20%: scheduled shortly after request; older ones are overdue
        sr.Status__c = 'Scheduled';
        sr.Technician__c = tech.Id;
        sr.Scheduled_Date__c = today.addDays(-ago + 2 + Math.mod(i, 5));
    } else if (bucket < 10) {
        // 10%: scheduled in the future (not overdue)
        sr.Status__c = 'Scheduled';
        sr.Technician__c = tech.Id;
        sr.Scheduled_Date__c = today.addDays(1 + Math.mod(i, 14));
        ago = Math.mod(ago, 7);
    } else if (bucket < 12) {
        // 10%: in progress, sometimes without a scheduled date
        sr.Status__c = 'In Progress';
        sr.Technician__c = tech.Id;
        if (Math.mod(i, 3) != 0) {
            sr.Scheduled_Date__c = today.addDays(-ago + 1);
        }
    } else if (bucket == 12) {
        // 5%: on hold, technician optional
        sr.Status__c = 'On Hold';
        if (Math.mod(i, 2) == 0) {
            sr.Technician__c = tech.Id;
            sr.Scheduled_Date__c = today.addDays(-ago + 3);
        }
    } else if (bucket < 18) {
        // 25%: completed, always at least 10 days old so dates are not in the future
        ago = Math.max(ago, 10);
        sr.Status__c = 'Completed';
        sr.Technician__c = tech.Id;
        sr.Scheduled_Date__c = today.addDays(-ago + 2);
        sr.Completed_Date__c = today.addDays(-ago + 4);
    } else if (bucket == 18) {
        // 5%: cancelled
        sr.Status__c = 'Cancelled';
    } else {
        // 5%: in progress today
        ago = Math.mod(i, 5);
        sr.Status__c = 'In Progress';
        sr.Technician__c = tech.Id;
        sr.Scheduled_Date__c = today;
    }

    sr.Requested_Date__c = today.addDays(-ago);
    // Some requests have no estimated cost, to test blank-value sorting.
    if (Math.mod(i, 7) != 0) {
        sr.Estimated_Cost__c = 500 + Math.mod(i * 137, 9500);
    }
    requests.add(sr);
}
insert requests;

System.debug(
    'Sample data loaded: ' + accounts.size() + ' accounts, ' + properties.size() + ' properties, ' +
    technicians.size() + ' technicians, ' + requests.size() + ' service requests.'
);
System.debug('Overdue: ' + [SELECT COUNT() FROM Service_Request__c WHERE Is_Overdue__c = true]);
System.debug('Unassigned: ' + [SELECT COUNT() FROM Service_Request__c WHERE Technician__c = null]);
