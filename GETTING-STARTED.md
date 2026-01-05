# Workday Provisioning Suite - Setup & Getting Started

## What You Have

This is a complete enterprise-grade Workday provisioning analysis and documentation suite. It includes:

### Four Automated Scripts

1. **Get-WorkdayEntraObjects.ps1** - Extracts all Workday-related configurations from Azure/Entra
2. **Document-ProvisioningFlows.ps1** - Generates comprehensive documentation
3. **Validate-ProvisioningConfigs.ps1** - Validates syntax and best practices
4. **Analyze-ProvisioningFlows.ps1** - Creates flow diagrams and technical analysis

### Supporting Files

- **RUN-ALL.ps1** - Master orchestration script (runs all 4 steps)
- **README.md** - Complete usage guide
- **QUICK-REFERENCE.md** - Command cheat sheet
- **BEST-PRACTICES.md** - Patterns, examples, and optimization tips
- **provisioning-schema.json** - Validation schema

## Quick Start (5 minutes)

### Step 1: Prepare Your Environment

Open PowerShell as Administrator:

```powershell
# Navigate to project
cd d:\projects\workday-provisioning

# Check PowerShell version (should be 5.1 or higher)
$PSVersionTable.PSVersion
```

### Step 2: Run the Master Script

```powershell
# Execute complete analysis
.\RUN-ALL.ps1
```

This will:

1. Prompt you to authenticate with Azure
2. Extract all Workday objects
3. Generate documentation
4. Validate configurations
5. Create flow analysis
6. Save everything to `output/` and `docs/`

### Step 3: Review Results

Open the generated documentation:

```powershell
# Open documentation index
Start-Process "d:\projects\workday-provisioning\docs\INDEX.md"

# Or view in VS Code
code d:\projects\workday-provisioning\docs\INDEX.md
```

## What Gets Generated

### In `output/` folder

- **extraction_summary.json** - Overview of all found objects
- **workday_service_principals.json** - Workday app details
- **provisioning_configs.json** - All sync job configurations
- **attribute_mappings.json** - How Workday attributes map to Azure AD
- **validation_report.md** - Any issues found
- **validation_report.json** - Detailed validation data

### In `docs/` folder

- **INDEX.md** - Start here! Links to all documents
- **01-Overview.md** - Executive summary
- **02-AttributeMappings.md** - All attribute mappings explained
- **03-ConfigurationDetails.md** - Sync job details
- **04-JSONReference.md** - Guide to JSON files
- **05-Troubleshooting.md** - Common issues & fixes
- **06-FlowAnalysis.md** - Flow diagrams & analysis

## File Structure

```
d:\projects\workday-provisioning\
├── README.md                           # Full documentation
├── QUICK-REFERENCE.md                  # Command cheat sheet
├── BEST-PRACTICES.md                   # Patterns & examples
├── GETTING-STARTED.md                  # This file
├── RUN-ALL.ps1                         # Master orchestration script
│
├── scripts/                            # PowerShell scripts
│   ├── Get-WorkdayEntraObjects.ps1
│   ├── Document-ProvisioningFlows.ps1
│   ├── Validate-ProvisioningConfigs.ps1
│   └── Analyze-ProvisioningFlows.ps1
│
├── configs/                            # Configuration files
│   └── provisioning-schema.json
│
├── output/                             # Generated JSON exports
│   ├── workday_service_principals.json
│   ├── provisioning_configs.json
│   ├── attribute_mappings.json
│   ├── validation_report.md
│   └── validation_report.json
│
└── docs/                               # Generated documentation
    ├── INDEX.md
    ├── 01-Overview.md
    ├── 02-AttributeMappings.md
    ├── 03-ConfigurationDetails.md
    ├── 04-JSONReference.md
    ├── 05-Troubleshooting.md
    └── 06-FlowAnalysis.md
```

## Key Features

### 1. Automatic Extraction

- Connects to your Azure tenant
- Finds all Workday-related objects
- Exports configurations as JSON
- No manual data gathering needed

### 2. Comprehensive Documentation

- Executive overviews
- Attribute mapping details
- Configuration specifications
- Troubleshooting guides
- All in Markdown format

### 3. Automatic Validation

- Checks JSON syntax
- Verifies required fields
- Validates GUID formats
- Checks best practices
- Generates validation report

### 4. Flow Analysis

- System architecture diagrams (Mermaid format)
- Data flow visualization
- Integration point mapping
- Performance guidance
- Sync schedule analysis

## Use Cases

### Use Case 1: Document Current State

**Goal**: Create documentation of what's deployed

**Steps**:

```powershell
.\RUN-ALL.ps1
# Review output in docs/
```

### Use Case 2: Audit Provisioning

**Goal**: Verify all mappings are correct

**Steps**:

```powershell
.\scripts\Get-WorkdayEntraObjects.ps1 -OutputPath "./output"
.\scripts\Validate-ProvisioningConfigs.ps1 -InputPath "./output" -OutputPath "./output"
# Review output/validation_report.md
```

### Use Case 3: Troubleshoot Issues

**Goal**: Understand the flow to debug problems

**Steps**:

```powershell
.\RUN-ALL.ps1
# Open docs/06-FlowAnalysis.md
# Follow troubleshooting guide
```

### Use Case 4: Plan Migration

**Goal**: Document for new tenant deployment

**Steps**:

```powershell
.\RUN-ALL.ps1
# Use output/ JSON files as migration data
# Use docs/ as deployment guide
```

## Authentication

The scripts use interactive authentication (no stored credentials):

1. Script prompts for login
2. Opens browser for Azure sign-in
3. You authenticate with your account
4. Access granted to Microsoft Graph API

**Required Permissions**:

- `Application.Read.All` - Read applications and service principals
- `Directory.Read.All` - Read directory data

