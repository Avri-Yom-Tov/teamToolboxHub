# AWS Credential Manager with GUI FOR EASY USE OF AWS CREDENTIALS DEVELOPMENT

# Hide console window
Add-Type -Name Window -Namespace Console -MemberDefinition '
[DllImport("Kernel32.dll")]
public static extern IntPtr GetConsoleWindow();

[DllImport("user32.dll")]
public static extern bool ShowWindow(IntPtr hWnd, Int32 nCmdShow);
'

$consolePtr = [Console.Window]::GetConsoleWindow()
[Console.Window]::ShowWindow($consolePtr, 0) | Out-Null

$Global:IsRunning = $false
$Global:CurrentJob = $null
$Global:StopRequested = $false
$Global:Runspace = $null
$Global:RunspacePS = $null
$Global:RunspaceHandle = $null
$Global:RunspaceOutQueue = $null
$Global:RunspaceCancelEvent = $null

# Configuration - Update these with your values ..

$user = 'Avraham.Yom-Tov'
$DEFAULT_SESSION = "default"
$default_region = 'us-west-2'
$source_profile = 'nice-identity'
$main_iam_acct_num = '736763050260'
$MFA_SESSION = "$source_profile-mfa-session"
$CODEARTIFACT_SESSION = "default-codeartifact"
$role_name = 'GroupAccess-Developers-Recording'
$codeartifact_source_profile = 'dev-test-perf'
$m2_config_file = "C:\Users\$env:UserName\.m2\settings.xml"
$mfa_secret_key = $env:awsSecretHere

$Global:AccountList = @(
    [PSCustomObject]@{ AccountId = 730335479582; Name = "rec-dev" }
    [PSCustomObject]@{ AccountId = 211125581625; Name = "rec-test" }
    [PSCustomObject]@{ AccountId = 339712875220; Name = "rec-perf" }
    [PSCustomObject]@{ AccountId = 934137132601; Name = "dev-test-perf" }
)

try {
    Add-Type -AssemblyName PresentationCore, PresentationFramework, WindowsBase, System.Drawing, System.Windows.Forms
    Write-Host "WPF assemblies loaded successfully"
} catch {
    Write-Error "Failed to load WPF assemblies: $($_.Exception.Message)"
    exit 1
}

#region Global Variables and Configuration

#endregion

#region Utility Functions
function New-TOTPCode {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Secret
    )
    
    try {
        $Secret = $Secret.ToUpper().Replace(" ", "")
        
        $base32Chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567"
        $bits = ""
        
        foreach ($char in $Secret.ToCharArray()) {
            $index = $base32Chars.IndexOf($char)
            if ($index -eq -1) {
                throw "Invalid Base32 character: $char"
            }
            $bits += [Convert]::ToString($index, 2).PadLeft(5, '0')
        }
        
        $byteCount = [Math]::Floor($bits.Length / 8)
        $secretBytes = New-Object byte[] $byteCount
        
        for ($i = 0; $i -lt $byteCount; $i++) {
            $byte = $bits.Substring($i * 8, 8)
            $secretBytes[$i] = [Convert]::ToByte($byte, 2)
        }
        
        $epoch = [Math]::Floor([DateTimeOffset]::UtcNow.ToUnixTimeSeconds() / 30)
        $timeBytes = New-Object byte[] 8
        for ($i = 7; $i -ge 0; $i--) {
            $timeBytes[$i] = [byte]($epoch -band 0xFF)
            $epoch = $epoch -shr 8
        }
        
        $hmac = New-Object System.Security.Cryptography.HMACSHA1
        $hmac.Key = $secretBytes
        $hash = $hmac.ComputeHash($timeBytes)
        
        $offset = $hash[$hash.Length - 1] -band 0x0F
        $binary = (($hash[$offset] -band 0x7F) -shl 24) -bor
                  (($hash[$offset + 1] -band 0xFF) -shl 16) -bor
                  (($hash[$offset + 2] -band 0xFF) -shl 8) -bor
                  ($hash[$offset + 3] -band 0xFF)
        
        $otp = $binary % 1000000
        
        return $otp.ToString("D6")
        
    } catch {
        Write-Host "Error generating TOTP: $($_.Exception.Message)"
        return $null
    }
}
function Write-StatusBar {
    param (
        [Parameter(Mandatory = $false)]
        [int]
        $Progress = -1,
        [Parameter(Mandatory = $true)]
        [string]
        $Text,
        [Parameter(Mandatory = $false)]
        [switch]
        $Indeterminate
    )
    
    $Global:WPFGui.StatusMessage = $Text
    $Global:WPFGui.ProgressValue = $Progress
    $Global:WPFGui.IsIndeterminateMode = $Indeterminate.IsPresent
}

function Update-Status {
    param(
        [string]$Message,
        [int]$Progress = -1,
        [switch]$Indeterminate
    )
    
    if ($Indeterminate) {
        Write-StatusBar -Text $Message -Indeterminate
    } elseif ($Progress -ge 0) {
        Write-StatusBar -Progress $Progress -Text $Message
    } else {
        if ($WPFGui.UI) {
            $WPFGui.UI.Dispatcher.Invoke([Action]{
                $WPFGui.StatusText.Text = $Message
            })
        }
    }
}

function Write-Log {
    param([string]$Message)
    
    $timestamp = Get-Date -Format "HH:mm:ss"
#   $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"

    $logMessage = "[$timestamp] $Message"
    
    if ($WPFGui.UI) {
        $WPFGui.UI.Dispatcher.Invoke([Action]{
            $WPFGui.LogOutput.AppendText("$logMessage`n")
            $WPFGui.LogOutput.ScrollToEnd()
        })
    }
    
    Write-Host $logMessage
}

function Show-MFADialog {
    $xaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="MFA Authentication" Height="200" Width="400"
        WindowStartupLocation="CenterOwner" ResizeMode="NoResize">
    <Grid Margin="10">
        <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="*"/>
            <RowDefinition Height="Auto"/>
        </Grid.RowDefinitions>
        
        <TextBlock Grid.Row="0" Text="Enter MFA Code" FontSize="16" FontWeight="Bold" Margin="0,0,0,10"/>
        <TextBlock Grid.Row="1" Text="Please enter your 6-digit MFA code:" Margin="0,0,0,10"/>
        <TextBox Grid.Row="2" Name="MFATextBox" FontSize="14" Padding="5" Margin="0,0,0,10"/>
        
        <StackPanel Grid.Row="4" Orientation="Horizontal" HorizontalAlignment="Right">
            <Button Name="OKButton" Content="OK" Width="75" Height="30" Margin="0,0,10,0" IsDefault="True"/>
            <Button Name="CancelButton" Content="Cancel" Width="75" Height="30" IsCancel="True"/>
        </StackPanel>
    </Grid>
</Window>
'@

    try {
        $reader = New-Object System.Xml.XmlNodeReader ([xml]$xaml)
        $dialog = [Windows.Markup.XamlReader]::Load($reader)
        
        $mfaTextBox = $dialog.FindName("MFATextBox")
        $okButton = $dialog.FindName("OKButton")
        $cancelButton = $dialog.FindName("CancelButton")
        
        $okButton.Add_Click({
            $dialog.DialogResult = $true
            $dialog.Close()
        })
        
        $cancelButton.Add_Click({
            $dialog.DialogResult = $false
            $dialog.Close()
        })
        
        if ($WPFGui.UI) {
            $dialog.Owner = $WPFGui.UI
        }
        $result = $dialog.ShowDialog()
        
        if ($result -eq $true) {
            return $mfaTextBox.Text
        }
        return $null
    } catch {
        Write-Host "Error showing MFA dialog: $($_.Exception.Message)"
        return $null
    }
}

