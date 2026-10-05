param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('Keystore', 'Properties')]
    [string]$Secret
)

$projectRoot = Split-Path -Parent $PSScriptRoot
if ($Secret -eq 'Keystore') {
    $signingPath = Join-Path $projectRoot 'android/signing/filo-testers.jks'
    $secretValue = [Convert]::ToBase64String([IO.File]::ReadAllBytes($signingPath))
    $secretName = 'FILO_KEYSTORE_BASE64'
} else {
    $signingPath = Join-Path $projectRoot 'android/key.properties'
    $secretValue = [IO.File]::ReadAllText($signingPath)
    $secretName = 'FILO_KEY_PROPERTIES'
}
Set-Clipboard -Value $secretValue
Write-Host "Copied $secretName to your clipboard. Paste it only into the matching GitHub Actions secret."
Write-Host 'After saving it, clear the clipboard with: Set-Clipboard -Value ""'
$secretValue = $null
