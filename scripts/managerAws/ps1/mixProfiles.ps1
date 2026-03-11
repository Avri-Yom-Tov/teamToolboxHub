
$user = 'Avraham.Yom-Tov' # Your AWS username
$source_profile = 'nice-identity' # This is your profile name as you configured it in .aws/credentials
$main_iam_acct_num = '736763050260' # This should be the nice-identity account number
$default_region = 'us-west-2' # Default region
$role_name = 'GroupAccess-Developers-Recording' # Your role in the target accounts
$MFA_SESSION = "$source_profile-mfa-session"

# Define accounts - ONLY these 2 profiles will be created
$accounts = @(
    [PSCustomObject]@{ AccountId = '918987959928'; Name = 'production'; Region = 'us-west-2' }
    [PSCustomObject]@{ AccountId = '654654430801'; Name = 'production-rec'; Region = 'us-west-2' }
)

# $accounts = @(
#     [PSCustomObject]@{ AccountId = '934137132601'; Name = 'dev-test-perf'; Region = 'us-west-2' }
#     [PSCustomObject]@{ AccountId = '730335479582'; Name = 'rec-dev'; Region = 'us-west-2' }
# )

########################### DO NOT EDIT ANYTHING BELOW THIS LINE ###########################

$profileNames = ($accounts | ForEach-Object { $_.Name }) -join ', '
echo "**********************************************************************************************************"
echo "This script will obtain temporary credentials for: $profileNames"
echo "and store them in your AWS CLI configuration."
echo "**********************************************************************************************************"

# Get MFA token from user
$mfa_device = "arn:aws:iam::" + $main_iam_acct_num + ":mfa/" + $user
$mfa_token = Read-Host -Prompt 'Enter MFA Code'
$token_expiration_seconds = 129600 # 36 Hours

# Get MFA session token
$token_creds = aws sts get-session-token --serial-number $mfa_device --duration-seconds $token_expiration_seconds --token-code $mfa_token --profile $source_profile | ConvertFrom-Json

Write-Host "Renewed AWS CLI Session with temporary credentials with MFA info..."

if ($lastexitcode -ne 0) {
    echo "Failed to get MFA session token. Please check your MFA code and try again."
    exit 1
}

# Set MFA session credentials
aws configure set aws_access_key_id $token_creds.Credentials.AccessKeyId --profile "$MFA_SESSION"
aws configure set aws_secret_access_key $token_creds.Credentials.SecretAccessKey --profile "$MFA_SESSION"
aws configure set aws_session_token $token_creds.Credentials.SessionToken --profile "$MFA_SESSION"

# Set region for all profiles
foreach ($account in $accounts) {
    $region = if ($account.Region) { $account.Region } else { $default_region }
    aws configure set region $region --profile $account.Name
}

echo "`n$(Get-Date -Format u) - Successfully cached MFA token for $token_expiration_seconds seconds."

# Function to add new lines in credentials and config files
function addNewLine {
    param(
        [Parameter()]
        [string] $profileName
    )
    $creds_file = "~/.aws/credentials"
    if (-Not (Get-Content $creds_file | Select-String "$profileName" -quiet)) {
        add-content -path $creds_file -value "`r`n"
    }
    $config_file = "~/.aws/config"
    if (-Not (Get-Content $config_file | Select-String "$profileName" -quiet)) {
        add-content -path $config_file -value "`r`n"
    }
}

# Main loop - renew credentials every 59 minutes for 36 hours
For ($hour=36; $hour -gt 0; $hour--) {

    foreach ($account in $accounts) {
        $profileName = $account.Name
        $accountId = $account.AccountId
        $region = if ($account.Region) { $account.Region } else { $default_region }
        $target_role = "arn:aws:iam::" + $accountId + ":role/" + $role_name

        echo "`nRenewing $profileName access keys..."
        $creds = aws sts assume-role --role-arn $target_role --role-session-name $user --profile "$MFA_SESSION" --query "Credentials" | ConvertFrom-Json

        if ($lastexitcode -eq 0) {
            addNewLine $profileName

            # Set AWS credentials via CLI
            aws configure set aws_access_key_id $creds.AccessKeyId --profile "$profileName"
            aws configure set aws_secret_access_key $creds.SecretAccessKey --profile "$profileName"
            aws configure set aws_session_token $creds.SessionToken --profile "$profileName"
            aws configure set region $region --profile "$profileName"

            echo "$(Get-Date -Format u) - $profileName ($region) profile has been updated in ~/.aws/credentials."
        } else {
            echo "Failed to assume role for $profileName (Account: $accountId)"
        }
    }

    echo "`n=========================================="
    echo "Profiles updated: $profileNames"
    echo "=========================================="

    if ($hour -eq 1) {
        echo "Keep this window open to have your keys renewed every 59 minutes for the next $hour hour."
    } else {
        echo "Keep this window open to have your keys renewed every 59 minutes for the next $hour hours."
    }

    Start-Sleep -s 3540 # 59 minutes
}

echo "MFA token credentials have expired. Please restart this script."

if ($host.name -notmatch 'ISE') {
    echo "`nPress any key to close this window..."
    $x = $host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
}