function addNewLine {
    param([string] $target_profile_name)
    
    $creds_file = "~/.aws/credentials"
    if (Test-Path $creds_file) {
        if (-Not (Get-Content $creds_file -ErrorAction SilentlyContinue | Select-String "$target_profile_name" -quiet)) {
            Add-Content -Path $creds_file -Value "`r`n"
        }
    }
    $config_file = "~/.aws/config"
    if (Test-Path $config_file) {
        if (-Not (Get-Content $config_file -ErrorAction SilentlyContinue | Select-String "$target_profile_name" -quiet)) {
            Add-Content -Path $config_file -Value "`r`n"
        }
    }
}

#region XAML Definition ( GUI )
$xaml = @'
<Window
    xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
    xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
    x:Class="System.Windows.Window"
    Title="AWS Credential Manager"
    Width="800"
    MinWidth="800"
    Height="550"
    MinHeight="550"
    Name="CredentialWindow"
    AllowsTransparency="True"
    BorderThickness="0"
    WindowStartupLocation="CenterScreen"
    ResizeMode="CanResize"
    WindowStyle="None"
    Background="Transparent">
    <Window.Resources>

        <SolidColorBrush x:Key="Button.Success.Background" Color="#16A34A" />
        <SolidColorBrush x:Key="Button.Warning.Background" Color="#EA580C" />
        <SolidColorBrush x:Key="Button.Danger.Background" Color="#DC2626" />

        <Style TargetType="{x:Type Button}">
            <Setter Property="FocusVisualStyle" Value="{x:Null}" />
            <Setter Property="Background" Value="#2563EB" />
            <Setter Property="Foreground" Value="White" />
            <Setter Property="BorderThickness" Value="0" />
            <Setter Property="Padding" Value="16,10" />
            <Setter Property="FontFamily" Value="Segoe UI" />
            <Setter Property="FontSize" Value="13" />
            <Setter Property="FontWeight" Value="SemiBold" />
            <Setter Property="Cursor" Value="Hand" />
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="{x:Type Button}">
                        <Border x:Name="border" Background="{TemplateBinding Background}" CornerRadius="8">
                            <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"
                                              Margin="{TemplateBinding Padding}" />
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsMouseOver" Value="True">
                                <Setter TargetName="border" Property="Opacity" Value="0.85" />
                            </Trigger>
                            <Trigger Property="IsPressed" Value="True">
                                <Setter TargetName="border" Property="Opacity" Value="0.7" />
                            </Trigger>
                            <Trigger Property="IsEnabled" Value="False">
                                <Setter TargetName="border" Property="Opacity" Value="0.4" />
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>

        <Style TargetType="{x:Type ComboBox}">
            <Setter Property="Background" Value="White" />
            <Setter Property="BorderBrush" Value="#CBD5E1" />
            <Setter Property="BorderThickness" Value="1.5" />
            <Setter Property="Foreground" Value="#0F172A" />
            <Setter Property="FontFamily" Value="Segoe UI" />
            <Setter Property="FontSize" Value="13" />
            <Setter Property="Padding" Value="12,9" />
            <Setter Property="Height" Value="40" />
            <Style.Triggers>
                <Trigger Property="IsMouseOver" Value="True">
                    <Setter Property="BorderBrush" Value="#2563EB" />
                </Trigger>
                <Trigger Property="IsKeyboardFocused" Value="True">
                    <Setter Property="BorderBrush" Value="#2563EB" />
                </Trigger>
            </Style.Triggers>
        </Style>

        <Style TargetType="{x:Type TextBox}">
            <Setter Property="Background" Value="Transparent" />
            <Setter Property="BorderThickness" Value="0" />
            <Setter Property="Foreground" Value="#1E293B" />
            <Setter Property="FontFamily" Value="Cascadia Code, Consolas" />
            <Setter Property="FontSize" Value="11.5" />
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="{x:Type TextBox}">
                        <Border Background="{TemplateBinding Background}" BorderThickness="0">
                            <ScrollViewer x:Name="PART_ContentHost" Focusable="false"
                                          HorizontalScrollBarVisibility="Hidden"
                                          VerticalScrollBarVisibility="Hidden" />
                        </Border>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>

        <Style TargetType="{x:Type ProgressBar}">
            <Setter Property="Height" Value="3" />
            <Setter Property="BorderThickness" Value="0" />
            <Setter Property="Background" Value="#E2E8F0" />
            <Setter Property="Foreground" Value="#2563EB" />
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="{x:Type ProgressBar}">
                        <Border x:Name="TemplateRoot" Background="{TemplateBinding Background}" CornerRadius="2">
                            <Grid>
                                <Rectangle x:Name="PART_Track" />
                                <Grid x:Name="PART_Indicator" ClipToBounds="True" HorizontalAlignment="Left">
                                    <Rectangle x:Name="Indicator" Fill="{TemplateBinding Foreground}" RadiusX="2" RadiusY="2" />
                                    <Rectangle x:Name="Animation" RadiusX="2" RadiusY="2" RenderTransformOrigin="0.5,0.5">
                                        <Rectangle.Fill>
                                            <LinearGradientBrush StartPoint="0,0" EndPoint="1,0">
                                                <GradientStop Color="Transparent" Offset="0" />
                                                <GradientStop Color="#2563EB" Offset="0.4" />
                                                <GradientStop Color="#60A5FA" Offset="0.6" />
                                                <GradientStop Color="Transparent" Offset="1" />
                                            </LinearGradientBrush>
                                        </Rectangle.Fill>
                                        <Rectangle.RenderTransform>
                                            <TransformGroup>
                                                <ScaleTransform />
                                                <SkewTransform />
                                                <RotateTransform />
                                                <TranslateTransform />
                                            </TransformGroup>
                                        </Rectangle.RenderTransform>
                                    </Rectangle>
                                </Grid>
                            </Grid>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsIndeterminate" Value="True">
                                <Setter Property="Visibility" TargetName="Indicator" Value="Collapsed" />
                                <Setter Property="Visibility" TargetName="PART_Track" Value="Collapsed" />
                                <Setter Property="Visibility" TargetName="Animation" Value="Visible" />
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>

        <Style TargetType="Window">
            <Style.Triggers>
                <Trigger Property="IsActive" Value="False">
                    <Setter Property="BorderBrush" Value="#CBD5E1" />
                </Trigger>
                <Trigger Property="IsActive" Value="True">
                    <Setter Property="BorderBrush" Value="#2563EB" />
                </Trigger>
            </Style.Triggers>
        </Style>

        <Style x:Key="TitleBarButtonStyle" TargetType="Button">
            <Setter Property="Width" Value="36" />
            <Setter Property="Height" Value="36" />
            <Setter Property="Foreground" Value="White" />
            <Setter Property="Padding" Value="0" />
            <Setter Property="WindowChrome.IsHitTestVisibleInChrome" Value="True" />
            <Setter Property="IsTabStop" Value="False" />
            <Setter Property="Background" Value="Transparent" />
            <Setter Property="BorderThickness" Value="0" />
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="{x:Type Button}">
                        <Border x:Name="border" Background="{TemplateBinding Background}" CornerRadius="6" SnapsToDevicePixels="True">
                            <Viewbox Stretch="Uniform" Margin="9" Width="14" Height="14">
                                <Path x:Name="ContentPath" Data="" Stroke="{TemplateBinding Foreground}" StrokeThickness="1.5" />
                            </Viewbox>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="Tag" Value="Minimize">
                                <Setter TargetName="ContentPath" Property="Data" Value="M 0,0.5 H 10" />
                            </Trigger>
                            <Trigger Property="Tag" Value="Close">
                                <Setter TargetName="ContentPath" Property="Data" Value="M 0.35,0.35 9.65,9.65 M 0.35,9.65 9.65,0.35" />
                            </Trigger>
                            <Trigger Property="IsMouseOver" Value="True">
                                <Setter TargetName="border" Property="Background" Value="#28FFFFFF" />
                            </Trigger>
                            <MultiTrigger>
                                <MultiTrigger.Conditions>
                                    <Condition Property="IsMouseOver" Value="True" />
                                    <Condition Property="Tag" Value="Close" />
                                </MultiTrigger.Conditions>
                                <MultiTrigger.Setters>
                                    <Setter TargetName="border" Property="Background" Value="#FFEF4444" />
                                </MultiTrigger.Setters>
                            </MultiTrigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>

    </Window.Resources>

    <WindowChrome.WindowChrome>
        <WindowChrome CaptionHeight="44" ResizeBorderThickness="4" CornerRadius="12" />
    </WindowChrome.WindowChrome>

    <Border Name="WinBorder"
            BorderBrush="{Binding Path=BorderBrush, RelativeSource={RelativeSource AncestorType={x:Type Window}}}"
            BorderThickness="1" CornerRadius="12" Background="#F1F5F9">
        <Border.Effect>
            <DropShadowEffect BlurRadius="32" ShadowDepth="8" Color="#64748B" Opacity="0.18" />
        </Border.Effect>
        <Grid Name="MainGrid" Background="Transparent">
            <Grid.RowDefinitions>
                <RowDefinition Height="44" />
                <RowDefinition Height="*" />
                <RowDefinition Height="Auto" />
            </Grid.RowDefinitions>

            <!-- Title Bar -->
            <Border Grid.Row="0" CornerRadius="12,12,0,0" BorderThickness="0">
                <Border.Background>
                    <LinearGradientBrush StartPoint="0,0" EndPoint="1,0">
                        <GradientStop Color="#1E3A8A" Offset="0" />
                        <GradientStop Color="#2563EB" Offset="1" />
                    </LinearGradientBrush>
                </Border.Background>
                <Grid Height="44" Margin="6,0">
                    <!-- Centered title sits in its own layer so the right-side buttons don't push it off-center -->
                    <StackPanel Orientation="Horizontal" HorizontalAlignment="Center" VerticalAlignment="Center">
                        <Border Width="22" Height="22" CornerRadius="5" Margin="0,0,10,0">
                            <Border.Background>
                                <LinearGradientBrush StartPoint="0,0" EndPoint="1,1">
                                    <GradientStop Color="#FF9900" Offset="0" />
                                    <GradientStop Color="#FF6600" Offset="1" />
                                </LinearGradientBrush>
                            </Border.Background>
                            <TextBlock Text="&#x26A1;" FontSize="11" HorizontalAlignment="Center" VerticalAlignment="Center" Foreground="White" />
                        </Border>
                        <TextBlock Text="AWS Credential Manager" VerticalAlignment="Center"
                                   Foreground="White" FontWeight="SemiBold"
                                   FontFamily="Segoe UI" FontSize="16" />
                    </StackPanel>
                    <!-- Window buttons on the right -->
                    <StackPanel Orientation="Horizontal" HorizontalAlignment="Right" VerticalAlignment="Center">
                        <Button Name="MinimizeButton" Style="{StaticResource TitleBarButtonStyle}" Tag="Minimize" />
                        <Button Name="CloseButton" Style="{StaticResource TitleBarButtonStyle}" Tag="Close" Margin="0,0,4,0" />
                    </StackPanel>
                </Grid>
            </Border>

            <!-- Main Content -->
            <Grid Grid.Row="1" Margin="18,16,18,12">
                <Grid.ColumnDefinitions>
                    <ColumnDefinition Width="272" />
                    <ColumnDefinition Width="14" />
                    <ColumnDefinition Width="*" />
                </Grid.ColumnDefinitions>

                <!-- Left Panel -->
                <Border Grid.Column="0" Background="White" CornerRadius="12" BorderThickness="1" BorderBrush="#E2E8F0">
                    <Border.Effect>
                        <DropShadowEffect BlurRadius="14" ShadowDepth="2" Color="#94A3B8" Opacity="0.1" />
                    </Border.Effect>
                    <StackPanel Margin="22,20,22,20">
                        <TextBlock Text="Configuration" FontWeight="SemiBold" FontSize="15"
                                   Foreground="#0F172A" FontFamily="Segoe UI"
                                   Margin="0,0,0,18" />

                        <TextBlock Text="DEFAULT PROFILE" FontSize="10.5" FontWeight="SemiBold"
                                   Foreground="#94A3B8" FontFamily="Segoe UI" Margin="0,0,0,7" />
                        <ComboBox Name="AccountComboBox" DisplayMemberPath="Name" Margin="0,0,0,24" />

                        <Border Height="1" Background="#F1F5F9" Margin="0,0,0,20" />

                        <TextBlock Text="ACTIONS" FontSize="10.5" FontWeight="SemiBold"
                                   Foreground="#94A3B8" FontFamily="Segoe UI" Margin="0,0,0,12" />

                        <Button Name="StartButton" Content="Start Process" Height="42" Margin="0,0,0,9"
                                Background="{StaticResource Button.Success.Background}" IsDefault="True" />
                        <Button Name="StopButton" Content="Stop Process" Height="42" Margin="0,0,0,9"
                                Background="{StaticResource Button.Danger.Background}" IsEnabled="False" />
                        <Button Name="RestartButton" Content="Restart Process" Height="42"
                                Background="{StaticResource Button.Warning.Background}" />
                    </StackPanel>
                </Border>

                <!-- Right Panel: Activity Log -->
                <Border Grid.Column="2" Background="White" CornerRadius="12" BorderThickness="1" BorderBrush="#E2E8F0">
                    <Border.Effect>
                        <DropShadowEffect BlurRadius="14" ShadowDepth="2" Color="#94A3B8" Opacity="0.1" />
                    </Border.Effect>
                    <Grid>
                        <Grid.RowDefinitions>
                            <RowDefinition Height="Auto" />
                            <RowDefinition Height="*" />
                        </Grid.RowDefinitions>

                        <Border Grid.Row="0" BorderThickness="0,0,0,1" BorderBrush="#F1F5F9" Padding="20,15,20,13">
                            <DockPanel>
                                <TextBlock Text="Activity Log" FontWeight="SemiBold" FontSize="15"
                                           Foreground="#0F172A" FontFamily="Segoe UI" VerticalAlignment="Center" />
                                <StackPanel DockPanel.Dock="Right" Orientation="Horizontal" VerticalAlignment="Center">
                                </StackPanel>
                            </DockPanel>
                        </Border>

                        <Border Grid.Row="1" Background="#F8FAFC" CornerRadius="0,0,12,12">
                            <ScrollViewer Name="LogScrollViewer" Padding="16,12" VerticalScrollBarVisibility="Auto">
                                <TextBox Name="LogOutput" IsReadOnly="True" TextWrapping="Wrap"
                                         Background="Transparent" BorderThickness="0"
                                         FontFamily="Cascadia Code, Consolas" FontSize="11.5"
                                         Foreground="#334155"
                                         VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Auto" />
                            </ScrollViewer>
                        </Border>
                    </Grid>
                </Border>
            </Grid>

            <!-- Status Bar -->
            <Border Grid.Row="2" Background="White" CornerRadius="0,0,12,12"
                    BorderThickness="0,1,0,0" BorderBrush="#E2E8F0">
                <Grid Margin="24,10,24,14">
                    <Grid.RowDefinitions>
                        <RowDefinition Height="Auto" />
                        <RowDefinition Height="6" />
                        <RowDefinition Height="Auto" />
                    </Grid.RowDefinitions>
                    <ProgressBar Grid.Row="0" Name="ProgressBar" Value="0" />
                    <TextBlock Grid.Row="2" Name="StatusText" Text="Ready"
                               FontFamily="Segoe UI" FontSize="11.5"
                               HorizontalAlignment="Center" Foreground="#64748B" FontWeight="Medium" />
                </Grid>
            </Border>

        </Grid>
    </Border>
