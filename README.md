# Workday Provisioning Analysis Suite

A comprehensive toolset for extracting, documenting, validating, and analyzing Workday provisioning flows in Azure/Entra.

## Overview

This suite provides four main capabilities:

1. **Extract** - Pull all Workday-related objects from Azure/Entra
2. **Document** - Create detailed provisioning flow documentation
3. **Validate** - Check configurations for syntax errors and best practices
4. **Analyze** - Generate flow diagrams and detailed analysis

## Special Workflows

### Deferred Email Provisioning

If your organization uses this pattern:

- Users created in Workday **without email** (during application process)
- Provisioned to Entra
- M365 license assigned → creates email/UPN
- Email written back to Workday for audit trail

📖 **See**: [BIDIRECTIONAL-SYNC-WORKFLOW.md](BIDIRECTIONAL-SYNC-WORKFLOW.md)

This document covers:

- Complete workflow architecture
- Timeline and phases
- Configuration templates
- Bidirectional sync setup
- Testing procedures
- Troubleshooting

## Quick Start

### Prerequisites

- PowerShell 5.1 or higher
- Microsoft Graph PowerShell module
- Azure/Entra admin consent access
- Workday provisioning already configured in your tenant

### Installation

1. **Clone or download** this repository

2. **Install required PowerShell modules** (scripts will prompt if missing):

   ```powershell
   Install-Module -Name Microsoft.Graph.Identity.ServicePrincipal -Scope CurrentUser
   Install-Module -Name Microsoft.Graph.Applications -Scope CurrentUser
   ```

3. **Allow script execution** (if needed):

   ```powershell
   Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
   ```

## Usage

Run the scripts in sequence to get complete analysis:

### Step 1: Extract Workday Objects

```powershell
cd d:\projects\workday-provisioning
.\scripts\Get-WorkdayEntraObjects.ps1 -OutputPath "./output"
```

**What it does:**

- Connects to Microsoft Graph
- Finds all Workday service principals
- Extracts provisioning configurations
- Exports attribute mappings
- Generates extraction summary

**Output files:**

- `workday_service_principals.json`
- `provisioning_configs.json`
- `attribute_mappings.json`
- `directory_extensions.json`
- `app_roles.json`
- `extraction_summary.json`

### Step 2: Generate Documentation

```powershell
.\scripts\Document-ProvisioningFlows.ps1 -InputPath "./output" -OutputPath "./docs"
```

**What it does:**

- Creates executive overview
- Documents all attribute mappings
- Details configuration settings
- Provides troubleshooting guide
- Generates index

**Output files:**

- `01-Overview.md` - High-level summary
- `02-AttributeMappings.md` - All attribute mappings
- `03-ConfigurationDetails.md` - Detailed configurations
- `04-JSONReference.md` - JSON reference guide
- `05-Troubleshooting.md` - Troubleshooting tips
- `INDEX.md` - Documentation index

### Step 3: Validate Configurations

```powershell
.\scripts\Validate-ProvisioningConfigs.ps1 -InputPath "./output" -OutputPath "./output"
```

**What it does:**

- Validates JSON syntax
- Checks required fields
- Verifies GUID formats
- Validates attribute mappings
- Checks best practices

**Output files:**

- `validation_report.md` - Human-readable report
- `validation_report.json` - Detailed results

### Step 4: Analyze Flows

```powershell
.\scripts\Analyze-ProvisioningFlows.ps1 -InputPath "./output" -OutputPath "./docs"
```

**What it does:**

- Creates flow diagrams (Mermaid format)
- Generates data flow analysis
- Documents integration points
- Provides sync schedule details
- Includes troubleshooting scenarios

**Output files:**

- `06-FlowAnalysis.md` - Complete flow analysis with diagrams

### Run All Steps at Once

