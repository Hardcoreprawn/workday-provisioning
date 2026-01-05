<#
.SYNOPSIS
    Identifies duplicate Entra ID accounts created by errant provisioning.

.DESCRIPTION
    This script retrieves users from Entra ID and identifies accounts with matching email patterns
    (original email vs email with '1' or '2' appended). It classifies pairs into two categories:
    
    Note: Any account pair matching the email suffix pattern is inherently a provisioning issue.
    
    1. DUPLICATE PAIRS - Same person with two accounts (matching EmployeeID and GUID)
       - Clear consolidation needed
       - Shows which attributes to copy from duplicate to original
       - Identifies which account to delete
    
    2. SUSPICIOUS ACCOUNTS - Grey area cases (matching EmployeeID with suffix, unclear GUID)
       - Likely created by errant provisioning agent
       - Causing authentication failures in downstream systems (SAP, etc.)
       - Requires investigation and attribute consolidation before deletion

.PARAMETER ExportPath
    Optional path to export the results to CSV for further analysis.

.PARAMETER Interactive
    When specified, enables interactive review mode. Shows each account pair side-by-side in
    fixed-width columns with clear visual separation. Pauses after each pair for review before
    moving to the next account. Ideal for step-by-step remediation planning.
    
    Usage: .\Get-EntraUserList.ps1 -Interactive
    
    In interactive mode:
    - Original account shown on left, duplicate on right
    - Color-coded indicators: ✓ (present), ✗ (missing), ○ (empty), ⚠ (suspicious)
    - Clear action items listed for each pair
    - Duplicates grouped separately from suspicious accounts
    - Summary provided at end with next steps

.PARAMETER Quiet
    When specified, suppresses the standard output of PSCustomObjects. Only displays the status
    messages and summary tables. Useful when you only care about the console output and don't
    need to pipe results to other commands.
    
    Usage: .\Get-EntraUserList.ps1 -Quiet

.EXAMPLE
    .\Get-EntraUserList.ps1
    Displays summary tables of all duplicate and suspicious account pairs.

.EXAMPLE
    .\Get-EntraUserList.ps1 -Interactive
    Enables interactive review mode - shows each pair individually with action items.

.EXAMPLE
    .\Get-EntraUserList.ps1 -Quiet
    Displays summary tables but suppresses the standard object output for cleaner console display.

.EXAMPLE
    .\Get-EntraUserList.ps1 -ExportPath "C:\Reports\UserAnalysis.csv"
    Exports results to CSV for further analysis.

.EXAMPLE
    $results = .\Get-EntraUserList.ps1
    $results | Where-Object { $_.Type -eq "DUPLICATE" } | Format-List
    Returns objects that can be filtered and formatted using standard PowerShell cmdlets.

.NOTES
    Requires: Microsoft.Graph PowerShell module
    Permissions needed: User.Read.All
    Author: Generated for Entra provisioning analysis
    Date: January 2026
    
    Detection logic:
    - DUPLICATE: Matching EmployeeID and GUID (clear consolidation)
    - SUSPICIOUS: Matching EmployeeID with email suffix 1/2 (provisioning artifact)
    
    Output modes:
    - Standard (default): Summary tables + returns PSCustomObjects for piping
    - Interactive (-Interactive): Account-by-account review with press-to-continue flow
    
    Visual indicators used:
    - ✓ = Present/Valid (shown in Green)
    - ✗ = Missing critical attribute (shown in Red)
    - ○ = Empty/Not set (shown in Gray)
    - ⚠ = Suspicious/Warning (shown in Yellow)
    
    Returns: Array of PSCustomObjects with properties for each account pair
    - Original_* and Duplicate_* properties for all extended attributes
    - Type, Status, and remediation information
    - Can be piped to Format-Table, Format-List, Export-Csv, etc.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$ExportPath,
    
    [Parameter(Mandatory = $false)]
    [switch]$Interactive,
    
    [Parameter(Mandatory = $false)]
    [switch]$Quiet
)

# Module requirements - Microsoft.Graph.Authentication is needed for Connect-MgGraph
$requiredModules = @(
    'Microsoft.Graph.Authentication',
    'Microsoft.Graph.Users'
)

function Install-RequiredModules {
    <#
    .SYNOPSIS
        Ensures all required PowerShell modules are installed and imported.
    #>
    
    Write-Host "`nChecking for required modules..." -ForegroundColor Cyan
    
    # Check if NuGet provider is available (required for Install-Module)
    $nugetProvider = Get-PackageProvider -Name NuGet -ListAvailable -ErrorAction SilentlyContinue
    if ($null -eq $nugetProvider -or $nugetProvider.Version -lt [Version]"2.8.5.201") {
        Write-Host "Installing NuGet package provider..." -ForegroundColor Yellow
        try {
            Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force -Scope CurrentUser | Out-Null
            Write-Host "NuGet provider installed successfully" -ForegroundColor Green
        }
        catch {
            Write-Warning "Failed to install NuGet provider: $_"
            Write-Host "You may need to run PowerShell as Administrator" -ForegroundColor Yellow
        }
    }
    
    # Set PSGallery as trusted if not already
    $psGallery = Get-PSRepository -Name PSGallery -ErrorAction SilentlyContinue
    if ($psGallery.InstallationPolicy -ne 'Trusted') {
        Write-Host "Setting PSGallery as trusted repository..." -ForegroundColor Yellow
        Set-PSRepository -Name PSGallery -InstallationPolicy Trusted
    }
    
    foreach ($module in $requiredModules) {
        Write-Host "  Checking module: $module" -ForegroundColor Gray
        
        $installedModule = Get-Module -ListAvailable -Name $module | Sort-Object Version -Descending | Select-Object -First 1
        
        if ($null -eq $installedModule) {
            Write-Host "  Installing module: $module..." -ForegroundColor Yellow
            try {
                Install-Module -Name $module -Repository PSGallery -Force -AllowClobber -Scope CurrentUser -ErrorAction Stop
                Write-Host "  Successfully installed $module" -ForegroundColor Green
            }
            catch {
                Write-Error "Failed to install module $module : $_"
                Write-Host "`nTroubleshooting tips:" -ForegroundColor Yellow
                Write-Host "  1. Try running PowerShell as Administrator" -ForegroundColor White
                Write-Host "  2. Run: Install-Module -Name $module -Scope CurrentUser -Force" -ForegroundColor White
                Write-Host "  3. Check your internet connection" -ForegroundColor White
                exit 1
            }
        }
        else {
            Write-Host "  Module $module is installed (v$($installedModule.Version))" -ForegroundColor Green
        }
        
        # Import the module
        try {
            Import-Module -Name $module -Force -ErrorAction Stop
            Write-Host "  Module $module imported successfully" -ForegroundColor Green
        }
        catch {
            Write-Error "Failed to import module $module : $_"
            exit 1
        }
    }
    
    Write-Host "All required modules are ready.`n" -ForegroundColor Green
}

