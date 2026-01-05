# Workday → Entra → M365 → Workday Bidirectional Sync

## Your Provisioning Workflow

This document describes your specific provisioning pattern where:

1. **Workday**: Users created during application (no email yet)
2. **Entra**: Users provisioned from Workday
3. **M365**: License assigned → creates email/UPN
4. **Workday**: Email written back for audit trail

---

## Architecture Diagram

```
┌──────────────────────────────────────────────────────────────┐
│                    COMPLETE WORKFLOW                         │
└──────────────────────────────────────────────────────────────┘

PHASE 1: INITIAL PROVISIONING (Workday → Entra)
────────────────────────────────────────────────

  Day 1 - 2:00 AM Sync Job 1: "Workday to Entra"
  ┌──────────────────┐
  │ Workday Employee │
  │ - Employee_ID ✅ │
  │ - First_Name  ✅ │
  │ - Last_Name   ✅ │
  │ - Email       ❌ │ (empty/null)
  │ - Department  ✅ │
  └────────┬─────────┘
           │
           ├─ Scoping: Employment_Status = ACTIVE
           │
           ├─ Mapping:
           │  • Employee_ID → employeeId
           │  • First_Name → givenName
           │  • Last_Name → surname
           │  • Email → mail (null allowed)
           │  • Department → department
           │
           ▼
  ┌──────────────────────┐
  │  Azure AD User       │
  │  - employeeId    ✅  │
  │  - givenName     ✅  │
  │  - surname       ✅  │
  │  - mail          ❌  │ (empty/null)
  │  - department    ✅  │
  │  - userPrincipal ❌  │ (not yet created)
  └──────────────────────┘


PHASE 2: M365 LICENSE ASSIGNMENT
────────────────────────────────

  Day 1 - Manual: Administrator assigns M365 license to user
  
  System Action (automatic):
  ┌──────────────────────┐
  │  Azure AD User       │
  │  - employeeId    ✅  │
  │  - givenName     ✅  │
  │  - surname       ✅  │
  │  - mail          ✅  │ ← Created automatically
  │  - userPrincipal ✅  │ ← Created automatically
  │  - department    ✅  │
  └──────────────────────┘


PHASE 3: REVERSE PROVISIONING (Entra → Workday)
───────────────────────────────────────────────

  Day 1 - 4:00 AM Sync Job 2: "Entra to Workday"
  ┌──────────────────────┐
  │  Azure AD User       │
  │  - mail              │ (now populated)
  │  - userPrincipal     │ (now populated)
  └────────┬─────────────┘
           │
           ├─ Scoping: mail NOT NULL (exclude pending users)
           │
           ├─ Mapping:
           │  • mail → Work_Email
           │  • userPrincipal → UPN_Email
           │
           ▼
  ┌──────────────────────┐
  │ Workday Employee     │
  │ - Employee_ID    ✅  │
  │ - First_Name     ✅  │
  │ - Last_Name      ✅  │
  │ - Email          ✅  │ ← Updated from Entra
  │ - Department     ✅  │
  │ - UPN_Email      ✅  │ ← Added from Entra
  └──────────────────────┘


PHASE 4: ONGOING BIDIRECTIONAL SYNC
────────────────────────────────────

  Daily 2:00 AM: Workday → Entra (changes in Workday)
  Daily 4:00 AM: Entra → Workday (changes in Entra/M365)

  Example: Email change in Workday
  ┌────────────────────────┐
  │ Workday: Email updated │
  │ john.smith@company.com │
  └────────┬───────────────┘
           │
           └─→ [Next 2 AM sync] → Entra
                                 └─ mail attribute updated


  Example: Email change in M365
  ┌──────────────────────────┐
  │ Entra/M365: Email updated │
  │ updated@company.com      │
  └────────┬─────────────────┘
           │
           └─→ [Next 4 AM sync] → Workday
                                 └─ Work_Email attribute updated
```

---

## Configuration Details

### Sync Job 1: Workday → Entra (2 AM Daily)