</Window>
'@
#endregion

# Initialize the GUI hashtable
$Global:WPFGui = @{}

# Initialize system tray variables
$Global:NotifyIcon = $null
$Global:IsHiddenToTray = $false
$Global:IsActuallyExiting = $false

function Initialize-SystemTray {
    try {
        # Create the NotifyIcon
        $Global:NotifyIcon = New-Object System.Windows.Forms.NotifyIcon
        
        # Set the icon (using the .ico file if it exists, otherwise use a default)
        $iconPath = Join-Path $PSScriptRoot "managerAws.ico"
        if (Test-Path $iconPath) {
            $Global:NotifyIcon.Icon = New-Object System.Drawing.Icon($iconPath)
        } else {
            # Use default system icon if ico file not found
            $Global:NotifyIcon.Icon = [System.Drawing.SystemIcons]::Application
        }
        
        $Global:NotifyIcon.Text = "AWS Credential Manager"
        $Global:NotifyIcon.Visible = $false
        
        # Create context menu for the tray icon
        $contextMenu = New-Object System.Windows.Forms.ContextMenuStrip
        
        # Show/Restore menu item
        $showMenuItem = New-Object System.Windows.Forms.ToolStripMenuItem
        $showMenuItem.Text = "Show Window"
        $showMenuItem.Add_Click({
            Show-WindowFromTray
        })
        $contextMenu.Items.Add($showMenuItem)
        
        # Separator
        $contextMenu.Items.Add((New-Object System.Windows.Forms.ToolStripSeparator))
        
        # Exit menu item
        $exitMenuItem = New-Object System.Windows.Forms.ToolStripMenuItem
        $exitMenuItem.Text = "Exit"
        $exitMenuItem.Add_Click({
            Exit-Application
        })
        $contextMenu.Items.Add($exitMenuItem)
        
        $Global:NotifyIcon.ContextMenuStrip = $contextMenu
        
        # Handle double-click to restore window
        $Global:NotifyIcon.Add_DoubleClick({
            Show-WindowFromTray
        })
        
        Write-Host "System tray initialized successfully"
        
    } catch {
        Write-Host "Error initializing system tray: $($_.Exception.Message)"
    }
}

