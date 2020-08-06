$ErrorActionPreference = "Stop"
Set-StrictMode -Version 3.0

# Dot source all functions and classes in all ps1 files located in the module
# Excludes tests and profiles

$files = @()
$files += Get-ChildItem -Force -Path ($PSScriptRoot + "/private/") -Exclude *.tests.ps1, *profile.ps1 -ErrorAction SilentlyContinue
$files += Get-ChildItem -Force -Path ($PSScriptRoot + "/public/") -Exclude *.tests.ps1, *profile.ps1 -ErrorAction SilentlyContinue

foreach ($file in $files) {
    try {
        . $file.FullName
    }
    catch {
        throw "Unable to dot source [$($file.FullName)]"
    }
}

Export-ModuleMember -Function * -Alias *