function Connect-ToMicrosoftGraph {
    <#
    .SYNOPSIS
        Connects to Microsoft Graph using device code authentication.
    #>
    
    Write-Host "Checking Microsoft Graph connection..." -ForegroundColor Cyan
    
    $requiredScopes = @("User.Read.All")
    
    try {
        $context = Get-MgContext
        
        if ($null -eq $context) {
            Write-Host "`n" -NoNewline
            Write-Host "=" * 60 -ForegroundColor Yellow
            Write-Host "  DEVICE CODE AUTHENTICATION" -ForegroundColor Yellow
            Write-Host "=" * 60 -ForegroundColor Yellow
            Write-Host "`nYou will be prompted to authenticate using a device code." -ForegroundColor White
            Write-Host "1. A code will be displayed below" -ForegroundColor White
            Write-Host "2. Open a browser and go to: https://microsoft.com/devicelogin" -ForegroundColor Cyan
            Write-Host "3. Enter the code when prompted" -ForegroundColor White
            Write-Host "4. Sign in with your organizational account`n" -ForegroundColor White
            
            Connect-MgGraph -Scopes $requiredScopes -UseDeviceCode -NoWelcome -ErrorAction Stop
            
            # Verify connection
            $context = Get-MgContext
            if ($null -eq $context) {
                throw "Connection verification failed"
            }
            
            Write-Host "`nSuccessfully connected to Microsoft Graph!" -ForegroundColor Green
            Write-Host "  Account: $($context.Account)" -ForegroundColor White
            Write-Host "  Tenant:  $($context.TenantId)" -ForegroundColor White
        }
        else {
            Write-Host "Already connected to Microsoft Graph" -ForegroundColor Green
            Write-Host "  Account: $($context.Account)" -ForegroundColor White
            Write-Host "  Tenant:  $($context.TenantId)" -ForegroundColor White
            
            # Verify we have the required scopes
            $hasRequiredScopes = $true
            foreach ($scope in $requiredScopes) {
                if ($context.Scopes -notcontains $scope) {
                    $hasRequiredScopes = $false
                    Write-Host "  Missing scope: $scope" -ForegroundColor Yellow
                }
            }
            
            if (-not $hasRequiredScopes) {
                Write-Host "`nReconnecting with required scopes..." -ForegroundColor Yellow
                Disconnect-MgGraph -ErrorAction SilentlyContinue | Out-Null
                Connect-MgGraph -Scopes $requiredScopes -UseDeviceCode -NoWelcome -ErrorAction Stop
                Write-Host "Reconnected successfully with required scopes" -ForegroundColor Green
            }
        }
    }
    catch {
        Write-Error "Failed to connect to Microsoft Graph: $_"
        Write-Host "`nTroubleshooting tips:" -ForegroundColor Yellow
        Write-Host "  1. Make sure you have internet connectivity" -ForegroundColor White
        Write-Host "  2. Verify you have permissions to read user data" -ForegroundColor White
        Write-Host "  3. Try running: Disconnect-MgGraph" -ForegroundColor White
        Write-Host "  4. Then run this script again" -ForegroundColor White
        exit 1
    }
}