function Hide-WindowToTray {
    try {
        if ($Global:WPFGui.UI -and $Global:NotifyIcon) {
            $Global:WPFGui.UI.WindowState = 'Minimized'
            $Global:WPFGui.UI.ShowInTaskbar = $false
            $Global:NotifyIcon.Visible = $true
            $Global:IsHiddenToTray = $true
            Write-Log "Application minimized to system tray"
        }
    } catch {
        Write-Host "Error hiding to tray: $($_.Exception.Message)"
    }
}

function Show-WindowFromTray {
    try {
        if ($Global:WPFGui.UI -and $Global:NotifyIcon) {
            $Global:WPFGui.UI.ShowInTaskbar = $true
            $Global:WPFGui.UI.WindowState = 'Normal'
            $Global:WPFGui.UI.Activate()
            $Global:WPFGui.UI.Topmost = $true
            $Global:WPFGui.UI.Topmost = $false
            $Global:NotifyIcon.Visible = $false
            $Global:IsHiddenToTray = $false
            Write-Log "Application restored from system tray"
        }
    } catch {
        Write-Host "Error showing from tray: $($_.Exception.Message)"
    }
}

function Exit-Application {
    try {
        $Global:IsActuallyExiting = $true
        
        # Clean up tray icon
        if ($Global:NotifyIcon) {
            $Global:NotifyIcon.Visible = $false
            $Global:NotifyIcon.Dispose()
            $Global:NotifyIcon = $null
        }
        
        # Clean up other resources and close application
        if ($Global:WPFGui.UI) {
            $Global:WPFGui.UI.Close()
        }
    } catch {
        Write-Host "Error during application exit: $($_.Exception.Message)"
    }
}