**Name**: "Workday to Azure AD Sync"

**Source**: Workday Employee data

**Target**: Azure AD User objects

**Scoping Rules**:
```
Include ALL where:
  • Employment_Status = "ACTIVE"

Exclude:
  • Employment_Status = "TERMINATED"
  • Employment_Status = "ON_LEAVE"
  • Employee_Type = "CONTRACTOR"
```

**Attribute Mappings**:
| Workday | Azure AD | Type | Required | Notes |
|---------|----------|------|----------|-------|
| Employee_ID | employeeId | String | YES | Unique identifier |
| First_Name | givenName | String | YES | First name |
| Last_Name | surname | String | YES | Last name |
| Email | mail | String | **NO** | Populated by M365 licensing later |
| Department | department | String | NO | Optional |
| Job_Title | jobTitle | String | NO | Optional |
| Manager_ID | manager | Reference | NO | Manager link |
| Location | officeLocation | String | NO | Office location |

**Key Setting**:
- Email is **NOT required** at initial sync
- User will be created WITHOUT email/UPN
- M365 licensing will add email/UPN later

---

### Sync Job 2: Entra → Workday (4 AM Daily)

**Name**: "Azure AD to Workday Sync"

**Source**: Azure AD User objects

**Target**: Workday Employee data

**Scoping Rules**:
```
Include ONLY where:
  • mail IS NOT NULL  (has email from M365 licensing)
  • userPrincipalName IS NOT NULL

Exclude:
  • mail = NULL       (not yet licensed in M365)
  • accountEnabled = false (disabled accounts)
```

**Attribute Mappings**:
| Azure AD | Workday | Type | Notes |
|----------|---------|------|-------|
| mail | Work_Email | String | Email from M365 licensing |
| userPrincipalName | UPN_Email | String | UPN from Entra |
| objectId | Entra_ObjectId | String | Reference for troubleshooting |

**Key Setting**:
- Scoping rule filters out users still waiting for M365 license
- Only syncs email back AFTER it's created by M365
- Audit trail: Workday origin → Entra creation → M365 email → Workday update

---

## Timeline Example

### User "Jane Doe" - Complete Flow

```
Tuesday, Jan 5, 2025
─────────────────────

10:30 AM  - Jane applies for job in career portal
10:45 AM  - HR creates Jane in Workday:
            • Employee_ID: EMP123456
            • First_Name: Jane
            • Last_Name: Doe
            • Email: (empty/null)  ← No email yet
            • Department: Engineering

Wednesday, Jan 6, 2025
──────────────────────

2:00 AM   - SYNC JOB 1: Workday → Entra
            ✓ Jane's record synced
            ✓ Azure AD user created
            ✓ No email in Entra yet
            ✓ No UPN created yet

10:00 AM  - HR approves Jane and assigns M365 license
            [System automatically creates]:
            • Email: jane.doe@company.com
            • UPN: jane.doe@company.com
            • Full mailbox activated

4:00 AM   - SYNC JOB 2: Entra → Workday
  (next day)✓ Syncs email back to Workday
            ✓ Work_Email: jane.doe@company.com
            ✓ UPN_Email: jane.doe@company.com
            ✓ Complete audit trail recorded

Result
──────
Workday:  Has email (updated by M365 → Entra → Workday flow)
Entra:    Has user with email/UPN from M365 licensing
M365:     Has licensed user with mailbox
Audit:    Complete trail of all changes
```

---

## Handling Edge Cases

### Case 1: User Licensed BEFORE Sync 2

**Timeline**:
- 2:00 AM: Sync Job 1 (Workday → Entra) - User created, no email
- 2:30 AM: HR manually licenses user in M365
- 4:00 AM: Sync Job 2 (Entra → Workday) - Email synced back

**Result**: ✅ Works correctly - email synced at 4 AM

---

### Case 2: Email Updated in Workday After M365 Licensing

**Timeline**:
- User licensed in M365, email created
- Email synced back to Workday (4 AM sync)
- Admin updates email in Workday to different address
- 2 AM next day: Workday → Entra sync overwrites Entra email