function Get-UsersWithDuplicates {
    <#
    .SYNOPSIS
        Identifies duplicate Entra ID user accounts and real accounts with matching names.
    
    .DESCRIPTION
        This function retrieves all users from Entra ID and identifies accounts with matching patterns
        (original email vs email with '1' appended). For each pair found, it:
        
        - Retrieves user details including extension attributes (GUID, WID) and EmployeeID
        - Compares internal IDs to determine if this is a duplicate or two real accounts
        - Determines which attributes need to be copied from duplicate to original
        - Identifies which account should be deleted (duplicates only)
        
    .OUTPUTS
        PSCustomObject array containing:
        - Original_* properties (DisplayName, Mail, EmployeeID, GUID, WID)
        - Duplicate_* properties (DisplayName, Mail, EmployeeID, GUID, WID)
        - NeedsGUID: Boolean indicating if original account needs GUID from duplicate
        - NeedsWID: Boolean indicating if original account needs WID from duplicate
        - AccountToDelete: Instructions on what to do with accounts
        - IsDuplicate: Boolean indicating if this is a duplicate or real accounts
        - Status: "DUPLICATE PAIR" or "REAL ACCOUNTS - BOTH VALID"
    #>
    Write-Host "`nRetrieving users from Entra ID..." -ForegroundColor Cyan
    
    # Properties to retrieve
    $properties = @(
        'Id',
        'EmployeeId',
        'UserPrincipalName',
        'DisplayName',
        'Mail',
        'OnPremisesExtensionAttributes'
    )
    
    # Helper function to get extension attributes safely
    function Get-ExtensionAttribute {
        <#
        .SYNOPSIS
            Safely retrieves a named extension attribute from a user object.
        
        .PARAMETER User
            The user object to extract the attribute from.
        
        .PARAMETER AttributeName
            The name of the extension attribute (e.g., 'extensionAttribute3', 'extensionAttribute4').
        
        .OUTPUTS
            String value of the attribute, or $null if empty/not set.
        #>
        param(
            [Parameter(Mandatory = $true)]
            $User,
            [Parameter(Mandatory = $true)]
            [string]$AttributeName
        )
        
        if ($null -eq $User.OnPremisesExtensionAttributes) {
            return $null
        }
        
        $attrValue = $User.OnPremisesExtensionAttributes | Select-Object -ExpandProperty $AttributeName -ErrorAction SilentlyContinue
        return [string]::IsNullOrWhiteSpace($attrValue) ? $null : $attrValue
    }
    
    
    
    # Helper function to classify account pairs
    function Test-AccountPairType {
        <#
        .SYNOPSIS
            Classifies account pairs as duplicate or suspicious duplicate.
        
        .DESCRIPTION
            Analyzes IDs between two accounts to determine their relationship.
            Note: Any account pair matching this pattern (email with 1/2 suffix) is
            inherently a provisioning issue - either a clear duplicate or suspicious error.
            
            - "DUPLICATE": Clear evidence of same person (matching EmployeeID and GUID)
            - "SUSPICIOUS": Matching EmployeeID with suffix 1/2 or other mismatches (provisioning agent error)
        
        .PARAMETER OriginalEmployeeID
            Employee ID from original account.
        
        .PARAMETER DuplicateEmployeeID
            Employee ID from account with suffix.
        
        .PARAMETER OriginalGUID
            GUID (extensionAttribute3) from original account.
        
        .PARAMETER DuplicateGUID
            GUID (extensionAttribute3) from account with suffix.
        
        .PARAMETER OriginalWID
            WID (extensionAttribute4) from original account.
        
        .PARAMETER DuplicateWID
            WID (extensionAttribute4) from account with suffix.
        
        .OUTPUTS
            String: "DUPLICATE" or "SUSPICIOUS"
        #>
        param(
            [string]$OriginalEmployeeID,
            [string]$DuplicateEmployeeID,
            [string]$OriginalGUID,
            [string]$DuplicateGUID,
            [string]$OriginalWID,
            [string]$DuplicateWID
        )
        
        # STRONG INDICATORS OF DUPLICATE (CLEAR CASE)
        # EmployeeIDs match exactly AND GUIDs match
        if (-not [string]::IsNullOrWhiteSpace($OriginalEmployeeID) -and 
            -not [string]::IsNullOrWhiteSpace($DuplicateEmployeeID) -and
            $OriginalEmployeeID -eq $DuplicateEmployeeID -and
            -not [string]::IsNullOrWhiteSpace($OriginalGUID) -and 
            -not [string]::IsNullOrWhiteSpace($DuplicateGUID) -and
            $OriginalGUID -eq $DuplicateGUID) {
            return "DUPLICATE"
        }
        
        # GUIDs match exactly
        if (-not [string]::IsNullOrWhiteSpace($OriginalGUID) -and 
            -not [string]::IsNullOrWhiteSpace($DuplicateGUID) -and
            $OriginalGUID -eq $DuplicateGUID) {
            return "DUPLICATE"
        }
        
        # SUSPICIOUS - EmployeeID match with suffix (provisioning agent created duplicate)
        # This is the key indicator of errant provisioning
        if (-not [string]::IsNullOrWhiteSpace($OriginalEmployeeID) -and 
            -not [string]::IsNullOrWhiteSpace($DuplicateEmployeeID) -and
            $OriginalEmployeeID -eq $DuplicateEmployeeID) {
            return "SUSPICIOUS"  # Same EmployeeID but different email = provisioning error
        }
        
        # Grey area: EmployeeID in one and not the other
        if (([string]::IsNullOrWhiteSpace($OriginalEmployeeID) -and 
            -not [string]::IsNullOrWhiteSpace($DuplicateEmployeeID)) -or
            (-not [string]::IsNullOrWhiteSpace($OriginalEmployeeID) -and 
            [string]::IsNullOrWhiteSpace($DuplicateEmployeeID))) {
            return "SUSPICIOUS"  # Incomplete EmployeeID data suggests provisioning issue
        }
        
        # Check if EmployeeID contains GUID or vice versa (relationship indicator)
        if (-not [string]::IsNullOrWhiteSpace($OriginalEmployeeID) -and 
            -not [string]::IsNullOrWhiteSpace($DuplicateGUID) -and
            $OriginalEmployeeID.Contains($DuplicateGUID)) {
            return "SUSPICIOUS"
        }
        
        # If we have no matching attributes, these are real accounts
        return "REAL"
    }
    
    $allUsers = Get-MgUser -All -Property ($properties -join ',') | Select-Object -Property $properties
    Write-Host "Retrieved $($allUsers.Count) users" -ForegroundColor Green
    
    # Create a hashtable for quick lookup by email prefix (without domain)
    $usersByEmailPrefix = @{}
    
    foreach ($user in $allUsers) {
        if ([string]::IsNullOrWhiteSpace($user.Mail)) { continue }
        
        $emailParts = $user.Mail.Split('@')
        if ($emailParts.Count -ne 2) { continue }
        
        $prefix = $emailParts[0].ToLower()
        $domain = $emailParts[1].ToLower()
        
        if (-not $usersByEmailPrefix.ContainsKey($prefix)) {
            $usersByEmailPrefix[$prefix] = @()
        }
        $usersByEmailPrefix[$prefix] += @{
            User = $user
            Prefix = $prefix
            Domain = $domain
        }
    }
    
    # Find duplicates - accounts where prefix ends with '1' and there's an original without '1'
    $matchedPairs = @()
    
    foreach ($prefix in $usersByEmailPrefix.Keys) {
        # Check if this prefix ends with '1' and could be a duplicate
        if ($prefix -match '^(.+)1$') {
            $originalPrefix = $Matches[1]
            
            # Look for the original account (without the trailing '1')
            if ($usersByEmailPrefix.ContainsKey($originalPrefix)) {
                foreach ($duplicateEntry in $usersByEmailPrefix[$prefix]) {
                    foreach ($originalEntry in $usersByEmailPrefix[$originalPrefix]) {
                        # Match by domain to ensure they're in the same tenant
                        if ($duplicateEntry.Domain -eq $originalEntry.Domain) {
                            $original = $originalEntry.User
                            $duplicate = $duplicateEntry.User
                            
                            # Retrieve ALL extension attributes for complete analysis
                            $orig_ExtAttr1 = Get-ExtensionAttribute -User $original -AttributeName 'extensionAttribute1'  # Provisioning status/ServiceNow ref
                            $orig_ExtAttr2 = Get-ExtensionAttribute -User $original -AttributeName 'extensionAttribute2'  # Employee type
                            $orig_ExtAttr3 = Get-ExtensionAttribute -User $original -AttributeName 'extensionAttribute3'  # GUID
                            $orig_ExtAttr4 = Get-ExtensionAttribute -User $original -AttributeName 'extensionAttribute4'  # Start date
                            $orig_ExtAttr5 = Get-ExtensionAttribute -User $original -AttributeName 'extensionAttribute5'  # End date
                            $orig_ExtAttr6 = Get-ExtensionAttribute -User $original -AttributeName 'extensionAttribute6'  # SAP ID
                            
                            $dup_ExtAttr1 = Get-ExtensionAttribute -User $duplicate -AttributeName 'extensionAttribute1'
                            $dup_ExtAttr2 = Get-ExtensionAttribute -User $duplicate -AttributeName 'extensionAttribute2'
                            $dup_ExtAttr3 = Get-ExtensionAttribute -User $duplicate -AttributeName 'extensionAttribute3'
                            $dup_ExtAttr4 = Get-ExtensionAttribute -User $duplicate -AttributeName 'extensionAttribute4'
                            $dup_ExtAttr5 = Get-ExtensionAttribute -User $duplicate -AttributeName 'extensionAttribute5'
                            $dup_ExtAttr6 = Get-ExtensionAttribute -User $duplicate -AttributeName 'extensionAttribute6'
                            
                            # Classify the pair: DUPLICATE or SUSPICIOUS
                            $pairType = Test-AccountPairType -OriginalEmployeeID $original.EmployeeId `
                                                             -DuplicateEmployeeID $duplicate.EmployeeId `
                                                             -OriginalGUID $orig_ExtAttr3 `
                                                             -DuplicateGUID $dup_ExtAttr3 `
                                                             -OriginalWID $orig_ExtAttr4 `
                                                             -DuplicateWID $dup_ExtAttr4
                            
                            # Set action items based on pair type
                            switch ($pairType) {
                                "DUPLICATE" {
                                    $needsGUID = [string]::IsNullOrWhiteSpace($orig_ExtAttr3)
                                    $needsWID = [string]::IsNullOrWhiteSpace($orig_ExtAttr4)
                                    $status = "DUPLICATE PAIR - DELETE DUPLICATE"
                                    $accountToDelete = "DELETE: $($duplicate.Mail)"
                                }
                                "SUSPICIOUS" {
                                    # For suspicious, we need to consolidate data
                                    $needsGUID = [string]::IsNullOrWhiteSpace($orig_ExtAttr3) -and -not [string]::IsNullOrWhiteSpace($dup_ExtAttr3)
                                    $needsWID = [string]::IsNullOrWhiteSpace($orig_ExtAttr4) -and -not [string]::IsNullOrWhiteSpace($dup_ExtAttr4)
                                    $status = "SUSPICIOUS DUPLICATE - PROVISIONING ERROR"
                                    $accountToDelete = "REVIEW & DELETE: $($duplicate.Mail)"
                                }
                            }
                            
                            $matchedPairs += [PSCustomObject]@{
                                # Original Account
                                Original_DisplayName       = $original.DisplayName
                                Original_Mail              = $original.Mail
                                Original_EmployeeID        = $original.EmployeeId
                                Original_ExtAttr1          = $orig_ExtAttr1  # Provisioning Status
                                Original_ExtAttr2          = $orig_ExtAttr2  # Employee Type
                                Original_GUID              = $orig_ExtAttr3  # GUID
                                Original_StartDate         = $orig_ExtAttr4  # Start Date
                                Original_EndDate           = $orig_ExtAttr5  # End Date
                                Original_SAP_ID            = $orig_ExtAttr6  # SAP ID
                                # Duplicate Account
                                Duplicate_DisplayName      = $duplicate.DisplayName
                                Duplicate_Mail             = $duplicate.Mail
                                Duplicate_EmployeeID       = $duplicate.EmployeeId
                                Duplicate_ExtAttr1         = $dup_ExtAttr1  # Provisioning Status
                                Duplicate_ExtAttr2         = $dup_ExtAttr2  # Employee Type
                                Duplicate_GUID             = $dup_ExtAttr3  # GUID
                                Duplicate_StartDate        = $dup_ExtAttr4  # Start Date
                                Duplicate_EndDate          = $dup_ExtAttr5  # End Date
                                Duplicate_SAP_ID           = $dup_ExtAttr6  # SAP ID
                                # Status/Actions
                                NeedsGUID                  = $needsGUID
                                NeedsWID                   = $needsWID
                                AccountToDelete            = $accountToDelete
                                PairType                   = $pairType
                                Status                     = $status
                            }
                        }
                    }
                }
            }
        }
    }
    
    return $matchedPairs
}

function Show-DuplicateAccountComparison {
    <#
    .SYNOPSIS
        Displays duplicate account pairs in a detailed side-by-side comparison view.
    
    .DESCRIPTION
        Shows original and duplicate accounts side-by-side with all relevant attributes
        clearly highlighted. Uses color coding to indicate missing, empty, or suspicious values.
    
    .PARAMETER Pairs
        Array of account pair objects to display.
    
    .PARAMETER PairType
        The type of pairs: "DUPLICATE" or "SUSPICIOUS"
    #>
    param(
        [Parameter(Mandatory = $true)]
        [array]$Pairs,
        
        [Parameter(Mandatory = $true)]
        [string]$PairType
    )
    
    $pairNumber = 0
    
    foreach ($pair in $Pairs) {
        $pairNumber++
        
        $borderColor = if ($PairType -eq "DUPLICATE") { "Green" } else { "Yellow" }
        
        Write-Host ""
        Write-Host ("┌" + ("─" * 128) + "┐") -ForegroundColor $borderColor
        Write-Host ("│ PAIR #$pairNumber - $($PairType)".PadRight(130, " ") + "│") -ForegroundColor $borderColor
        Write-Host ("├" + ("─" * 64) + "┬" + ("─" * 63) + "┤") -ForegroundColor $borderColor
        
        # Header row
        Write-Host ("│ ORIGINAL ACCOUNT (KEEP)".PadRight(65, " ") + "│ DUPLICATE ACCOUNT (DELETE)".PadRight(64, " ") + "│") -ForegroundColor $borderColor -NoNewline
        Write-Host ""
        Write-Host ("├" + ("─" * 64) + "┼" + ("─" * 63) + "┤") -ForegroundColor $borderColor
        
        # Email
        $origEmail = $pair.Original_Mail
        $dupEmail = $pair.Duplicate_Mail
        $origEmailPadded = $origEmail.PadRight(64)
        Write-Host "│ $origEmailPadded│ $dupEmail" -ForegroundColor White
        
        # Email analysis indicator
        Write-Host ("│ " + "".PadRight(63) + "│ ").TrimEnd() -NoNewline
        Write-Host "⚠ Suffix mismatch detected" -ForegroundColor Red
        
        Write-Host ("├" + ("─" * 64) + "┼" + ("─" * 63) + "┤") -ForegroundColor $borderColor
        
        # EmployeeID
        $origEidStatus = if ([string]::IsNullOrWhiteSpace($pair.Original_EmployeeID)) { 
            Write-Host "✗ " -ForegroundColor Red -NoNewline; "MISSING" 
        } else { 
            Write-Host "✓ " -ForegroundColor Green -NoNewline; $pair.Original_EmployeeID 
        }
        $dupEidStatus = if ([string]::IsNullOrWhiteSpace($pair.Duplicate_EmployeeID)) { 
            Write-Host "○ " -ForegroundColor Gray -NoNewline; "EMPTY" 
        } else { 
            if ($pair.Original_EmployeeID -eq $pair.Duplicate_EmployeeID) {
                Write-Host "⚠ " -ForegroundColor Yellow -NoNewline
            } else {
                Write-Host "✓ " -ForegroundColor Green -NoNewline
            }
            $pair.Duplicate_EmployeeID 
        }
        
        $origEidLine = "EmployeeID: $origEidStatus"
        $dupEidLine = "EmployeeID: $dupEidStatus"
        $origEidPadded = $origEidLine.PadRight(64)
        Write-Host "│ $origEidPadded│ $dupEidLine" -ForegroundColor White
        
        Write-Host ("├" + ("─" * 64) + "┼" + ("─" * 63) + "┤") -ForegroundColor $borderColor
        
        # GUID
        $origGuidStatus = if ([string]::IsNullOrWhiteSpace($pair.Original_GUID)) { 
            Write-Host "✗ " -ForegroundColor Red -NoNewline; "MISSING" 
        } else { 
            Write-Host "✓ " -ForegroundColor Green -NoNewline; $pair.Original_GUID.Substring(0, [Math]::Min(30, $pair.Original_GUID.Length)) 
        }
        $dupGuidStatus = if ([string]::IsNullOrWhiteSpace($pair.Duplicate_GUID)) { 
            Write-Host "○ " -ForegroundColor Gray -NoNewline; "EMPTY" 
        } else { 
            Write-Host "✓ " -ForegroundColor Green -NoNewline; $pair.Duplicate_GUID.Substring(0, [Math]::Min(30, $pair.Duplicate_GUID.Length)) 
        }
        
        $origGuidLine = "GUID: $origGuidStatus"
        $dupGuidLine = "GUID: $dupGuidStatus"
        $origGuidPadded = $origGuidLine.PadRight(64)
        Write-Host "│ $origGuidPadded│ $dupGuidLine" -ForegroundColor White
        
        Write-Host ("├" + ("─" * 64) + "┼" + ("─" * 63) + "┤") -ForegroundColor $borderColor
        
        # Start Date
        $origStartStatus = if ([string]::IsNullOrWhiteSpace($pair.Original_StartDate)) { 
            Write-Host "✗ " -ForegroundColor Red -NoNewline; "MISSING" 
        } else { 
            Write-Host "✓ " -ForegroundColor Green -NoNewline; $pair.Original_StartDate 
        }
        $dupStartStatus = if ([string]::IsNullOrWhiteSpace($pair.Duplicate_StartDate)) { 
            Write-Host "○ " -ForegroundColor Gray -NoNewline; "EMPTY" 
        } else { 
            Write-Host "✓ " -ForegroundColor Green -NoNewline; $pair.Duplicate_StartDate 
        }
        
        $origStartLine = "Start Date: $origStartStatus"
        $dupStartLine = "Start Date: $dupStartStatus"
        $origStartPadded = $origStartLine.PadRight(64)
        Write-Host "│ $origStartPadded│ $dupStartLine" -ForegroundColor White
        
        Write-Host ("├" + ("─" * 64) + "┼" + ("─" * 63) + "┤") -ForegroundColor $borderColor
        
        # End Date
        $origEndStatus = if ([string]::IsNullOrWhiteSpace($pair.Original_EndDate)) { 
            Write-Host "○ " -ForegroundColor Gray -NoNewline; "EMPTY" 
        } else { 
            Write-Host "✓ " -ForegroundColor Green -NoNewline; $pair.Original_EndDate 
        }
        $dupEndStatus = if ([string]::IsNullOrWhiteSpace($pair.Duplicate_EndDate)) { 
            Write-Host "○ " -ForegroundColor Gray -NoNewline; "EMPTY" 
        } else { 
            Write-Host "✓ " -ForegroundColor Green -NoNewline; $pair.Duplicate_EndDate 
        }
        
        $origEndLine = "End Date: $origEndStatus"
        $dupEndLine = "End Date: $dupEndStatus"
        $origEndPadded = $origEndLine.PadRight(64)
        Write-Host "│ $origEndPadded│ $dupEndLine" -ForegroundColor White
        
        Write-Host ("├" + ("─" * 64) + "┼" + ("─" * 63) + "┤") -ForegroundColor $borderColor
        
        # SAP ID
        $origSapStatus = if ([string]::IsNullOrWhiteSpace($pair.Original_SAP_ID)) { 
            Write-Host "○ " -ForegroundColor Gray -NoNewline; "EMPTY" 
        } else { 
            Write-Host "✓ " -ForegroundColor Green -NoNewline; $pair.Original_SAP_ID 
        }
        $dupSapStatus = if ([string]::IsNullOrWhiteSpace($pair.Duplicate_SAP_ID)) { 
            Write-Host "○ " -ForegroundColor Gray -NoNewline; "EMPTY" 
        } else { 
            Write-Host "✓ " -ForegroundColor Green -NoNewline; $pair.Duplicate_SAP_ID 
        }
        
        $origSapLine = "SAP ID: $origSapStatus"
        $dupSapLine = "SAP ID: $dupSapStatus"
        $origSapPadded = $origSapLine.PadRight(64)
        Write-Host "│ $origSapPadded│ $dupSapLine" -ForegroundColor White
        
        Write-Host ("├" + ("─" * 64) + "┼" + ("─" * 63) + "┤") -ForegroundColor $borderColor
        
        # Recommendation/Action
        Write-Host "│ ACTION REQUIRED:".PadRight(65) + "│" -ForegroundColor $borderColor -NoNewline
        Write-Host ""
        
        if ($PairType -eq "DUPLICATE") {
            Write-Host "│ 1. Copy any missing attributes from duplicate".PadRight(65) + "│" -ForegroundColor Green
            Write-Host "│ 2. DELETE this duplicate account".PadRight(65) + "│" -ForegroundColor Red
        }
        else {
            Write-Host "│ 1. VERIFY original account email is correct".PadRight(65) + "│" -ForegroundColor Cyan
            if ($pair.NeedsGUID -and $pair.Duplicate_GUID) {
                Write-Host "│ 2. Copy GUID from duplicate if needed".PadRight(65) + "│" -ForegroundColor Yellow
            }
            elseif ($pair.NeedsWID -and $pair.Duplicate_StartDate) {
                Write-Host "│ 2. Copy Start Date from duplicate if needed".PadRight(65) + "│" -ForegroundColor Yellow
            }
            Write-Host "│ 3. DELETE this suspicious duplicate account".PadRight(65) + "│" -ForegroundColor Red
        }
        
        Write-Host ("└" + ("─" * 128) + "┘") -ForegroundColor $borderColor
    }
}

# Main execution
try {
    Write-Host "=== Entra User Duplicate Finder ===" -ForegroundColor Cyan
    Write-Host "Started at: $(Get-Date)" -ForegroundColor Gray
    
    Install-RequiredModules
    Connect-ToMicrosoftGraph
    
    $results = Get-UsersWithDuplicates
    
    if ($results.Count -eq 0) {
        Write-Host "`nNo account pairs found." -ForegroundColor Yellow
    }
    else {
        # Separate results into two categories
        $duplicates = $results | Where-Object { $_.PairType -eq "DUPLICATE" }
        $suspicious = $results | Where-Object { $_.PairType -eq "SUSPICIOUS" }
        
        # Interactive mode
        if ($Interactive) {
            Write-Host "`n" -NoNewline
            Write-Host ("=" * 130) -ForegroundColor Cyan
            Write-Host "INTERACTIVE ACCOUNT REVIEW MODE" -ForegroundColor Cyan
            Write-Host ("=" * 130) -ForegroundColor Cyan
            
            # Process duplicates
            if ($duplicates.Count -gt 0) {
                Write-Host "`n[$($duplicates.Count) CLEAR DUPLICATES - READY FOR CONSOLIDATION]" -ForegroundColor Green
                
                foreach ($pair in $duplicates) {
                    Write-Host "`n" -NoNewline
                    Write-Host ("=" * 130) -ForegroundColor Green
                    Write-Host "DUPLICATE PAIR - CONSOLIDATE & DELETE DUPLICATE" -ForegroundColor Green
                    Write-Host ("=" * 130) -ForegroundColor Green
                    
                    # Two-column layout with fixed widths
                    Write-Host ""
                    Write-Host "ORIGINAL ACCOUNT (KEEP)                                │ DUPLICATE ACCOUNT (DELETE)"  -ForegroundColor Yellow
                    Write-Host ("─" * 60) + "┼" + ("─" * 68) -ForegroundColor Gray
                    
                    # Email
                    $origEmail = $pair.Original_Mail.PadRight(58)
                    $dupEmail = $pair.Duplicate_Mail
                    Write-Host "$origEmail │ $dupEmail" -ForegroundColor White
                    
                    # EmployeeID
                    $origEid = if ([string]::IsNullOrWhiteSpace($pair.Original_EmployeeID)) { "✗ [MISSING]" } else { "✓ $($pair.Original_EmployeeID)" }
                    $dupEid = if ([string]::IsNullOrWhiteSpace($pair.Duplicate_EmployeeID)) { "○ [EMPTY]" } else { "✓ $($pair.Duplicate_EmployeeID)" }
                    $origEidPadded = $origEid.PadRight(58)
                    Write-Host "$origEidPadded │ $dupEid" -ForegroundColor White
                    
                    # GUID
                    $origGuid = if ([string]::IsNullOrWhiteSpace($pair.Original_GUID)) { "✗ [MISSING]" } else { "✓ $($pair.Original_GUID.Substring(0, [Math]::Min(20, $pair.Original_GUID.Length)))..." }
                    $dupGuid = if ([string]::IsNullOrWhiteSpace($pair.Duplicate_GUID)) { "○ [EMPTY]" } else { "✓ $($pair.Duplicate_GUID.Substring(0, [Math]::Min(20, $pair.Duplicate_GUID.Length)))..." }
                    $origGuidPadded = $origGuid.PadRight(58)
                    Write-Host "$origGuidPadded │ $dupGuid" -ForegroundColor White
                    
                    # Start Date
                    $origStart = if ([string]::IsNullOrWhiteSpace($pair.Original_StartDate)) { "○ [EMPTY]" } else { "✓ $($pair.Original_StartDate)" }
                    $dupStart = if ([string]::IsNullOrWhiteSpace($pair.Duplicate_StartDate)) { "○ [EMPTY]" } else { "✓ $($pair.Duplicate_StartDate)" }
                    $origStartPadded = $origStart.PadRight(58)
                    Write-Host "$origStartPadded │ $dupStart" -ForegroundColor White
                    
                    # End Date
                    $origEnd = if ([string]::IsNullOrWhiteSpace($pair.Original_EndDate)) { "○ [EMPTY]" } else { "✓ $($pair.Original_EndDate)" }
                    $dupEnd = if ([string]::IsNullOrWhiteSpace($pair.Duplicate_EndDate)) { "○ [EMPTY]" } else { "✓ $($pair.Duplicate_EndDate)" }
                    $origEndPadded = $origEnd.PadRight(58)
                    Write-Host "$origEndPadded │ $dupEnd" -ForegroundColor White
                    
                    # SAP ID
                    $origSap = if ([string]::IsNullOrWhiteSpace($pair.Original_SAP_ID)) { "○ [EMPTY]" } else { "✓ $($pair.Original_SAP_ID)" }
                    $dupSap = if ([string]::IsNullOrWhiteSpace($pair.Duplicate_SAP_ID)) { "○ [EMPTY]" } else { "✓ $($pair.Duplicate_SAP_ID)" }
                    $origSapPadded = $origSap.PadRight(58)
                    Write-Host "$origSapPadded │ $dupSap" -ForegroundColor White
                    
                    Write-Host ""
                    Write-Host ("─" * 130) -ForegroundColor Gray
                    Write-Host "`n  ACTION REQUIRED:" -ForegroundColor Green
                    Write-Host "  ✓ Consolidate any missing data from duplicate to original" -ForegroundColor Green
                    Write-Host "  ✓ DELETE the duplicate account: $($pair.Duplicate_Mail)" -ForegroundColor Red
                    
                    if ($pair.NeedsGUID -and $pair.Duplicate_GUID) {
                        Write-Host "    → Copy GUID: $($pair.Duplicate_GUID)" -ForegroundColor Yellow
                    }
                    if ($pair.NeedsWID -and $pair.Duplicate_StartDate) {
                        Write-Host "    → Copy Start Date: $($pair.Duplicate_StartDate)" -ForegroundColor Yellow
                    }
                    
                    Write-Host ""
                }
            }
            
            # Process suspicious
            if ($suspicious.Count -gt 0) {
                Write-Host "`n[$($suspicious.Count) SUSPICIOUS DUPLICATES - PROVISIONING ERRORS]" -ForegroundColor Yellow
                
                foreach ($pair in $suspicious) {
                    Write-Host "`n" -NoNewline
                    Write-Host ("=" * 130) -ForegroundColor Yellow
                    Write-Host "SUSPICIOUS DUPLICATE - PROVISIONING AGENT ERROR (VERIFY THEN DELETE)" -ForegroundColor Yellow
                    Write-Host ("=" * 130) -ForegroundColor Yellow
                    
                    # Two-column layout with fixed widths
                    Write-Host ""
                    Write-Host "ORIGINAL ACCOUNT (KEEP & VERIFY)                     │ DUPLICATE ACCOUNT (DELETE)"  -ForegroundColor Cyan
                    Write-Host ("─" * 60) + "┼" + ("─" * 68) -ForegroundColor Gray
                    
                    # Email
                    $origEmail = $pair.Original_Mail.PadRight(58)
                    $dupEmail = $pair.Duplicate_Mail
                    Write-Host "$origEmail │ $dupEmail" -ForegroundColor White
                    Write-Host "$(" " * 58)  │   [SUFFIX ERROR ⚠]" -ForegroundColor Red
                    
                    # EmployeeID
                    $origEid = if ([string]::IsNullOrWhiteSpace($pair.Original_EmployeeID)) { "✗ [MISSING]" } else { "✓ $($pair.Original_EmployeeID)" }
                    $dupEid = if ([string]::IsNullOrWhiteSpace($pair.Duplicate_EmployeeID)) { "○ [EMPTY]" } else { "⚠ $($pair.Duplicate_EmployeeID)" }
                    $origEidPadded = $origEid.PadRight(58)
                    Write-Host "$origEidPadded │ $dupEid" -ForegroundColor White
                    
                    # GUID
                    $origGuid = if ([string]::IsNullOrWhiteSpace($pair.Original_GUID)) { "✗ [MISSING]" } else { "✓ $($pair.Original_GUID.Substring(0, [Math]::Min(20, $pair.Original_GUID.Length)))..." }
                    $dupGuid = if ([string]::IsNullOrWhiteSpace($pair.Duplicate_GUID)) { "○ [EMPTY]" } else { "✓ $($pair.Duplicate_GUID.Substring(0, [Math]::Min(20, $pair.Duplicate_GUID.Length)))..." }
                    $origGuidPadded = $origGuid.PadRight(58)
                    Write-Host "$origGuidPadded │ $dupGuid" -ForegroundColor White
                    
                    # Start Date
                    $origStart = if ([string]::IsNullOrWhiteSpace($pair.Original_StartDate)) { "✗ [MISSING]" } else { "✓ $($pair.Original_StartDate)" }
                    $dupStart = if ([string]::IsNullOrWhiteSpace($pair.Duplicate_StartDate)) { "○ [EMPTY]" } else { "✓ $($pair.Duplicate_StartDate)" }
                    $origStartPadded = $origStart.PadRight(58)
                    Write-Host "$origStartPadded │ $dupStart" -ForegroundColor White
                    
                    # End Date
                    $origEnd = if ([string]::IsNullOrWhiteSpace($pair.Original_EndDate)) { "○ [EMPTY]" } else { "✓ $($pair.Original_EndDate)" }
                    $dupEnd = if ([string]::IsNullOrWhiteSpace($pair.Duplicate_EndDate)) { "○ [EMPTY]" } else { "✓ $($pair.Duplicate_EndDate)" }
                    $origEndPadded = $origEnd.PadRight(58)
                    Write-Host "$origEndPadded │ $dupEnd" -ForegroundColor White
                    
                    # SAP ID
                    $origSap = if ([string]::IsNullOrWhiteSpace($pair.Original_SAP_ID)) { "○ [EMPTY]" } else { "✓ $($pair.Original_SAP_ID)" }
                    $dupSap = if ([string]::IsNullOrWhiteSpace($pair.Duplicate_SAP_ID)) { "○ [EMPTY]" } else { "✓ $($pair.Duplicate_SAP_ID)" }
                    $origSapPadded = $origSap.PadRight(58)
                    Write-Host "$origSapPadded │ $dupSap" -ForegroundColor White
                    
                    Write-Host ""
                    Write-Host ("─" * 130) -ForegroundColor Gray
                    Write-Host "`n  ISSUE IDENTIFIED:" -ForegroundColor Red
                    Write-Host "  ⚠ Duplicate email has numeric suffix (provisioning error)" -ForegroundColor Red
                    Write-Host "  ⚠ Same EmployeeID on both accounts (indicates errant agent)" -ForegroundColor Red
                    
                    Write-Host "`n  ACTION REQUIRED:" -ForegroundColor Yellow
                    Write-Host "  1. VERIFY original account email is correct: $($pair.Original_Mail)" -ForegroundColor Cyan
                    
                    if ($pair.NeedsGUID -and $pair.Duplicate_GUID) {
                        Write-Host "  2. Copy missing GUID from duplicate: $($pair.Duplicate_GUID)" -ForegroundColor Yellow
                    }
                    elseif ($pair.NeedsWID -and $pair.Duplicate_StartDate) {
                        Write-Host "  2. Copy missing Start Date from duplicate: $($pair.Duplicate_StartDate)" -ForegroundColor Yellow
                    }
                    else {
                        Write-Host "  2. Both accounts have complete data - consolidation not needed" -ForegroundColor Green
                    }
                    
                    Write-Host "  3. DELETE the duplicate account: $($pair.Duplicate_Mail)" -ForegroundColor Red
                    
                    Write-Host ""
                }
            }
            
            # Summary after interactive review
            Write-Host "`n" -NoNewline
            Write-Host ("=" * 130) -ForegroundColor Cyan
            Write-Host "INTERACTIVE REVIEW COMPLETE" -ForegroundColor Cyan
            Write-Host ("=" * 130) -ForegroundColor Cyan
            
            Write-Host "`nSummary of accounts reviewed:" -ForegroundColor White
            Write-Host "  Duplicates (Ready to delete):   $($duplicates.Count)" -ForegroundColor Green
            Write-Host "  Suspicious (Verify then delete): $($suspicious.Count)" -ForegroundColor Yellow
            
            Write-Host "`nNext steps:" -ForegroundColor Cyan
            Write-Host "  1. Execute the consolidation and deletion steps above" -ForegroundColor White
            Write-Host "  2. Monitor downstream systems for re-authentication" -ForegroundColor White
            Write-Host "  3. Run script again to verify all pairs have been resolved" -ForegroundColor White
            
            Write-Host ""
            Read-Host "Press ENTER to exit" | Out-Null
        }
        else {
            # Standard mode - show custom side-by-side view
            if ($duplicates.Count -gt 0) {
                Write-Host "`n" -NoNewline
                Write-Host ("=" * 130) -ForegroundColor Red
                Write-Host "DUPLICATES: $($duplicates.Count) clear duplicate pair(s) - SAME PERSON WITH TWO ACCOUNTS" -ForegroundColor Red
                Write-Host ("=" * 130) -ForegroundColor Red
                Write-Host "`nThese pairs have matching EmployeeID or GUID - definite duplicates to consolidate." -ForegroundColor Yellow
                Write-Host ""
                
                Show-DuplicateAccountComparison -Pairs $duplicates -PairType "DUPLICATE"
            }
            
            if ($suspicious.Count -gt 0) {
                Write-Host "`n" -NoNewline
                Write-Host ("=" * 130) -ForegroundColor Yellow
                Write-Host "SUSPICIOUS: $($suspicious.Count) suspicious duplicate(s) - PROVISIONING AGENT ERRORS" -ForegroundColor Yellow
                Write-Host ("=" * 130) -ForegroundColor Yellow
                Write-Host "`nThese accounts have matching EmployeeID with email suffix (1/2) - provisioning issues." -ForegroundColor White
                Write-Host ""
                
                Show-DuplicateAccountComparison -Pairs $suspicious -PairType "SUSPICIOUS"
            }
            
            # Export if path provided
            if ($ExportPath) {
                $results | Export-Csv -Path $ExportPath -NoTypeInformation -Encoding UTF8
                Write-Host "`nResults exported to: $ExportPath" -ForegroundColor Green
            }
            
            Write-Host "`nTo view full details for a specific pair, use Format-List:" -ForegroundColor Gray
            Write-Host "  `$results[0] | Format-List" -ForegroundColor Gray
            
            # Return the full result set (unless -Quiet is specified)
            if (-not $Quiet) {
                $results
            }
        }
    }
    
    Write-Host "`nCompleted at: $(Get-Date)" -ForegroundColor Gray
}
catch {
    Write-Error "An error occurred: $_"
    Write-Error $_.ScriptStackTrace
    exit 1
}
finally {
    Write-Host "`nDone!" -ForegroundColor Cyan
}