try {
    Write-Host "Loading GUI ..."
    
    # Load the XAML
    $reader = New-Object System.Xml.XmlNodeReader ([xml]$xaml)
    $Global:WPFGui.UI = [Windows.Markup.XamlReader]::Load($reader)
    
    if (-not $Global:WPFGui.UI) {
        throw "Failed to create main window"
    }
    
    Write-Host "GUI window created successfully"
    
    # Get references to controls
    $Global:WPFGui.AccountComboBox = $Global:WPFGui.UI.FindName("AccountComboBox")
    $Global:WPFGui.StartButton = $Global:WPFGui.UI.FindName("StartButton")
    $Global:WPFGui.StopButton = $Global:WPFGui.UI.FindName("StopButton")
    $Global:WPFGui.RestartButton = $Global:WPFGui.UI.FindName("RestartButton")
    $Global:WPFGui.LogOutput = $Global:WPFGui.UI.FindName("LogOutput")
    $Global:WPFGui.ProgressBar = $Global:WPFGui.UI.FindName("ProgressBar")
    $Global:WPFGui.StatusText = $Global:WPFGui.UI.FindName("StatusText")
    $Global:WPFGui.CloseButton = $Global:WPFGui.UI.FindName("CloseButton")
    $Global:WPFGui.MinimizeButton = $Global:WPFGui.UI.FindName("MinimizeButton")
    $Global:WPFGui.LogScrollViewer = $Global:WPFGui.UI.FindName("LogScrollViewer")
    
    # Initialize DispatcherTimer variables
    $Global:WPFGui.StatusMessage = "Ready"
    $Global:WPFGui.ProgressValue = 0
    $Global:WPFGui.IsIndeterminateMode = $false
    
    # Create DispatcherTimer for smooth progress bar updates
    $Global:UpdateTimer = New-Object System.Windows.Threading.DispatcherTimer
    $Global:UpdateTimer.Interval = [TimeSpan]::FromMilliseconds(50) # Update every 50ms
    
    $updateBlock = {
        try {
            if ($Global:WPFGui.StatusText) {
                $Global:WPFGui.StatusText.Text = $Global:WPFGui.StatusMessage
            }
            
            if ($Global:WPFGui.ProgressBar) {
                if ($Global:WPFGui.IsIndeterminateMode) {
                    $Global:WPFGui.ProgressBar.IsIndeterminate = $true
                } else {
                    $Global:WPFGui.ProgressBar.IsIndeterminate = $false
                    if ($Global:WPFGui.ProgressValue -ge 0) {
                        $Global:WPFGui.ProgressBar.Value = $Global:WPFGui.ProgressValue
                    }
                }
            }
        } catch {
            # Ignore errors during update
        }
    }
    
    $Global:UpdateTimer.Add_Tick($updateBlock)
    $Global:UpdateTimer.Start()

    # Verify all controls were found
    $controls = @("AccountComboBox", "StartButton", "StopButton", "RestartButton", "LogOutput", "ProgressBar", "StatusText", "CloseButton", "MinimizeButton")
    foreach ($control in $controls) {
        if (-not $Global:WPFGui[$control]) {
            Write-Warning "Control $control not found!"
        } else {
            Write-Host "Control $control found successfully"
        }
    }

    # Populate account dropdown - the user's selection becomes the "default" profile
    $Global:WPFGui.AccountComboBox.ItemsSource = $Global:AccountList
    $defaultProfileIndex = 0
    for ($i = 0; $i -lt $Global:AccountList.Count; $i++) {
        if ($Global:AccountList[$i].Name -eq 'dev-test-perf') {
            $defaultProfileIndex = $i
            break
        }
    }
    $Global:WPFGui.AccountComboBox.SelectedIndex = $defaultProfileIndex

    # Initialize system tray functionality
    Initialize-SystemTray
    
    # Add window state changed event handler for regular minimize behavior
    $Global:WPFGui.UI.Add_StateChanged({
        if ($Global:WPFGui.UI.WindowState -eq 'Minimized' -and -not $Global:IsHiddenToTray) {
            Hide-WindowToTray
        }
    })

    Write-Log "AWS Credential Manager GUI loaded successfully."
    Write-Log "Select an account and click Start to begin the credential process."

} catch {
    Write-Host "Error loading GUI: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "Stack trace: $($_.Exception.StackTrace)" -ForegroundColor Red
    Read-Host "Press Enter to exit"
    exit 1
}

#region Title bar button event handlers
$Global:WPFGui.MinimizeButton.add_Click({
    Hide-WindowToTray
})

$Global:WPFGui.CloseButton.add_Click({
    Exit-Application
})
#endregion