**Result**: ✅ Workday is authoritative for email after initial sync

---

### Case 3: Multiple Users Awaiting M365 License

**Timeline**:
- Multiple users created in Workday
- Batch licensed in M365 (not all at same time)
- 4 AM sync only syncs users with email (scoping rule)

**Result**: ✅ Only users with email synced - others wait for their email

---

## Monitoring Checklist

### Daily Monitoring

- [ ] **2 AM Sync Job 1 (Workday → Entra)**
  - Check: No errors in sync logs
  - Verify: New users appear in Entra
  - Check: No email attribute errors (expected to be null)

- [ ] **4 AM Sync Job 2 (Entra → Workday)**
  - Check: No errors in sync logs
  - Verify: Email syncs back to Workday
  - Check: Scoping rule filters correctly (only licensed users)

### Weekly Monitoring

- [ ] Sample user audit trail:
  - Created in Workday ✓
  - Synced to Entra ✓
  - Licensed in M365 ✓
  - Email synced back to Workday ✓

- [ ] Check data consistency:
  - Email in Entra = Email in Workday?
  - UPN correct format?
  - No orphaned users?

### Issues to Watch For

1. **Email NOT Syncing Back**
   - Verify Sync Job 2 is enabled
   - Check scoping rule (mail NOT NULL)
   - Verify Workday target attribute exists
   - Check for duplicate email errors

2. **Users Stuck Without Email**
   - Check if M365 license was assigned
   - Verify Entra email attribute populated
   - Check Sync Job 2 scoping rule
   - Manual license assignment may be pending

3. **Email Conflicts**
   - Multiple users same email?
   - Check Workday validation rules
   - Check for duplicate prevention
   - Verify email format in both systems

---

## Testing Before Production

### Test 1: Single User Deferred Email

```
Step 1: Create test user in Workday WITHOUT email
Step 2: Run Sync Job 1 manually
Step 3: Verify user created in Entra without email
Step 4: Manually assign M365 license
Step 5: Verify email/UPN created in Entra
Step 6: Run Sync Job 2 manually
Step 7: Verify email synced back to Workday

Expected: Complete flow without errors
```

### Test 2: Bidirectional Email Updates

```
Step 1: Complete Test 1 above
Step 2: Update email in Workday
Step 3: Run Sync Job 1
Step 4: Verify email updated in Entra
Step 5: Update email in Entra directly
Step 6: Run Sync Job 2
Step 7: Verify email updated in Workday
Step 8: Confirm no conflicts or errors

Expected: Updates flow bidirectionally
```

### Test 3: Scoping Rule Filters

```
Step 1: Create 5 test users in Workday
Step 2: Run Sync Job 1 - all created in Entra
Step 3: License only 2 of them in M365
Step 4: Run Sync Job 2
Step 5: Verify only 2 emails synced back

Expected: Scoping rule filters correctly
```

---

## Configuration Templates

### Sync Job 1: Workday → Entra (Template)

```json
{
  "Name": "Workday to Azure AD - Deferred Email",
  "Enabled": true,
  "ScheduleMinutes": 1440,
  "ScheduleHour": 2,
  "SourceObjectName": "Employee",
  "TargetObjectName": "User",
  "ScopingRules": {
    "Include": [
      {"attribute": "Employment_Status", "operator": "EQUALS", "value": "ACTIVE"}
    ],
    "Exclude": [
      {"attribute": "Employment_Status", "operator": "EQUALS", "value": "TERMINATED"}
    ]
  },
  "AttributeMappings": [
    {"source": "Employee_ID", "target": "employeeId", "type": "String", "required": true},
    {"source": "First_Name", "target": "givenName", "type": "String", "required": true},
    {"source": "Last_Name", "target": "surname", "type": "String", "required": true},
    {"source": "Email", "target": "mail", "type": "String", "required": false},
    {"source": "Department", "target": "department", "type": "String", "required": false}
  ]
}
```

