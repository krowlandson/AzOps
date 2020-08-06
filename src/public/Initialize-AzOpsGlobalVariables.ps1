<#
.SYNOPSIS
    Initializes the environment and global variables variables required for the AzOps cmdlets.
.DESCRIPTION
    Initializes the environment and global variables variables required for the AzOps cmdlets.
    Key / Values in the [AzOpsVariables] hashtable will be set as environment variables and global variables.
    All Management Groups and Subscription that the user/service principal have access to will be discovered and added to their respective variables.
.EXAMPLE
    Initialize-AzOpsGlobalVariables
.INPUTS
    None
.OUTPUTS
    - Global variables and environment variables as defined in the hashtable [AzOpsVariables]
    - [AzOpsAzManagementGroup] as well as [AzOpsSubscriptions] with all subscriptions and Management Groups that was discovered
#>

function Initialize-AzOpsGlobalVariables {

    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidGlobalVars', 'global:AzOpsPartialMgDiscoveryRoot')]
    [CmdletBinding()]
    [OutputType()]
    param (
        [Parameter(Mandatory = $false)]
        [switch]$InvalidateCache,
        [Parameter(Mandatory = $false)]
        [switch]$GeneralizeTemplates,
        [Parameter(Mandatory = $false)]
        [switch]$ExportRawTemplate
    )

    begin {
        Write-AzOpsLog -Level Debug -Topic "Initialize-AzOpsGlobalVariables" -Message ("Initiating function " + $MyInvocation.MyCommand + " begin")

        # Validate that Azure Context is available
        $AllAzContext = Get-AzContext -ListAvailable
        if (-not($AllAzContext)) {
            Write-AzOpsLog -Level Error -Topic "Initialize-AzOpsGlobalVariables" -Message "No context available in Az PowerShell. Please use Connect-AzAccount and connect before using the command"
            throw
        }

        # Ensure that registry value for long path support in windows has been set
        Test-AzOpsRuntime

        # Set current $TenantId value from $AllAzContext
        $TenantId = $AllAzContext.Tenant.Id

        # Hashtable containing map of environment to global variables for AzOps, with default values
        # Values need to be [PsCustomObject] to allow correct setting of types (important when setting $null)
        $AzOpsVariables = [hashtable]@{
            AZOPS_STATE                     = [PsCustomObject]@{ AzOpsState = (Join-Path $(Get-Location) -ChildPath "azops") } # Folder to store AzOpsState artefact
            AZOPS_MAIN_TEMPLATE             = [PsCustomObject]@{ AzOpsMainTemplate = "$PSScriptRoot\..\..\template\template.json" } # Main template json
            AZOPS_STATE_CONFIG              = [PsCustomObject]@{ AzOpsStateConfig = "$PSScriptRoot\..\AzOpsStateConfig.json" } # Configuration file for resource serialization
            AZOPS_ENROLLMENT_PRINCIPAL_NAME = [PsCustomObject]@{ AzOpsEnrollmentAccountPrincipalName = $null }
            AZOPS_EXCLUDED_SUB_OFFER        = [PsCustomObject]@{ AzOpsExcludedSubOffer = "AzurePass_2014-09-01,FreeTrial_2014-09-01,AAD_2015-09-01" } # Excluded QuotaIDs as per https://docs.microsoft.com/en-us/azure/cost-management-billing/costs/understand-cost-mgt-data#supported-microsoft-azure-offers
            AZOPS_EXCLUDED_SUB_STATE        = [PsCustomObject]@{ AzOpsExcludedSubState = "Disabled,Deleted,Warned,Expired,PastDue" } # Excluded subscription states as per https://docs.microsoft.com/en-us/rest/api/resources/subscriptions/list#subscriptionstate
            AZOPS_OFFER_TYPE                = [PsCustomObject]@{ AzOpsOfferType = "MS-AZR-0017P" }
            AZOPS_DEFAULT_DEPLOYMENT_REGION = [PsCustomObject]@{ AzOpsDefaultDeploymentRegion = "northeurope" } # Default deployment region for state deployments (ARM region, not region where a resource is deployed)
            AZOPS_INVALIDATE_CACHE          = [PsCustomObject]@{ AzOpsInvalidateCache = if ($InvalidateCache) { $true } else { $false } } # Invalidates cache and ensures that Management Groups and Subscriptions are re-discovered
            AZOPS_GENERALIZE_TEMPLATES      = [PsCustomObject]@{ AzOpsGeneralizeTemplates = if ($GeneralizeTemplates) { $true } else { $false } } # Will generalize JSON templates (only used when generating azopsreference)
            AZOPS_EXPORT_RAW_TEMPLATES      = [PsCustomObject]@{ AzOpsExportRawTemplate = if ($ExportRawTemplate) { $true } else { $false } } # Export generic templates without embedding them in the parameter block
            AZOPS_IGNORE_CONTEXT_CHECK      = [PsCustomObject]@{ AzOpsIgnoreContextCheck = 0 } # If set to 1, skip AAD tenant validation == 1
            AZOPS_THROTTLE_LIMIT            = [PsCustomObject]@{ AzOpsThrottleLimit = 10 } # Throttle limit used in Foreach-Object -Parallel for resource/subscription discovery
            AZOPS_PARTIAL_MG_DISCOVERY_ROOT = [PsCustomObject]@{ AzOpsPartialMgDiscoveryRoot = $null } # Specify the Management Group to use as root by Name (not DisplayName), e.g. "contoso"
            AZOPS_STRICT_MODE               = [PsCustomObject]@{ AzOpsStrictMode = 0 }
            AZOPS_SKIP_RESOURCE_GROUP       = [PsCustomObject]@{ AzOpsSkipResourceGroup = 1 }
            AZOPS_SKIP_POLICY               = [PsCustomObject]@{ AzOpsSkipPolicy = 0 }
            AZOPS_LOG_TIMESTAMP_PREFERENCE  = [PsCustomObject]@{ AzOpsLogTimestampPreference = $false }
            GITHUB_API_URL                  = [PsCustomObject]@{ GitHubApiUrl = $null }
            GITHUB_PULL_REQUEST             = [PsCustomObject]@{ GitHubPullRequest = $null }
            GITHUB_REPOSITORY               = [PsCustomObject]@{ GitHubRepository = $null }
            GITHUB_TOKEN                    = [PsCustomObject]@{ GitHubToken = $null }
            GITHUB_AUTO_MERGE               = [PsCustomObject]@{ GitHubAutoMerge = 1 }
            GITHUB_BRANCH                   = [PsCustomObject]@{ GitHubBranch = $null }
            GITHUB_COMMENTS                 = [PsCustomObject]@{ GitHubComments = $null }
            GITHUB_HEAD_REF                 = [PsCustomObject]@{ GitHubHeadRef = $null }
            GITHUB_BASE_REF                 = [PsCustomObject]@{ GitHubBaseRef = $null }
        }

    }

    process {
        Write-AzOpsLog -Level Debug -Topic "Initialize-AzOpsGlobalVariables" -Message ("Initiating function " + $MyInvocation.MyCommand + " process")

        # Iterate through each key:value pair in AzOpsVariables to create global variables using local environment variables to override if present
        Write-AzOpsLog -Level Verbose -Topic "Initialize-AzOpsGlobalVariables" -Message ("Setting AzOps Global Variables using environment variables or default values.")
        foreach ($Key in $AzOpsVariables.Keys | Sort-Object) {
            $EnvVarName = "env:\$Key"
            $AzOpsVariableName = $($AzOpsVariables.$Key.psobject.properties.name)
            if (Test-Path -Path $EnvVarName) {
                $EnvVarStatus = "FOUND"
                $AzOpsVariableSource = "Environment Variable"
                $AzOpsVariableValue = Get-ChildItem -Path $EnvVarName | Select-Object -ExpandProperty Value
            }
            else {
                $EnvVarStatus = "NOT FOUND"
                $AzOpsVariableSource = "Default Value"
                $AzOpsVariableValue = $AzOpsVariables.$Key.$AzOpsVariableName
            }
            Write-AzOpsLog -Level Verbose -Topic "Initialize-AzOpsGlobalVariables" -Message "Environment variable [$EnvVarName] ($EnvVarStatus)"
            if ($AzOpsVariableValue -match ',') {
                $AzOpsVariableValue = $AzOpsVariableValue -split ','
            }
            elseif ($AzOpsVariableValue -ieq "True") {
                $AzOpsVariableValue = $true
            }
            elseif ($AzOpsVariableValue -ieq "False") {
                $AzOpsVariableValue = $false
            }
            Set-Variable -Name $AzOpsVariableName -Scope Global -Value $AzOpsVariableValue
            Write-AzOpsLog -Level Verbose -Topic "Initialize-AzOpsGlobalVariables" -Message "Set [`$global:$AzOpsVariableName] using $($AzOpsVariableSource): $AzOpsVariableValue"
        }

        # Validate number of AAD Tenants that the principal has access to.
        # Needs to run after processing AzOpsVariables due to AzOpsIgnoreContextCheck
        if (0 -eq $AzOpsIgnoreContextCheck) {
            $AzContextTenants = @($AllAzContext.Tenant.Id | Sort-Object -Unique)
            if ($AzContextTenants.Count -gt 1) {
                Write-AzOpsLog -Level Error -Topic "Initialize-AzOpsGlobalVariables" -Message "Unsupported number of tenants in context: $($AzContextTenants.Count) TenantID(s)
                TenantID(s): $($AzContextTenants -join ',')
                Please reconnect with Connect-AzAccount using an account/service principal that only have access to one tenant"
                break
            }
            Write-AzOpsLog -Level Verbose -Topic "Initialize-AzOpsGlobalVariables" -Message "Found Tenant Id in current context: $($AllAzContext.Tenant.Id)"
        }

        # Set AzOpsSubscriptions if InvalidateCache is set to true or variable not set
        # Need to use Get-Variable and Set-Variable to avoid error evaluating non-existing variable
        if (($InvalidateCache) -or ($AzOpsInvalidateCache) -or (-not (Get-Variable -Name AzOpsSubscriptions -Scope Global -ErrorAction Ignore))) {
            # Initialize global variable for subscriptions - get all subscriptions in Tenant
            Write-AzOpsLog -Level Verbose -Topic "Initialize-AzOpsGlobalVariables" -Message "Initializing Global Variable [AzOpsSubscriptions]"
            Get-AzOpsAllSubscription -ExcludedOffers $AzOpsExcludedSubOffer -ExcludedStates $AzOpsExcludedSubState -TenantId $TenantId `
            | Set-Variable -Name AzOpsSubscriptions -Scope Global
        }
        else {
            # If InvalidateCache is not set to 1 and $global:AzOpsSubscriptions set, use cached information
            Write-AzOpsLog -Level Verbose -Topic "Initialize-AzOpsGlobalVariables" -Message "Using cached values for [AzOpsSubscriptions]"
        }

        # Set AzOpsAzManagementGroup if InvalidateCache is set to true or variable not set
        # Need to use Get-Variable and Set-Variable to avoid error evaluating non-existing variable
        if (($InvalidateCache) -or ($AzOpsInvalidateCache) -or (-not (Get-Variable -Name AzOpsAzManagementGroup -Scope Global -ErrorAction Ignore))) {
            Write-AzOpsLog -Level Verbose -Topic "Initialize-AzOpsGlobalVariables" -Message "Initializing Global Variable [AzOpsAzManagementGroup]"
            # Set root scope variable using AzOpsPartialMgDiscoveryRoot if provided, otherwise default to "Tenant Root Group" by using TenantId
            if ($global:AzOpsPartialMgDiscoveryRoot) {
                $RootMgName = $global:AzOpsPartialMgDiscoveryRoot
                $RootMgMessage = "user-specified Management Group: $RootMgName"
            }
            else {
                $RootMgName = $TenantId
                $RootMgMessage = "`"Tenant Root Group`" Management Group: $RootMgName"
            }
            Write-AzOpsLog -Level Verbose -Topic "Initialize-AzOpsGlobalVariables" -Message "Starting discovery from $RootMgMessage"
            Get-AzOpsAllManagementGroup -GroupName $RootMgName -Recurse `
            | Set-Variable -Name AzOpsAzManagementGroup -Scope Global
        }
        else {
            # If InvalidateCache is not set to 1 and $global:AzOpsAzManagementGroup set, use cached information
            Write-AzOpsLog -Level Verbose -Topic "Initialize-AzOpsGlobalVariables" -Message "Using cached values for [AzOpsAzManagementGroup]"
        }

    }

    end {
        Write-AzOpsLog -Level Debug -Topic "Initialize-AzOpsGlobalVariables" -Message ("Initiating function " + $MyInvocation.MyCommand + " end")
    }
}