#region Event Handlers
$Global:WPFGui.StartButton.Add_Click({
    try {
        if ($Global:IsRunning) {
            return
        }

        $selectedAccount = $Global:WPFGui.AccountComboBox.SelectedItem
        if (-not $selectedAccount) {
            [System.Windows.MessageBox]::Show("Please select a default profile first.", "No Profile Selected", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Warning)
            return
        }

        $accountList = $Global:AccountList
        if (-not $accountList -or $accountList.Count -eq 0) {
            [System.Windows.MessageBox]::Show("No accounts configured.", "No Accounts", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Warning)
            return
        }

        $mfaCode = $null

        if ([string]::IsNullOrWhiteSpace($mfa_secret_key)) {
            $mfaCode = Show-MFADialog
            if (-not $mfaCode) {
                Write-Log "MFA authentication cancelled by user."
                return
            }

            if ($mfaCode.Length -ne 6 -or -not ($mfaCode -match '^\d{6}$')) {
                [System.Windows.MessageBox]::Show("Please enter a valid 6-digit MFA code.", "Invalid MFA Code", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Warning)
                return
            }
        } else {
            Write-Log "Generating MFA code automatically from secret key..."
            $mfaCode = New-TOTPCode -Secret $mfa_secret_key

            if (-not $mfaCode) {
                Write-Log "Failed to generate MFA code. Please check your secret key."
                [System.Windows.MessageBox]::Show("Failed to generate MFA code automatically. Please check your secret key configuration.", "MFA Generation Error", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Error)
                return
            }

            Write-Log "MFA code generated successfully: $mfaCode"
        }

        $defaultProfileName = $selectedAccount.Name
        $profileNames = ($accountList | ForEach-Object { $_.Name }) -join ', '
        Write-Log "Default profile: $defaultProfileName. Renewing for: $profileNames"

        $Global:WPFGui.StartButton.IsEnabled = $false
        $Global:WPFGui.StopButton.IsEnabled = $true
        $Global:WPFGui.RestartButton.IsEnabled = $false

        Write-StatusBar -Text "Starting AWS credential process..." -Indeterminate

        # Convert PSCustomObjects to hashtables (kept for parity with prior job serialization shape)
        $accountsForJob = @($accountList | ForEach-Object { @{ AccountId = [string]$_.AccountId; Name = [string]$_.Name } })

        # Shared cross-thread primitives for the runspace
        $Global:RunspaceOutQueue = New-Object 'System.Collections.Concurrent.ConcurrentQueue[string]'
        $Global:RunspaceCancelEvent = New-Object System.Threading.ManualResetEventSlim($false)

        # Background work runs in a runspace (in-process) instead of Start-Job (separate process).
        # Protocol with the UI is unchanged: lines pushed to $OutQueue are drained by the timer
        # and routed through Write-Log / Write-StatusBar exactly as before.
        $Global:Runspace = [runspacefactory]::CreateRunspace()
        $Global:Runspace.ApartmentState = 'STA'
        $Global:Runspace.ThreadOptions = 'ReuseThread'
        $Global:Runspace.Open()
        $Global:Runspace.SessionStateProxy.SetVariable('OutQueue', $Global:RunspaceOutQueue)
        $Global:Runspace.SessionStateProxy.SetVariable('CancelEvent', $Global:RunspaceCancelEvent)

        $Global:RunspacePS = [powershell]::Create()
        $Global:RunspacePS.Runspace = $Global:Runspace

        $null = $Global:RunspacePS.AddScript({
            param($AccountsBag, $DefaultProfileName, $MFACode, $user, $role_name, $source_profile, $main_iam_acct_num, $default_region, $MFA_SESSION, $DEFAULT_SESSION, $CODEARTIFACT_SESSION, $codeartifact_source_profile, $m2_config_file)
            $Accounts = $AccountsBag.Accounts

            # Replacement for Write-Output: enqueue a line for the UI thread to pick up.
            function Write-Output { param([Parameter(ValueFromPipeline=$true,Position=0)][string]$Line) process { $OutQueue.Enqueue([string]$Line) } }

            function addNewLine {
                param([string] $target_profile_name)
                $creds_file = "$env:USERPROFILE\.aws\credentials"
                if (Test-Path $creds_file) {
                    if (-Not (Get-Content $creds_file -ErrorAction SilentlyContinue | Select-String "$target_profile_name" -quiet)) {
                        Add-Content -Path $creds_file -Value "`r`n"
                    }
                }
                $config_file = "$env:USERPROFILE\.aws\config"
                if (Test-Path $config_file) {
                    if (-Not (Get-Content $config_file -ErrorAction SilentlyContinue | Select-String "$target_profile_name" -quiet)) {
                        Add-Content -Path $config_file -Value "`r`n"
                    }
                }
            }

            try {
                $mfa_device = "arn:aws:iam::" + $main_iam_acct_num + ":mfa/" + $user
                $token_expiration_seconds = 129600 # 36 Hours

                # Get session token with MFA
                Write-Output "PROGRESS:INDETERMINATE:Getting session token with MFA..."
                $token_result = aws sts get-session-token --serial-number $mfa_device --duration-seconds $token_expiration_seconds --token-code $MFACode --profile $source_profile 2>&1

                if ($LASTEXITCODE -ne 0) {
                    Write-Output "AWS CLI Error: $token_result"
                    throw "Failed to get session token. Please check your MFA code and AWS configuration."
                }

                try {
                    $token_creds = $token_result | ConvertFrom-Json
                } catch {
                    Write-Output "Error parsing AWS response: $token_result"
                    throw "Failed to parse AWS response. Please check your AWS configuration."
                }

                Write-Output "PROGRESS:INDETERMINATE:Configuring MFA session credentials..."
                aws configure set aws_access_key_id $token_creds.Credentials.AccessKeyId --profile "$MFA_SESSION"
                aws configure set aws_secret_access_key $token_creds.Credentials.SecretAccessKey --profile "$MFA_SESSION"
                aws configure set aws_session_token $token_creds.Credentials.SessionToken --profile "$MFA_SESSION"

                # Reorder so the user-selected default profile is renewed first.
                # This makes the [default] mirror usable as soon as possible,
                # without waiting for the other profiles to finish.
                $defaultAcct = $Accounts | Where-Object { $_.Name -eq $DefaultProfileName } | Select-Object -First 1
                if ($defaultAcct) {
                    $Accounts = @($defaultAcct) + @($Accounts | Where-Object { $_.Name -ne $DefaultProfileName })
                }

                # Pre-set region for each profile
                foreach ($acct in $Accounts) {
                    aws configure set region $default_region --profile $acct.Name
                }

                Write-Output "Successfully cached MFA token for $token_expiration_seconds seconds."
                Write-Output "PROGRESS:INDETERMINATE:Starting credential renewal loop..."

                # Start the renewal loop for 36 hours
                for ($hour = 36; $hour -gt 0; $hour--) {
                    try {
                        $hourText = if ($hour -eq 1) { "hour" } else { "hours" }

                        Write-Output "PROGRESS:INDETERMINATE:Renewing credentials for all profiles... ($hour $hourText remaining)"

                        $codeartifact_creds = $null
                        $renewalFailed = $false

                        foreach ($acct in $Accounts) {
                            $target_profile_name = $acct.Name
                            $target_account_num = $acct.AccountId
                            $target_role = "arn:aws:iam::" + $target_account_num + ":role/" + $role_name

                            Write-Output "Renewing $target_profile_name access keys..."
                            $creds = aws sts assume-role --role-arn $target_role --role-session-name $user --profile "$MFA_SESSION" --query "Credentials" | ConvertFrom-Json

                            if ($LASTEXITCODE -eq 0 -and $creds) {
                                addNewLine $target_profile_name

                                aws configure set aws_access_key_id $creds.AccessKeyId --profile "$target_profile_name"
                                aws configure set aws_secret_access_key $creds.SecretAccessKey --profile "$target_profile_name"
                                aws configure set aws_session_token $creds.SessionToken --profile "$target_profile_name"
                                aws configure set region $default_region --profile "$target_profile_name"

                                Write-Output "$target_profile_name profile has been updated in ~/.aws/credentials."

                                # If this is the user-selected default profile, mirror credentials into [default]
                                if ($target_profile_name -eq $DefaultProfileName) {
                                    addNewLine $DEFAULT_SESSION
                                    aws configure set aws_access_key_id $creds.AccessKeyId --profile "$DEFAULT_SESSION"
                                    aws configure set aws_secret_access_key $creds.SecretAccessKey --profile "$DEFAULT_SESSION"
                                    aws configure set aws_session_token $creds.SessionToken --profile "$DEFAULT_SESSION"
                                    aws configure set region $default_region --profile "$DEFAULT_SESSION"
                                    Write-Output "Mirrored $target_profile_name credentials into [$DEFAULT_SESSION] profile."
                                }

                                if ($target_profile_name -eq $codeartifact_source_profile) {
                                    $codeartifact_creds = $creds
                                }
                            } else {
                                Write-Output "Failed to assume role for $target_profile_name (Account: $target_account_num)"
                                $renewalFailed = $true
                            }
                        }

                        # Use the dev-test-perf credentials to fetch CodeArtifact token + update Maven/NPM
                        if ($codeartifact_creds) {
                            try {
                                addNewLine $CODEARTIFACT_SESSION

                                aws configure set aws_access_key_id $codeartifact_creds.AccessKeyId --profile "$CODEARTIFACT_SESSION"
                                aws configure set aws_secret_access_key $codeartifact_creds.SecretAccessKey --profile "$CODEARTIFACT_SESSION"
                                aws configure set aws_session_token $codeartifact_creds.SessionToken --profile "$CODEARTIFACT_SESSION"
                                aws configure set region $default_region --profile "$CODEARTIFACT_SESSION"

                                $CODEARTIFACT_AUTH_TOKEN = (aws codeartifact get-authorization-token --domain nice-devops --domain-owner 369498121101 --query authorizationToken --output text --region us-west-2 --profile "$CODEARTIFACT_SESSION")
                                Write-Output "Generated CodeArtifact Token using $codeartifact_source_profile credentials."

                                # Update Maven settings.xml
                                try {
                                    if (Test-Path $m2_config_file) {
                                        $x = [xml] (Get-Content $m2_config_file)
                                        $nodeId = $x.settings.servers.server | Where-Object { $_.id -eq "cxone-codeartifact" }
                                        if ($nodeId) { $nodeId.password = $CODEARTIFACT_AUTH_TOKEN.ToString() }
                                        $nodeId1 = $x.settings.servers.server | Where-Object { $_.id -eq "platform-utils" }
                                        if ($nodeId1) { $nodeId1.password = $CODEARTIFACT_AUTH_TOKEN.ToString() }
                                        $nodeId2 = $x.settings.servers.server | Where-Object { $_.id -eq "plugins-codeartifact" }
                                        if ($nodeId2) { $nodeId2.password = $CODEARTIFACT_AUTH_TOKEN.ToString() }
                                        $x.Save($m2_config_file)
                                        Write-Output "Updated $m2_config_file with CodeArtifact Token."
                                    }
                                } catch {
                                    Write-Output "No settings.xml found or using old version: $($_.Exception.Message)"
                                }

                                # Update NPM config
                                try {
                                    npm config set registry "https://nice-devops-369498121101.d.codeartifact.us-west-2.amazonaws.com/npm/cxone-npm/" 2>$null
                                    npm config set "//nice-devops-369498121101.d.codeartifact.us-west-2.amazonaws.com/npm/cxone-npm/:_authToken=${CODEARTIFACT_AUTH_TOKEN}" 2>$null
                                    Write-Output "Updated NPM with CodeArtifact Token."
                                } catch {
                                    Write-Output "NPM not installed or error: $($_.Exception.Message)"
                                }
                            } catch {
                                Write-Output "Error generating CodeArtifact token: $($_.Exception.Message)"
                            }
                        } else {
                            Write-Output "Skipping CodeArtifact: $codeartifact_source_profile credentials not available."
                        }

                        if ($renewalFailed) {
                            Write-Output "One or more profiles failed to renew. Continuing with next cycle."
                        }

                        Write-Output "PROGRESS:STOP:All profiles renewed. Waiting for next renewal... ($hour $hourText remaining)"

                        # Sleep for 59 minutes with periodic progress updates.
                        # Use a cancellable wait so Stop/Restart break out of the sleep immediately
                        # instead of waiting up to a full minute.
                        for ($minute = 59; $minute -gt 0; $minute--) {
                            if ($CancelEvent.Wait(60000)) { return }
                            if ($minute % 10 -eq 0) {
                                Write-Output "PROGRESS:STOP:Waiting... ($hour $hourText, $minute minutes remaining)"
                            }
                        }
                    } catch {
                        Write-Output "Error during renewal: $($_.Exception.Message)"
                        break
                    }
                }

                Write-Output "PROGRESS:STOP:MFA token credentials have expired after 36 hours."

            } catch {
                Write-Output "Error: $($_.Exception.Message)"
            }
        })

        $null = $Global:RunspacePS.AddArgument(@{ Accounts = $accountsForJob })
        $null = $Global:RunspacePS.AddArgument($defaultProfileName)
        $null = $Global:RunspacePS.AddArgument($mfaCode)
        $null = $Global:RunspacePS.AddArgument($user)
        $null = $Global:RunspacePS.AddArgument($role_name)
        $null = $Global:RunspacePS.AddArgument($source_profile)
        $null = $Global:RunspacePS.AddArgument($main_iam_acct_num)
        $null = $Global:RunspacePS.AddArgument($default_region)
        $null = $Global:RunspacePS.AddArgument($MFA_SESSION)
        $null = $Global:RunspacePS.AddArgument($DEFAULT_SESSION)
        $null = $Global:RunspacePS.AddArgument($CODEARTIFACT_SESSION)
        $null = $Global:RunspacePS.AddArgument($codeartifact_source_profile)
        $null = $Global:RunspacePS.AddArgument($m2_config_file)

        $Global:RunspaceHandle = $Global:RunspacePS.BeginInvoke()

        # Monitor the runspace
        $Global:JobTimer = New-Object System.Windows.Threading.DispatcherTimer
        $Global:JobTimer.Interval = [TimeSpan]::FromSeconds(2)
        $Global:JobTimer.Add_Tick({
            try {
                # Check if UI still exists
                if (-not $Global:WPFGui -or -not $Global:WPFGui.UI) {
                    if ($Global:JobTimer) { $Global:JobTimer.Stop() }
                    return
                }

                if ($Global:RunspacePS) {
                    try {
                        # Drain any output the worker has enqueued since last tick
                        if ($Global:RunspaceOutQueue) {
                            $line = $null
                            while ($Global:RunspaceOutQueue.TryDequeue([ref]$line)) {
                                try {
                                    if ($line -match '^PROGRESS:INDETERMINATE:(.+)$') {
                                        $progressText = $matches[1]
                                        Write-StatusBar -Text $progressText -Indeterminate
                                        Write-Log $progressText
                                    } elseif ($line -match '^PROGRESS:STOP:(.+)$') {
                                        $progressText = $matches[1]
                                        Write-StatusBar -Progress 0 -Text $progressText
                                        Write-Log $progressText
                                    } else {
                                        Write-Log $line
                                    }
                                } catch {
                                    # Ignore log errors
                                }
                            }
                        }

                        $state = $Global:RunspacePS.InvocationStateInfo.State
                        if ($state -eq 'Completed' -or $state -eq 'Failed' -or $state -eq 'Stopped') {
                            if ($Global:JobTimer) { $Global:JobTimer.Stop() }
                            $Global:IsRunning = $false

                            try {
                                Write-StatusBar -Progress 0 -Text "Process completed"
                            } catch {
                                # Ignore status update errors
                            }

                            try {
                                if ($Global:WPFGui.StartButton) { $Global:WPFGui.StartButton.IsEnabled = $true }
                                if ($Global:WPFGui.StopButton) { $Global:WPFGui.StopButton.IsEnabled = $false }
                                if ($Global:WPFGui.RestartButton) { $Global:WPFGui.RestartButton.IsEnabled = $true }
                            } catch {
                                # Ignore UI update errors
                            }

                            if ($state -eq 'Failed') {
                                try {
                                    $reason = $null
                                    if ($Global:RunspacePS.InvocationStateInfo.Reason) {
                                        $reason = $Global:RunspacePS.InvocationStateInfo.Reason.Message
                                    } elseif ($Global:RunspacePS.Streams.Error.Count -gt 0) {
                                        $reason = $Global:RunspacePS.Streams.Error[0].Exception.Message
                                    }
                                    if ($reason) {
                                        Write-Log "Job failed: $reason"
                                    } else {
                                        Write-Log "Job failed: Unknown reason"
                                    }
                                } catch {
                                    try {
                                        Write-Log "Job failed: Error retrieving failure details"
                                    } catch {
                                        # Ignore even log errors
                                    }
                                }
                            }

                            try {
                                if ($Global:RunspaceHandle) {
                                    $Global:RunspacePS.EndInvoke($Global:RunspaceHandle) | Out-Null
                                }
                            } catch {
                                # EndInvoke surfaces terminating errors; already logged above
                            }
                            try { $Global:RunspacePS.Dispose() } catch { }
                            try { $Global:Runspace.Dispose() } catch { }
                            try { if ($Global:RunspaceCancelEvent) { $Global:RunspaceCancelEvent.Dispose() } } catch { }
                            $Global:RunspacePS = $null
                            $Global:Runspace = $null
                            $Global:RunspaceHandle = $null
                            $Global:RunspaceOutQueue = $null
                            $Global:RunspaceCancelEvent = $null
                            $Global:CurrentJob = $null

                            try {
                                Write-StatusBar -Progress 0 -Text "Ready"
                            } catch {
                                # Ignore status update errors
                            }
                        }
                    } catch {
                        # Error accessing runspace, likely already disposed
                        if ($Global:JobTimer) { $Global:JobTimer.Stop() }
                        $Global:RunspacePS = $null
                        $Global:Runspace = $null
                        $Global:RunspaceHandle = $null
                        $Global:CurrentJob = $null
                        $Global:IsRunning = $false
                    }
                } else {
                    # Runspace is null, stop the timer
                    if ($Global:JobTimer) { $Global:JobTimer.Stop() }
                }
            } catch {
                try {
                    Write-Host "Error in job monitoring: $($_.Exception.Message)"
                } catch {
                    # Even console output failed
                }

                try {
                    if ($Global:JobTimer) { $Global:JobTimer.Stop() }
                } catch {
                    # Ignore timer stop errors
                }

                $Global:IsRunning = $false
                $Global:CurrentJob = $null
            }
        })
        $Global:JobTimer.Start()
        
        $Global:IsRunning = $true
        
    } catch {
        Write-Log "Error in Start button click: $($_.Exception.Message)"
        $Global:WPFGui.StartButton.IsEnabled = $true
        $Global:WPFGui.StopButton.IsEnabled = $false
        $Global:WPFGui.RestartButton.IsEnabled = $true
    }
})