### Sync Job 2: Entra → Workday (Template)

```json
{
  "Name": "Azure AD to Workday - Email Writeback",
  "Enabled": true,
  "ScheduleMinutes": 1440,
  "ScheduleHour": 4,
  "SourceObjectName": "User",
  "TargetObjectName": "Employee",
  "ScopingRules": {
    "Include": [
      {"attribute": "mail", "operator": "NOT_EQUALS", "value": "null"},
      {"attribute": "userPrincipalName", "operator": "NOT_EQUALS", "value": "null"}
    ]
  },
  "AttributeMappings": [
    {"source": "mail", "target": "Work_Email", "type": "String"},
    {"source": "userPrincipalName", "target": "UPN_Email", "type": "String"},
    {"source": "objectId", "target": "Entra_ObjectId", "type": "String"}
  ]
}
```

---

## Troubleshooting Guide

### Problem: Email Not Syncing Back to Workday

```
Diagnosis Steps:
1. Check Sync Job 2 is enabled
   → Go to Azure AD > Enterprise Apps > [Workday] > Provisioning
   → Verify "Provisioning Status" = Enabled

2. Check scoping rule in Sync Job 2
   → Verify: mail NOT NULL
   → Check: User has email in Entra

3. Verify target attribute in Workday
   → Check: "Work_Email" field exists in Workday
   → Verify: Field has write permissions
   → Check: Field data type matches (String)

4. Review sync logs
   → Check for error messages
   → Look for attribute name mismatch
   → Verify no validation errors in Workday

5. Manual test
   → Pick user with email in Entra
   → Force sync of that user
   → Check Workday for email
```

### Problem: Users Stuck Without Email

```
Diagnosis:
1. Is M365 license assigned?
   → Check user in M365 admin center
   → Verify license shows as "active"
   → If not assigned: Assign license, wait for email creation

2. Is email in Entra?
   → Check user in Azure AD
   → Verify "mail" attribute populated
   → If not populated: Wait for M365 sync (can take hours)

3. Is Sync Job 2 running?
   → Check logs for Sync Job 2
   → Verify it ran at 4 AM
   → Check for any errors
   → If failed: Check scoping rule filter

4. Is scoping rule filtering user?
   → Check: Does user have email? (required for scope)
   → Check: Is user enabled? (accountEnabled = true)
   → Check: No other exclude rules matching
```

### Problem: Email Updates Not Bidirectional

```
Check Sync Job 1 (Workday → Entra):
1. Is it enabled?
2. Did it run at 2 AM?
3. Are attribute mappings correct?
4. Check for error logs

Check Sync Job 2 (Entra → Workday):
1. Is it enabled?
2. Did it run at 4 AM?
3. Are attribute mappings correct?
4. Check scoping rule (mail NOT NULL)?
5. Verify target attribute writable in Workday
```

---

## Best Practices for This Workflow

✅ **DO**:
- Schedule Sync Job 2 several hours AFTER M365 licensing typically completes
- Include scoping rule to filter incomplete records (mail NOT NULL)
- Monitor both sync jobs daily
- Keep audit trail of email changes
- Test with pilot group before full rollout
- Document the complete flow for support team

❌ **DON'T**:
- Set email as "required" in Sync Job 1 (users created without email)
- Schedule both sync jobs at same time
- Assume email will be instantly created in Entra after M365 license
- Remove scoping rule from Sync Job 2 (will try to sync null emails)
- Use only one direction (bidirectional is important for accuracy)

---

## Summary

Your workflow creates a **complete audit trail**:

```
Workday (creation, no email)
    ↓
Azure AD (provisioning, no email)
    ↓
M365 License (creates email/UPN)
    ↓
Workday (email writeback, complete record)
```

This ensures:
- ✅ Users created before email assigned
- ✅ M365 licensing is independent of Workday email
- ✅ Email synced back for complete audit trail
- ✅ Bidirectional updates supported
- ✅ Clear audit of where each attribute came from

---

**Version**: 1.0  
**Last Updated**: January 2026
