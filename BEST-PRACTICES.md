# Workday Provisioning - Best Practices & Examples

## Configuration Patterns

### Pattern 1: Standard Employee Provisioning

**Scope**: All active employees

**Configuration**:

```json
{
  "SourceObjectName": "Employee",
  "TargetObjectName": "User",
  "AttributeMappings": [
    {
      "source": "Employee_ID",
      "target": "employeeId",
      "type": "String",
      "required": true
    },
    {
      "source": "First_Name",
      "target": "givenName",
      "type": "String",
      "required": true
    },
    {
      "source": "Last_Name",
      "target": "surname",
      "type": "String",
      "required": true
    },
    {
      "source": "Work_Email",
      "target": "mail",
      "type": "String",
      "required": false,
      "note": "May be populated later after M365 licensing"
    },
    {
      "source": "Department",
      "target": "department",
      "type": "String"
    },
    {
      "source": "Job_Title",
      "target": "jobTitle",
      "type": "String"
    },
    {
      "source": "Manager_ID",
      "target": "manager",
      "type": "Reference"
    },
    {
      "source": "Location",
      "target": "officeLocation",
      "type": "String"
    }
  ],
  "ScopingRules": {
    "Include": [
      {
        "attribute": "Employment_Status",
        "operator": "EQUALS",
        "value": "ACTIVE"
      }
    ],
    "Exclude": [
      {
        "attribute": "Employment_Status",
        "operator": "EQUALS",
        "value": "TERMINATED"
      }
    ]
  }
}
```

**Sync Schedule**: Daily at 2 AM

**Note**: This pattern supports deferred email assignment. Users are created in Entra without email, then M365 licensing creates the email/UPN which can be synced back to Workday.

### Pattern 2: Deferred Email Provisioning (Application Workflow)

**Scope**: New employees created in Workday without email addresses

**Workflow**:
1. Employee created in Workday during application process (no email yet)
2. Provisioned to Entra as user
3. M365 license assigned → creates UPN and email
4. Email written back to Workday
5. Subsequent syncs maintain email bidirectionally

**Initial Provisioning Configuration (Workday → Entra)**:
```json
{
  "SourceObjectName": "Employee",
  "TargetObjectName": "User",
  "AttributeMappings": [
    {
      "source": "Employee_ID",
      "target": "employeeId",
      "type": "String",
      "required": true
    },
    {
      "source": "First_Name",
      "target": "givenName",
      "type": "String",
      "required": true
    },
    {
      "source": "Last_Name",
      "target": "surname",
      "type": "String",
      "required": true
    },
    {
      "source": "Work_Email",
      "target": "mail",
      "type": "String",
      "required": false,
      "expression": "iff(IsNull([Work_Email]),null,[Work_Email])",
      "note": "Email will be populated after M365 licensing"
    },
    {
      "source": "Department",
      "target": "department",
      "type": "String"
    },
    {
      "source": "Job_Title",
      "target": "jobTitle",
      "type": "String"
    }
  ]
}
```

**Sync Schedule**: Daily at 2 AM

**Bidirectional Sync Configuration** (Entra → Workday):
After M365 licensing creates the email/UPN in Entra, a separate sync writes back:
```json
{
  "SourceObjectName": "User",
  "TargetObjectName": "Employee",
  "ScopingRules": {
    "Include": [
      {
        "attribute": "mail",
        "operator": "NOT_EQUALS",
        "value": "null"
      }
    ]
  },
  "AttributeMappings": [
    {
      "source": "mail",
      "target": "Work_Email",
      "type": "String",
      "note": "Sync email created by M365 licensing back to Workday"
    },
    {
      "source": "userPrincipalName",
      "target": "UPN",
      "type": "String",
      "note": "Sync UPN back to Workday for reference"
    }
  ]
}
```

**Sync Schedule**: Daily at 4 AM (after M365 licensing process)

**Important Notes**:
- The second sync job (Entra → Workday) ensures email/UPN from M365 licensing is captured back in Workday
- Scoping rule on the second job prevents syncing users without email (still pending M365 licensing)
- This creates a complete audit trail: Workday → Entra → M365 → Workday

### Pattern 3: Termination Management

**Scope**: Termed employees

**Configuration**:

