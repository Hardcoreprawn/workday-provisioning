# Quick Reference Guide

## Command Cheat Sheet

### Extract Workday Objects
```powershell
cd d:\projects\workday-provisioning
.\scripts\Get-WorkdayEntraObjects.ps1 -OutputPath "./output"
```

### Generate Documentation
```powershell
.\scripts\Document-ProvisioningFlows.ps1 -InputPath "./output" -OutputPath "./docs"
```

### Validate Configurations
```powershell
.\scripts\Validate-ProvisioningConfigs.ps1 -InputPath "./output" -OutputPath "./output"
```

### Analyze Flows
```powershell
.\scripts\Analyze-ProvisioningFlows.ps1 -InputPath "./output" -OutputPath "./docs"
```

### Run Everything
```powershell
.\RUN-ALL.ps1
```

## Output Files Summary

| File | Purpose | Location |
|------|---------|----------|
| extraction_summary.json | Overview of all extractions | output/ |
| workday_service_principals.json | Service principal details | output/ |
| provisioning_configs.json | Sync job configurations | output/ |
| attribute_mappings.json | All attribute mappings | output/ |
| validation_report.md | Validation results | output/ |
| validation_report.json | Detailed validation data | output/ |
| INDEX.md | Documentation index | docs/ |
| 01-Overview.md | High-level overview | docs/ |
| 02-AttributeMappings.md | Detailed attribute mappings | docs/ |
| 03-ConfigurationDetails.md | Configuration details | docs/ |
| 04-JSONReference.md | JSON reference guide | docs/ |
| 05-Troubleshooting.md | Troubleshooting tips | docs/ |
| 06-FlowAnalysis.md | Flow diagrams and analysis | docs/ |

## Key Attributes to Validate

### User Attributes

Common Workday attributes mapped to Azure AD:

| Workday | Azure AD | Type | Required |
|---------|----------|------|----------|
| Employee_ID | employeeId | String | Yes |
| First_Name | givenName | String | Yes |
| Last_Name | surname | String | Yes |
| Email | userPrincipalName | String | Yes |
| Email | mail | String | Yes |
| Department | department | String | No |
| Job_Title | jobTitle | String | No |
| Manager_ID | manager | Reference | No |
| Cost_Center | costCenter | String | No |
| Location | officeLocation | String | No |

### Validation Checks

Before deploying:

```
✓ Source attributes exist in Workday
✓ Target attributes valid in Azure AD
✓ Attribute names case-sensitive match
✓ Data types compatible
✓ Transformation expressions valid
✓ Null handling configured
✓ Scoping rules appropriate
✓ Schedule interval reasonable
✓ Error notifications configured
✓ Audit logging enabled
```

## Common Workday Integration Scenarios

### Scenario 1: Full User Provisioning

**Flow**: Workday Employee → Azure AD User

**Typical Mappings**:
- Employee ID → employeeId
- First Name → givenName
- Last Name → surname
- Work Email → userPrincipalName & mail
- Department → department
- Manager → manager (object reference)

**Scope**: All active employees

**Frequency**: Daily or hourly

### Scenario 2: Termination Flow

**Flow**: Workday Termination → Azure AD Disable

**Typical Mappings**:
- Employment Status → accountEnabled (converts to boolean)
- Termination Date → (triggers disable if date passed)

**Scope**: Termed employees

**Frequency**: Daily

### Scenario 3: Dynamic Groups

**Flow**: Workday Department → Azure AD Groups

**Typical Mappings**:
- Department → group membership
- Job Level → security group assignment

**Scope**: Department-based groups

**Frequency**: Daily

## Troubleshooting Quick Commands

### View Last N Provisioning Actions
```powershell
$sp = Get-MgServicePrincipal -Filter "displayName eq 'Workday'"
Get-MgServicePrincipalSynchronizationJob -ServicePrincipalId $sp.Id | 
    Select-Object Id, Status, LastExecution, Progress
```

### Check Sync Job Errors
```powershell
$sp = Get-MgServicePrincipal -Filter "displayName eq 'Workday'"
$job = Get-MgServicePrincipalSynchronizationJob -ServicePrincipalId $sp.Id
Get-MgServicePrincipalSynchronizationJobSchema -ServicePrincipalId $sp.Id -SynchronizationJobId $job.Id
```

### Test Attribute Mapping
```powershell
$testUser = Get-MgUser -Filter "userPrincipalName eq 'user@example.com'"
$testUser | Select-Object employeeId, givenName, surname, mail, department
```

## Performance Tuning

### Optimize Sync Speed

1. **Reduce Attribute Count**: Only map necessary attributes
2. **Simplify Expressions**: Minimize transformation complexity
3. **Adjust Schedule**: Consider off-peak hours for large syncs
4. **Batch Processing**: Use directory extensions for bulk updates
5. **Parallel Jobs**: If multiple populations needed

### Monitor Performance

- **Sync Duration**: Should complete within scheduled interval
- **Success Rate**: Aim for >99% successful provisions
- **Error Types**: Review and fix common errors
- **API Limits**: Azure AD has rate limits - monitor usage

## Security Best Practices

1. **Least Privilege**: Use minimal permissions for service accounts
2. **Credential Rotation**: Rotate Workday API credentials quarterly
3. **Audit Logging**: Enable and monitor provisioning logs
4. **Data Classification**: Mark provisioning logs as sensitive
5. **Access Control**: Limit admin access to provisioning configs
6. **Encryption**: Ensure Workday connection uses HTTPS
7. **MFA**: Enable MFA for admin access to Azure AD

## Monitoring Checklist

### Weekly
- [ ] Sync job status is running
- [ ] No permanent errors in logs
- [ ] Recent users successfully provisioned

### Monthly
- [ ] Attribute mappings match business requirements
- [ ] Termination flows working correctly
- [ ] Performance metrics acceptable

### Quarterly
- [ ] Complete audit of provisioning rules
- [ ] Review and update documentation
- [ ] Performance optimization review
- [ ] Security audit of admin access

## Reference Documentation

- [Workday Azure AD Connector](https://learn.microsoft.com/en-us/azure/active-directory/app-provisioning/workday-integration-reference)
- [Attribute Mapping Reference](https://learn.microsoft.com/en-us/azure/active-directory/app-provisioning/customize-application-attributes)
- [Azure AD Provisioning Logs](https://learn.microsoft.com/en-us/azure/active-directory/reports-monitoring/concept-provisioning-logs)
- [Graph PowerShell Module](https://learn.microsoft.com/en-us/powershell/microsoftgraph/overview)

---

**For Complete Documentation**: Open `docs/INDEX.md`