## Troubleshooting Setup

### Issue: "Cannot find module 'Microsoft.Graph.Identity.ServicePrincipal'"

**Solution**:

```powershell
Install-Module -Name Microsoft.Graph.Identity.ServicePrincipal -Scope CurrentUser -Force
Install-Module -Name Microsoft.Graph.Applications -Scope CurrentUser -Force
```

### Issue: "No Workday Service Principal Found"

**Check**:

1. Navigate to Azure AD > Enterprise Applications
2. Search for "Workday"
3. Verify app is installed
4. Note the exact display name

**Solution**: The extraction will still complete - check output/workday_service_principals.json

### Issue: "Access Denied" during authentication

**Check**:

1. You have Azure AD admin access
2. You have global reader or application admin role
3. Try disconnecting and reconnecting:

```powershell
Disconnect-MgGraph
.\RUN-ALL.ps1
```

### Issue: Script Won't Execute

**Enable scripts**:

```powershell
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
```

## Next Steps After Setup

### 1. Review Documentation (30 min)

- Read `docs/INDEX.md`
- Understand your current provisioning setup
- Note any configuration details

### 2. Check Validation Report (15 min)

- Review `output/validation_report.md`
- Address any errors or warnings
- Plan any corrective actions

### 3. Analyze Flows (20 min)

- Read `docs/06-FlowAnalysis.md`
- Understand data flows
- Review attribute mappings

### 4. Plan Improvements (ongoing)

- Use BEST-PRACTICES.md for optimization
- Plan any configuration changes
- Schedule regular reviews (monthly)

## Key Documents to Read

### For Executives

1. Read: `docs/01-Overview.md`
2. Time: 10 minutes
3. What you'll know: What Workday provisioning is deployed

### For Administrators

1. Read: `docs/INDEX.md` (links to all documents)
2. Read: `docs/02-AttributeMappings.md`
3. Read: `docs/06-FlowAnalysis.md`
4. Time: 1-2 hours
5. What you'll know: Complete configuration details

### For Architects

1. Read: `BEST-PRACTICES.md`
2. Read: `docs/06-FlowAnalysis.md`
3. Review: `output/*.json` files
4. Time: 2-3 hours
5. What you'll know: Optimization opportunities

### For Developers

1. Read: `QUICK-REFERENCE.md`
2. Review: `output/*.json` schema
3. Read: `BEST-PRACTICES.md` patterns
4. Time: 1-2 hours
5. What you'll know: Integration patterns

## Regular Maintenance

### Weekly

- Check provisioning status
- Review sync logs for errors

### Monthly

- Review documentation for accuracy
- Check attribute mappings are still valid
- Run validation script

### Quarterly

- Complete audit of configuration
- Optimization review
- Update documentation

## Integration with Other Tools

### Export to Excel

```powershell
# Extract attribute mappings
$mappings = Get-Content "output\attribute_mappings.json" | ConvertFrom-Json
$mappings | Export-Csv "attribute-mappings.csv" -NoTypeInformation
```

### Generate HTML Report

```powershell
# Convert Markdown to HTML
$markdown = Get-Content "docs\01-Overview.md" | Out-String
# Use Pandoc or VS Code to convert
```

### Share with Team

1. Copy entire `docs/` folder
2. Share link to `INDEX.md`
3. All documentation is Markdown (viewable in any editor)

## Security Notes

1. **No credentials stored** - Scripts use interactive auth only
2. **Sensitive data** - JSON files contain configuration details
3. **Access control** - Share documentation carefully
4. **Audit logs** - All extraction is logged in Azure AD
5. **Data retention** - Clean up old output files periodically

## Success Metrics

After running this suite, you should have:

- ✓ Complete inventory of Workday provisioning configuration
- ✓ Documentation of all attribute mappings
- ✓ Validation report showing any issues
- ✓ Flow diagrams showing data movement
- ✓ Troubleshooting guide for common issues
- ✓ JSON exports for migration/backup

## Support

### If Scripts Fail

1. Check error message in console
2. Review README.md section "Troubleshooting"
3. Verify prerequisites are installed
4. Check Azure AD permissions

### If Documentation Is Missing

1. Ensure all scripts ran successfully
2. Check output/ and docs/ folders exist
3. Run individual scripts to debug
4. Review script output for errors

### If Validation Shows Errors

1. Review `output/validation_report.md`
2. Check `docs/05-Troubleshooting.md`
3. Review corresponding JSON files
4. Fix issues in Azure AD configuration

## What's Next?

1. **First Time**: Run `.\RUN-ALL.ps1` now
2. **Review**: Read `docs/INDEX.md`
3. **Understand**: Study `docs/02-AttributeMappings.md`
4. **Optimize**: Review `BEST-PRACTICES.md`
5. **Monitor**: Schedule monthly validation runs

## Questions?

### How do I

**...run just one script?**

```powershell
.\scripts\Get-WorkdayEntraObjects.ps1 -OutputPath "./output"
```

**...update documentation after changes?**

```powershell
.\RUN-ALL.ps1  # Re-run after making changes
```

**...validate only without documenting?**

```powershell
.\scripts\Get-WorkdayEntraObjects.ps1 -OutputPath "./output"
.\scripts\Validate-ProvisioningConfigs.ps1 -InputPath "./output" -OutputPath "./output"
```

**...export to different format?**
See "Integration with Other Tools" section above

**...schedule regular runs?**
Create Windows Task Scheduler task pointing to `RUN-ALL.ps1`

---

**Ready to begin?** Run this command:

```powershell
cd d:\projects\workday-provisioning
.\RUN-ALL.ps1
```

Then open `docs/INDEX.md` to explore your provisioning configuration!

**Version**: 1.0  
**Last Updated**: January 2026