```json
{
  "SourceObjectName": "Employee",
  "TargetObjectName": "User",
  "AttributeMappings": [
    {
      "source": "Employee_ID",
      "target": "employeeId",
      "type": "String"
    },
    {
      "source": "Employment_Status",
      "target": "accountEnabled",
      "type": "Boolean",
      "expression": "iff([Employment_Status]=\"TERMINATED\",false,true)"
    }
  ],
  "ScopingRules": {
    "Include": [
      {
        "attribute": "Employment_Status",
        "operator": "IN",
        "values": ["TERMINATED", "ON_LEAVE", "INACTIVE"]
      }
    ]
  }
}
```

**Sync Schedule**: Daily at 3 AM (after main sync)

### Pattern 4: Manager Hierarchy

**Scope**: Employees with manager relationships

**Configuration**:

```json
{
  "SourceObjectName": "Employee",
  "TargetObjectName": "User",
  "AttributeMappings": [
    {
      "source": "Employee_ID",
      "target": "employeeId",
      "type": "String"
    },
    {
      "source": "Manager_ID",
      "target": "manager",
      "type": "Reference",
      "mapping": {
        "sourceType": "Employee",
        "sourceAttribute": "Employee_ID",
        "targetType": "User",
        "targetAttribute": "id"
      }
    }
  ]
}
```

**Sync Schedule**: Twice daily (after employee sync)

## Expression Examples

### Converting Text to Boolean

```text
iff([Employment_Status]="ACTIVE",true,false)
```

### Email Construction

```
Append([Employee_ID], "@example.com")
```

### Department Code Mapping

```
Switch([Dept_Code],
  "100","Sales",
  "200","Engineering",
  "300","Operations",
  "N/A")
```

### Name Formatting

```
Concat([Last_Name], ", ", [First_Name])
```

### Conditional Default

```
iff(IsNull([Mobile_Phone]),"[Mobile_Not_Provided]",[Mobile_Phone])
```

## Data Type Handling

### String to Boolean

- Source: `true` (string)
- Target: true (boolean)
- Expression: `IIF([source_field]="true",true,false)`

### Date Formatting

- Source: `2024-01-15`
- Target: `/Date(1705276800000)/`
- Expression: `FormatDateTime([source_date],"yyyy-MM-dd")`

### Reference Mapping

- Source: `Manager_ID` (employee ID)
- Target: `manager` (user object reference)
- Requires: Two-step sync (first employees, then managers)

## Scoping Rules - Best Practices

### Rule 1: Include Only Active Employees

```
Include: Employment_Status EQUALS "ACTIVE"
```

### Rule 2: Exclude Test Accounts

```
Exclude: Email STARTSWITH "test"
Exclude: Email STARTSWITH "demo"
```

### Rule 3: Department-Specific Provisioning

```
Include: Department EQUALS "Engineering"
Include: Department EQUALS "Sales"
```

### Rule 4: Location-Based

```
Include: Country EQUALS "USA"
Include: State IN ["CA", "NY", "TX"]
```

### Rule 5: Exclude Contractors

```
Exclude: Employment_Type EQUALS "CONTRACTOR"
Exclude: Employment_Type EQUALS "TEMPORARY"
```

## Attribute Mapping - Quality Checklist

### Source Attribute

- [ ] Attribute exists in Workday
- [ ] Attribute populated for target users
- [ ] Data format matches documentation
- [ ] Handles null values gracefully
- [ ] Permission to read attribute granted

### Target Attribute

- [ ] Valid Azure AD attribute name
- [ ] Correct data type expected
- [ ] Supports write operations
- [ ] Not a read-only attribute
- [ ] Complies with organization policy

### Expression

- [ ] Syntax is valid
- [ ] Handles edge cases (null, empty)
- [ ] Performance acceptable
- [ ] Tested with sample data
- [ ] Documented for team

### Mapping

- [ ] Maps required fields
- [ ] Handles immutable fields appropriately
- [ ] Supports deprovisioning
- [ ] Tested for round-trip consistency
- [ ] Audit trail available

## Testing Procedures

### Test 1: Single User Sync

1. Disable full sync
2. Modify test user in Workday
3. Run sync for that user only
4. Verify attributes in Azure AD
5. Check sync logs for errors

### Test 2: Attribute Validation

