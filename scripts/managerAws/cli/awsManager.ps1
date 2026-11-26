# awsManager.ps1 - headless version of awsManager.py
# Account 934137132601 (dev-test) -> creds into [dev-test] + [default], CodeArtifact npm + pip auth,
# then staging / production / perf-wcx into their own profiles.
# Renews every 54 min (before the 1h role creds expire) for 36h (MFA session lifetime). Ctrl+C to stop.

$ErrorActionPreference = "Stop"

$AccountId     = "934137132601"
$ProfileName   = "dev-test"
$OtherAccounts = [ordered]@{ "staging" = "946153222386"; "production" = "918987959928"; "perf-wcx" = "636107004818" }
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

$CredFile   = if ($env:AWS_SHARED_CREDENTIALS_FILE) { $env:AWS_SHARED_CREDENTIALS_FILE } else { "$HOME\.aws\credentials" }
$ConfigFile = if ($env:AWS_CONFIG_FILE) { $env:AWS_CONFIG_FILE } else { "$HOME\.aws\config" }

# Writes the credentials file directly: each `aws configure set` costs a ~2 s CLI start on Windows.
function Set-AwsProfile([string]$Name, $Creds) {
    $text  = if (Test-Path $CredFile) { [IO.File]::ReadAllText($CredFile) } else { "" }
    $block = "[$Name]`r`naws_access_key_id = $($Creds.AccessKeyId)`r`naws_secret_access_key = $($Creds.SecretAccessKey)`r`naws_session_token = $($Creds.SessionToken)`r`n`r`n"
    $m = [regex]::Match($text, "(?ms)^\[" + [regex]::Escape($Name) + "\][^\r\n]*\r?\n.*?(?=^\[|\z)")
    $text = if ($m.Success) { $text.Remove($m.Index, $m.Length).Insert($m.Index, $block) } else { $text.TrimEnd() + "`r`n`r`n" + $block }
    [IO.File]::WriteAllText($CredFile, $text)
    # region lives in the config file; set it only when missing (first run)
    $section = if ($Name -eq "default") { "default" } else { "profile $Name" }
    $cfg = if (Test-Path $ConfigFile) { [IO.File]::ReadAllText($ConfigFile) } else { "" }
    if ($cfg -notmatch ("(?ms)^\[" + [regex]::Escape($section) + "\][^\[]*?^region\s*=")) {
        aws configure set region $Region --profile $Name
    }
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

# --- Renewal loop: assume-role + CodeArtifact every 54 min while MFA session lives (36h) ---
$RoleArn = "arn:aws:iam::${AccountId}:role/$RoleName"
$sessionEnd = (Get-Date).AddSeconds($DurationSec)

while ((Get-Date) -lt $sessionEnd) {
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

    foreach ($name in $OtherAccounts.Keys) {
        $acct = $OtherAccounts[$name]
        Write-Host "Assuming role in $name ($acct)..."
        $c = aws sts assume-role --role-arn "arn:aws:iam::${acct}:role/$RoleName" --role-session-name $User --profile $MfaSession --query Credentials --output json | ConvertFrom-Json
        if ($c) { Set-AwsProfile $name $c; Write-Host "Credentials written to [$name]." }
        else { Write-Warning "assume-role failed for $name ($acct) - skipped." }
    }

    $left = [math]::Round(($sessionEnd - (Get-Date)).TotalHours, 1)
    Write-Host "Next renewal in 54 min. $left h left on MFA session. Keep window open (Ctrl+C to stop)."
    Start-Sleep -Seconds (54 * 60)
}

Write-Host "MFA session expired. Rerun script."
