# Define Write-AzOpsLog Function
function Write-AzOpsLog {

    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [ValidateSet("Information", "Warning", "Error", "Verbose", "Debug")]
        [string]$Level,

        [Parameter(Mandatory = $false)]
        [string]$Topic,

        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [string]$Message,

        [Parameter(Mandatory = $false)]
        [switch]$Timestamp
    )

    begin {
        # Generate log message prefix with Timestamp (optional) and Topic (optional)
        # Will apply the same values to all messages sent via pipeline
        # Uses Timestamp switch or AzOpsLogTimestampPreference variable to enable timestamp on messages
        # AzOpsLogTimestampPreference can be set as at any variable scope as needed
        $messagePrefix = ""
        if ($Timestamp -or (Get-Variable -Name "AzOpsLogTimestampPreference" -ErrorAction Ignore)) {
            $logTimeUtc = (Get-Date).ToUniversalTime().ToString("HH:mm:ss.ffff")
            $messagePrefix = ($messagePrefix + "[$logTimeUtc] ")
        }
        if ($Topic) {
            $messagePrefix = ($messagePrefix + "($Topic) ")
        }
    }

    process {
        # Generate log message from messagePrefix
        $log = ($messagePrefix + $message)

        switch ($level) {
            "Information" {
                Write-Information -MessageData $log -InformationAction Continue
            }
            "Warning" {
                Write-Warning -Message $log
            }
            "Error" {
                Write-Error -Message $log
            }
            "Verbose" {
                Write-Verbose -Message $log
            }
            "Debug" {
                Write-Debug -Message $log
            }
        }
    }

    end { }

}