1. Create test employee in Workday
2. Run provisioning
3. Compare each mapped attribute:
   - Value matches
   - Data type correct
   - Format as expected
   - No truncation
   - Special characters handled

### Test 3: Error Scenarios

1. Test with null values
2. Test with special characters
3. Test with max-length strings
4. Test with numeric values as strings
5. Test with date edge cases

### Test 4: Scope Validation

1. Verify included users sync
2. Verify excluded users don't sync
3. Test scope transitions (add/remove from scope)
4. Verify deprovisioning works for out-of-scope users

## Performance Optimization

### Reduce Sync Time

```
Metric: 10,000 users
Current Duration: 2 hours
Target: 45 minutes
Strategy: Remove unused attributes, simplify expressions
```

### Optimize Expressions

Bad:

```
If([Source1]="A", If([Source2]="B", If([Source3]="C", "Value", "Default"), "Default"), "Default")
```

Good:

```
Switch([Source1]&[Source2]&[Source3], "ABC", "Value", "Default")
```

### Batch Operations

- Sync in separate jobs for different populations
- Schedule off-peak hours for large syncs
- Use parallel jobs for independent mappings

## Monitoring & Alerting

### Key Metrics

```
Success Rate = (Successful Provisions / Total Provisions) * 100
Error Rate = (Failed Provisions / Total Provisions) * 100
Sync Duration = End Time - Start Time
Active Rate = (Provisioned Users / Total Employees) * 100
```

### Alert Thresholds

- ✓ Success Rate < 95% → Investigate
- ✓ Error Rate > 5% → Review logs
- ✓ Sync Duration > 2x baseline → Check performance
- ✓ Active Rate < expected → Check scoping rules

### Monthly Review Template

```
Month: January 2025
Total Users: 5,000
Provisioned: 4,850
Deprovisioned: 42
Failed: 12
Success Rate: 99.8%

Issues: [List any]
Optimizations: [List any]
Changes Made: [List any]
Next Review: February 2025
```

## Troubleshooting Guide - By Symptom

### Symptom: Users Not Syncing

```
Check List:
1. Sync job enabled?
2. Scoping rules include the user?
3. Source attributes populated?
4. Workday connection valid?
5. Attribute mapping valid?
6. No errors in logs?
```

### Symptom: Slow Sync Performance

```
Optimization Steps:
1. Profile attribute mappings
2. Remove unused mappings
3. Simplify expressions
4. Check for bottlenecks
5. Review Workday export times
6. Increase schedule frequency
```

### Symptom: Attribute Mapping Failures

```
Validation Steps:
1. Verify attribute exists in Workday
2. Check data type compatibility
3. Test expression with sample
4. Validate target attribute name
5. Check for read-only attributes
6. Review transformation logic
```

## Migration Checklist

When deploying Workday provisioning to new tenant:

- [ ] Service principal created
- [ ] Workday API credentials configured
- [ ] Attribute mappings defined and tested
- [ ] Scoping rules configured
- [ ] Test sync successful
- [ ] Pilot group synced without errors
- [ ] User validation completed
- [ ] Deprovisioning tested
- [ ] Monitoring configured
- [ ] Support training completed
- [ ] Documentation updated
- [ ] Rollback plan documented

## Bidirectional Sync - Reverse Provisioning

When using deferred email provisioning (Workday application workflow):

### Understanding the Flow

```
┌─────────────┐
│   Workday   │ Step 1: Create user (no email)
│  Employee   │
└──────┬──────┘
       │
       ├─→ [Sync 1: 2 AM] Workday → Entra
       │
       ├──────────────────────────┐
       │                          │
       │  ┌──────────┐            │
       │  │Entra User│            │
       │  │(created) │            │
       │  │(no email)│            │
       │  └────┬─────┘            │
       │       │                  │
       │       ├─→ [M365 License] │ Step 2: License assignment
       │       │      Assigned    │
       │       │                  │
       │  ┌────▼─────┐            │
       │  │Entra User│            │
       │  │(email now│            │
       │  │created)  │            │
       │  └────┬─────┘            │
       │       │                  │
       └──────┬┘                  │
              │                   │
              └─→ [Sync 2: 4 AM]  │ Step 3: Reverse sync
                 Entra → Workday  │
              │                   │
       ┌──────▼──────┐            │
       │   Workday   │            │
       │  Employee   │ Step 4: Email/UPN updated
       │(email added)│
       └─────────────┘
```