$Global:WPFGui.StopButton.Add_Click({
    try {
        $Global:StopRequested = $true
        Write-Log "Stop requested by user. Stopping process..."
        Write-StatusBar -Progress 0 -Text "Stopping process..."
        $Global:WPFGui.StopButton.IsEnabled = $false

        # Signal the worker's cancellable wait so a long Start-Sleep returns immediately
        if ($Global:RunspaceCancelEvent) {
            try { $Global:RunspaceCancelEvent.Set() } catch { }
        }

        if ($Global:RunspacePS) {
            try {
                $Global:RunspacePS.Stop()
                if ($Global:RunspaceHandle) {
                    try { $Global:RunspacePS.EndInvoke($Global:RunspaceHandle) | Out-Null } catch { }
                }
                $Global:RunspacePS.Dispose()
            } catch {
                Write-Log "Warning: Error during runspace cleanup: $($_.Exception.Message)"
            } finally {
                $Global:RunspacePS = $null
            }
        }
        if ($Global:Runspace) {
            try { $Global:Runspace.Dispose() } catch { }
            $Global:Runspace = $null
        }
        if ($Global:RunspaceCancelEvent) {
            try { $Global:RunspaceCancelEvent.Dispose() } catch { }
            $Global:RunspaceCancelEvent = $null
        }
        $Global:RunspaceHandle = $null
        $Global:RunspaceOutQueue = $null
        $Global:CurrentJob = $null

        # Stop the timer
        if ($Global:JobTimer) {
            try {
                $Global:JobTimer.Stop()
                $Global:JobTimer = $null
            } catch {
                # Ignore timer cleanup errors
            }
        }

        $Global:IsRunning = $false
        $Global:WPFGui.StartButton.IsEnabled = $true
        $Global:WPFGui.RestartButton.IsEnabled = $true
        Write-Log "Process stopped successfully."
    } catch {
        Write-Log "Error in Stop button click: $($_.Exception.Message)"
    }
})

