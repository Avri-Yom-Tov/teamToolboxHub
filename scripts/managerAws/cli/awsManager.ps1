# awsManager.ps1 - headless version of awsManager.py
# Account 934137132601 (dev-test-perf) -> creds into [dev-test-perf] + [default], CodeArtifact npm + pip auth.
# Renews every 59 min for 36h (MFA session lifetime). Ctrl+C to stop.

$ErrorActionPreference = "Stop"

$AccountId     = "934137132601"
$ProfileName   = "dev-test-perf"
$User          = if ($env:awsUserName) { $env:awsUserName } else { "Avraham.Yom-Tov" }
$Region        = "us-west-2"
$SourceProfile = "nice-identity"
$MainIamAcct   = "736763050260"
$RoleName      = "GroupAccess-Developers-Recording"
$MfaSession    = "$SourceProfile-mfa-session"
$DurationSec   = 36 * 3600

function New-TOTPCode([string]$Secret) {
    $Secret = $Secret.ToUpper().Replace(" ", "")
    $chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567"
    $bits = ""
    foreach ($c in $Secret.ToCharArray()) {
        $i = $chars.IndexOf($c)
        if ($i -lt 0) { throw "Invalid Base32 char: $c" }
        $bits += [Convert]::ToString($i, 2).PadLeft(5, '0')
    }
    $bytes = New-Object byte[] ([math]::Floor($bits.Length / 8))
    for ($i = 0; $i -lt $bytes.Length; $i++) {
        $bytes[$i] = [Convert]::ToByte($bits.Substring($i * 8, 8), 2)
    }
    $epoch = [long][math]::Floor([DateTimeOffset]::UtcNow.ToUnixTimeSeconds() / 30)
    $timeBytes = [BitConverter]::GetBytes($epoch)
    [Array]::Reverse($timeBytes)
    $hmac = New-Object System.Security.Cryptography.HMACSHA1(,$bytes)
    $hash = $hmac.ComputeHash($timeBytes)
    $offset = $hash[$hash.Length - 1] -band 0x0F
    $binary = (($hash[$offset] -band 0x7F) -shl 24) -bor (($hash[$offset+1] -band 0xFF) -shl 16) -bor (($hash[$offset+2] -band 0xFF) -shl 8) -bor ($hash[$offset+3] -band 0xFF)
    return ($binary % 1000000).ToString().PadLeft(6, '0')
}

function Set-AwsProfile([string]$Name, $Creds) {
    aws configure set aws_access_key_id     $Creds.AccessKeyId     --profile $Name
    aws configure set aws_secret_access_key $Creds.SecretAccessKey --profile $Name
    aws configure set aws_session_token     $Creds.SessionToken    --profile $Name
    aws configure set region                $Region                --profile $Name
}

# --- MFA code: auto from secret, else prompt ---
if ($env:awsSecretHere) {
    $MfaCode = New-TOTPCode $env:awsSecretHere
    Write-Host "Auto MFA code: $MfaCode"
} else {
    $MfaCode = Read-Host "Enter 6-digit MFA code"
}

# --- Session token with MFA ---
Write-Host "Getting session token (MFA)..."
$MfaDevice = "arn:aws:iam::${MainIamAcct}:mfa/$User"
$token = aws sts get-session-token --serial-number $MfaDevice --duration-seconds $DurationSec --token-code $MfaCode --profile $SourceProfile --output json | ConvertFrom-Json
if (-not $token) { throw "MFA authentication failed" }
Set-AwsProfile $MfaSession $token.Credentials

# --- Renewal loop: assume-role + CodeArtifact every 59 min while MFA session lives (36h) ---
$RoleArn = "arn:aws:iam::${AccountId}:role/$RoleName"
$hoursRemaining = $DurationSec / 3600

while ($hoursRemaining -gt 0) {
    Write-Host "`n[$(Get-Date -Format 'HH:mm:ss')] Assuming role in $ProfileName ($AccountId)..."
    $creds = aws sts assume-role --role-arn $RoleArn --role-session-name $User --profile $MfaSession --query Credentials --output json | ConvertFrom-Json
    if (-not $creds) { throw "assume-role failed" }

    Set-AwsProfile $ProfileName $creds
    Set-AwsProfile "default" $creds
    Set-AwsProfile "default-codeartifact" $creds
    Write-Host "Credentials written to [$ProfileName], [default], [default-codeartifact]."

    Write-Host "Authenticating npm against CodeArtifact..."
    $caToken = aws codeartifact get-authorization-token --domain nice-devops --domain-owner 369498121101 --query authorizationToken --output text --region us-west-2 --profile default-codeartifact
    npm config set registry "https://nice-devops-369498121101.d.codeartifact.us-west-2.amazonaws.com/npm/cxone-npm/"
    npm config set "//nice-devops-369498121101.d.codeartifact.us-west-2.amazonaws.com/npm/cxone-npm/:_authToken=$($caToken.Trim())"
    Write-Host "npm token set."

    Write-Host "Authenticating pip against CodeArtifact..."
    aws codeartifact login --tool pip --repository cxone-pystore --domain nice-devops --domain-owner 369498121101 --region us-west-2 --profile default-codeartifact
    Write-Host "pip authenticated."

    Write-Host "Next renewal in 59 min. $hoursRemaining h left on MFA session. Keep window open (Ctrl+C to stop)."
    Start-Sleep -Seconds (59 * 60)
    $hoursRemaining--
}

Write-Host "MFA session expired. Rerun script."