```powershell
.\scripts\Get-WorkdayEntraObjects.ps1 -OutputPath "./output"; `
.\scripts\Document-ProvisioningFlows.ps1 -InputPath "./output" -OutputPath "./docs"; `
.\scripts\Validate-ProvisioningConfigs.ps1 -InputPath "./output" -OutputPath "./output"; `
.\scripts\Analyze-ProvisioningFlows.ps1 -InputPath "./output" -OutputPath "./docs"
```

## Project Structure

```text
workday-provisioning/
├── README.md                 # This file
├── scripts/
│   ├── Get-WorkdayEntraObjects.ps1      # Extract Entra objects
│   ├── Document-ProvisioningFlows.ps1   # Generate documentation
│   ├── Validate-ProvisioningConfigs.ps1 # Validate syntax
│   └── Analyze-ProvisioningFlows.ps1    # Create flow analysis
├── output/
│   ├── *.json files          # Extracted configurations
│   ├── validation_report.md  # Validation results
│   └── validation_report.json
├── docs/
│   ├── INDEX.md              # Documentation index
│   ├── 01-Overview.md
│   ├── 02-AttributeMappings.md
│   ├── 03-ConfigurationDetails.md
│   ├── 04-JSONReference.md
│   ├── 05-Troubleshooting.md
│   └── 06-FlowAnalysis.md
└── configs/                  # For custom configurations
```

## Key Concepts

### Service Principals

A Service Principal represents the Workday application in Azure AD. Each provisioning flow is associated with a service principal that has permissions to read from Workday and write to Azure AD.

### Synchronization Jobs

Sync jobs contain the actual provisioning logic:

- **Status**: Enabled or Disabled
- **Schedule**: How often sync runs
- **Progress**: Number of users processed
- **Errors**: Any provisioning failures

### Attribute Mappings

Attribute mappings define how Workday employee data transforms to Azure AD user attributes:

- **Source**: Workday system attribute (e.g., `employee_id`)
- **Target**: Azure AD attribute (e.g., `employeeId`)
- **Transformation**: Optional expression to transform the value

### Scoping Rules

Scoping rules determine which users get provisioned:

- Based on user attributes
- Can include or exclude specific users
- Essential for pilot deployments

## Validation Checklist

Before deploying provisioning flows:

- [ ] All service principals have correct permissions
- [ ] Attribute mappings use valid Azure AD attribute names
- [ ] Source attributes exist in Workday system
- [ ] Scoping rules match business requirements
- [ ] Sync schedule is appropriate for your organization
- [ ] Test sync completed without errors
- [ ] Audit logs show successful provisioning
- [ ] User accounts have expected attribute values

## Common Issues and Solutions

### Issue: "No Workday Service Principal Found"

**Causes:**

- Workday app not installed
- Different naming convention
- Insufficient permissions

**Solutions:**

1. Verify Workday connector is installed in your tenant
2. Check the exact display name of the app
3. Ensure you have `Application.Read.All` permission

### Issue: "Provisioning Not Running"

**Check:**

1. Sync job status (should be "Enabled")
2. Last sync execution time
3. Error logs for failures

### Issue: "Attribute Mappings Not Applied"

**Validate:**

1. Source attributes exist in Workday
2. Target attribute syntax is correct
3. Transformation expressions are valid
4. Scoping rules include the target user

## Reports Generated

### Extraction Report

- Summary of all discovered objects
- Service principal details
- Provisioning configuration count
- Mapping count and types

### Validation Report

- Syntax validation results
- Field validation
- Best practices checks
- Recommendations for fixes

### Documentation

- Architecture overview
- Attribute mapping details
- Configuration specifications
- Troubleshooting guides

### Flow Analysis

- System component diagrams
- Data flow visualization
- Integration point mapping
- Performance monitoring guidance

## Best Practices

1. **Regular Monitoring**: Check provisioning status weekly
2. **Documentation**: Keep attribute mappings documented
3. **Testing**: Always test changes in a pilot scope first
4. **Audit**: Review provisioning logs monthly
5. **Optimization**: Regularly review and optimize mappings

## Troubleshooting

### Script Won't Run

```powershell
# Check execution policy
Get-ExecutionPolicy

# Update if needed
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser

# Run script with full path
& "d:\projects\workday-provisioning\scripts\Get-WorkdayEntraObjects.ps1"
```

### Microsoft Graph Connection Issues

```powershell
# Ensure you're using the latest module
Update-Module -Name Microsoft.Graph.Identity.ServicePrincipal

# Clear any cached credentials
$profile | Remove-Item -Force -ErrorAction SilentlyContinue

# Reconnect
Connect-MgGraph -Scopes "Application.Read.All"
```

### JSON Parse Errors

Ensure JSON files are valid:

```powershell
Get-Content "output\provisioning_configs.json" | ConvertFrom-Json
```

## Security Considerations

1. **Credentials**: Scripts use interactive authentication - no credentials stored
2. **Logs**: PowerShell keeps command history - consider clearing when done
3. **JSON Files**: Contain sensitive configuration data - secure appropriately
4. **API Access**: Use least-privilege service accounts for Workday connection

## Support and Contributing

### Getting Help

1. Check documentation in `/docs` folder
2. Review validation report for specific errors
3. Check troubleshooting section in generated documentation
4. Review Microsoft Graph documentation

### Extending the Suite

To add custom validation or analysis:

1. Duplicate a script as template
2. Modify to add your logic
3. Run and generate new reports
4. Integrate with existing documentation

## License

Use freely for your organization's needs.

## Related Resources

- [Microsoft Workday Connector](https://learn.microsoft.com/en-us/azure/active-directory/app-provisioning/workday-integration-reference)
- [Attribute Mapping Documentation](https://learn.microsoft.com/en-us/azure/active-directory/app-provisioning/customize-application-attributes)
- [Microsoft Graph PowerShell](https://learn.microsoft.com/en-us/powershell/microsoftgraph/overview)
- [Azure AD Provisioning](https://learn.microsoft.com/en-us/azure/active-directory/app-provisioning/app-provisioning-overview)

---

**Version**: 1.0  
**Last Updated**: January 2026