$Global:WPFGui.RestartButton.Add_Click({
    try {
        if ($Global:IsRunning) {
            $Global:StopRequested = $true
            Write-Log "Restarting process..."

            if ($Global:RunspaceCancelEvent) {
                try { $Global:RunspaceCancelEvent.Set() } catch { }
            }

            if ($Global:RunspacePS) {
                try {
                    $Global:RunspacePS.Stop()
                    if ($Global:RunspaceHandle) {
                        try { $Global:RunspacePS.EndInvoke($Global:RunspaceHandle) | Out-Null } catch { }
                    }
                    $Global:RunspacePS.Dispose()
                } catch {
                    Write-Log "Warning: Error during runspace cleanup: $($_.Exception.Message)"
                } finally {
                    $Global:RunspacePS = $null
                }
            }
            if ($Global:Runspace) {
                try { $Global:Runspace.Dispose() } catch { }
                $Global:Runspace = $null
            }
            if ($Global:RunspaceCancelEvent) {
                try { $Global:RunspaceCancelEvent.Dispose() } catch { }
                $Global:RunspaceCancelEvent = $null
            }
            $Global:RunspaceHandle = $null
            $Global:RunspaceOutQueue = $null
            $Global:CurrentJob = $null

            # Stop the timer
            if ($Global:JobTimer) {
                try {
                    $Global:JobTimer.Stop()
                    $Global:JobTimer = $null
                } catch {
                    # Ignore timer cleanup errors
                }
            }

            Start-Sleep -Seconds 1
        }
        
        # Reset state
        $Global:IsRunning = $false
        
        # Clear the log
        $Global:WPFGui.LogOutput.Clear()
        
        # Stop indeterminate progress and reset to 0
        $Global:WPFGui.ProgressBar.IsIndeterminate = $false
        $Global:WPFGui.ProgressBar.Value = 0
        Write-StatusBar -Progress 0 -Text "Ready"
        
        # Reset button states
        $Global:WPFGui.StartButton.IsEnabled = $true
        $Global:WPFGui.StopButton.IsEnabled = $false
        $Global:WPFGui.RestartButton.IsEnabled = $true
        
        Write-Log "Ready to start new process"
    } catch {
        Write-Log "Error in Restart button click: $($_.Exception.Message)"
    }
})

$Global:WPFGui.UI.Add_Closing({
    param($sender, $e)
    try {
        # If we're not actually exiting, cancel the close and hide to tray instead
        if (-not $Global:IsActuallyExiting) {
            $e.Cancel = $true
            Hide-WindowToTray
            return
        }
        
        $Global:StopRequested = $true
        
        # Clean up system tray
        if ($Global:NotifyIcon) {
            $Global:NotifyIcon.Visible = $false
            $Global:NotifyIcon.Dispose()
            $Global:NotifyIcon = $null
        }
        
        # Stop all timers
        if ($Global:JobTimer) {
            try {
                $Global:JobTimer.Stop()
                $Global:JobTimer = $null
            } catch {
                # Ignore timer cleanup errors
            }
        }
        
        if ($Global:UpdateTimer) {
            try {
                $Global:UpdateTimer.Stop()
                $Global:UpdateTimer = $null
            } catch {
                # Ignore timer cleanup errors
            }
        }
        
        # Clean up runspace
        if ($Global:RunspaceCancelEvent) {
            try { $Global:RunspaceCancelEvent.Set() } catch { }
        }
        if ($Global:RunspacePS) {
            try { $Global:RunspacePS.Stop() } catch { }
            try { $Global:RunspacePS.Dispose() } catch { }
            $Global:RunspacePS = $null
        }
        if ($Global:Runspace) {
            try { $Global:Runspace.Dispose() } catch { }
            $Global:Runspace = $null
        }
        if ($Global:RunspaceCancelEvent) {
            try { $Global:RunspaceCancelEvent.Dispose() } catch { }
            $Global:RunspaceCancelEvent = $null
        }
        $Global:RunspaceHandle = $null
        $Global:RunspaceOutQueue = $null
        $Global:CurrentJob = $null
    } catch {
        # Ignore errors during cleanup
    }
})
#endregion

# Show the GUI
try {
    Write-Host "Showing GUI window..."
    if ($Global:WPFGui.UI) {
        $Global:WPFGui.UI.ShowDialog() | Out-Null
    } else {
        throw "GUI window was not created successfully"
    }
} catch {
    Write-Host "Error showing GUI: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "Full error details: $($_.Exception.ToString())" -ForegroundColor Red
    if ($Global:RunspacePS) {
        try { $Global:RunspacePS.Stop() } catch { }
        try { $Global:RunspacePS.Dispose() } catch { }
    }
    if ($Global:Runspace) {
        try { $Global:Runspace.Dispose() } catch { }
    }
    Read-Host "Press Enter to exit"
}