### Key Considerations for Bidirectional Sync

1. **Timing**: Schedule reverse sync AFTER M365 licensing process
2. **Scoping**: Filter on mail attribute NOT NULL to avoid syncing incomplete records
3. **Conflicts**: Establish which system is authoritative for each attribute
4. **Validation**: Test bidirectional flow with pilot group first

### Handling Email Conflicts

If email is updated in both systems:

```
Scenario: Email changed in both Workday AND Entra/M365

Solution Strategy:
├─ Option 1: Workday is authoritative
│  └─ Configure: Workday → Entra (overwrite always)
│
├─ Option 2: Entra/M365 is authoritative  
│  └─ Configure: Entra → Workday (overwrite always)
│
└─ Option 3: Last-write-wins
   └─ Configure: Latest timestamp determines source
   └─ Requires: Both systems have lastModified tracking
```

### Testing Bidirectional Sync

Before deploying:

1. Test with single user in Workday
2. Manually trigger first sync (Workday → Entra)
3. Assign M365 license to test user
4. Verify email created in Entra
5. Manually trigger second sync (Entra → Workday)
6. Verify email appears in Workday
7. Update email in Workday
8. Verify it updates in Entra
9. Update email in Entra
10. Verify reverse sync handles it correctly

## Migration Checklist

When deploying Workday provisioning to new tenant:

- [ ] Service principal created
- [ ] Workday API credentials configured
- [ ] Attribute mappings defined and tested
- [ ] Scoping rules configured
- [ ] Test sync successful
- [ ] Pilot group synced without errors
- [ ] User validation completed
- [ ] Deprovisioning tested
- [ ] **Bidirectional sync tested** (if using deferred email)
- [ ] Monitoring configured
- [ ] Support training completed
- [ ] Documentation updated
- [ ] Rollback plan documented

## Reference Architecture

```
┌─────────────────────────────────────────────────┐
│          WORKDAY PROVISIONING SYSTEM            │
├─────────────────────────────────────────────────┤
│                                                 │
│  ┌──────────────┐      ┌──────────────┐       │
│  │   Workday    │      │ Workday HCM  │       │
│  │  Tenancy     │──────│  APIs        │       │
│  └──────────────┘      └──────────────┘       │
│         │                                      │
│         │ Extract Employee Data               │
│         │                                      │
│  ┌──────────────────────────────────┐        │
│  │  Azure AD Provisioning Service   │        │
│  │  ┌────────────────────────────┐  │        │
│  │  │ Sync Job                   │  │        │
│  │  │ - Status: Enabled          │  │        │
│  │  │ - Schedule: Daily 2 AM     │  │        │
│  │  │ - Last Run: 2 hours ago    │  │        │
│  │  └────────────────────────────┘  │        │
│  │  ┌────────────────────────────┐  │        │
│  │  │ Attribute Mapping Engine   │  │        │
│  │  │ - 20+ attributes mapped    │  │        │
│  │  │ - 5 transformation exprs   │  │        │
│  │  │ - Type conversions applied │  │        │
│  │  └────────────────────────────┘  │        │
│  │  ┌────────────────────────────┐  │        │
│  │  │ Scoping Rules              │  │        │
│  │  │ - Include: ACTIVE status   │  │        │
│  │  │ - Exclude: CONTRACTOR      │  │        │
│  │  │ - 4,850 users in scope     │  │        │
│  │  └────────────────────────────┘  │        │
│  └──────────────────────────────────┘        │
│         │                                     │
│         │ Provision Users                    │
│         │ Create, Update, Delete             │
│         │                                     │
│  ┌──────────────────────────────┐           │
│  │    Azure AD User Objects     │           │
│  │    (4,850 Active Users)      │           │
│  └──────────────────────────────┘           │
│         │                                     │
│         │ Sync to Connected Apps             │
│         │ (Office 365, Teams, etc)          │
│         │                                     │
│  ┌──────────────────────────────┐           │
│  │   Connected Applications     │           │
│  │   - Office 365               │           │
│  │   - Teams                    │           │
│  │   - Other SaaS Apps          │           │
│  └──────────────────────────────┘           │
│                                              │
└──────────────────────────────────────────────┘
```

---

**Version**: 1.0  
**Last Updated**: January 2026
