#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
AWS Credential Manager - Beautiful Login-Style Design
Inspired by PyQt-Fluent-Widgets Login Template
"""

import sys
import os
import subprocess
import threading
import time
import json
import configparser
import hmac
import hashlib
import struct
import traceback
from datetime import datetime
from pathlib import Path


# --- DEBUG LOGGING (independent of the worker thread) ---
DEBUG_LOG_PATH = Path(__file__).parent / "aws_manager_debug.log"


def debug_log(message):
    """Write a debug message to the dedicated debug log."""
    try:
        timestamp = datetime.now().strftime("%Y-%m-%d %H:%M:%S.%f")[:-3]
        line = f"[{timestamp}] {message}"
        with open(DEBUG_LOG_PATH, "a", encoding="utf-8") as f:
            f.write(line + "\n")
        print(line)
    except Exception:
        try:
            print(f"DEBUG_LOG_FAILED: {message}")
        except Exception:
            pass


debug_log("=" * 80)
debug_log("STARTUP")
debug_log(f"sys.argv          = {sys.argv}")
debug_log(f"__file__          = {__file__}")
debug_log(f"Path(__file__)    = {Path(__file__).resolve()}")
debug_log(f"Parent dir        = {Path(__file__).parent.resolve()}")
debug_log(f"cwd               = {os.getcwd()}")
debug_log(f"DEBUG_LOG_PATH    = {DEBUG_LOG_PATH.resolve()}")
debug_log(f"Python            = {sys.executable}")
debug_log(f"Platform          = {sys.platform}")
debug_log(f"USERPROFILE       = {os.environ.get('USERPROFILE', '<missing>')}")
debug_log(f"awsSecretHere set = {bool(os.environ.get('awsSecretHere'))}")

from PyQt5.QtCore import Qt, pyqtSignal, QObject, QSize, QEvent, QTimer
from PyQt5.QtGui import QIcon, QColor, QPixmap, QPainter, QLinearGradient, QBrush
from PyQt5.QtWidgets import QApplication, QWidget, QVBoxLayout, QHBoxLayout, QSystemTrayIcon, QMenu, QAction, QLabel, QSpacerItem, QSizePolicy
from qfluentwidgets import (
    setTheme, Theme, setThemeColor, isDarkTheme,
    PrimaryPushButton, PushButton, ComboBox, LineEdit,
    TitleLabel, SubtitleLabel, BodyLabel, CaptionLabel, StrongBodyLabel,
    ProgressRing, InfoBar, InfoBarPosition, MessageBox, MessageBoxBase,
    FluentIcon as FIF, SplitTitleBar, CheckBox, HyperlinkButton
)

def resource_path(name):
    """Path to bundled resource - works both as script and pyinstaller onefile exe"""
    base = getattr(sys, "_MEIPASS", str(Path(__file__).parent))
    return str(Path(base) / name)


def isWin11():
    """Check if running on Windows 11"""
    return sys.platform == 'win32' and sys.getwindowsversion().build >= 22000

if isWin11():
    from qframelesswindow import AcrylicWindow as Window
else:
    from qframelesswindow import FramelessWindow as Window


# Configuration - matching PowerShell script
AWS_ACCOUNTS = [
    {"id": "934137132601", "name": "dev-test-perf"},
    {"id": "918987959928", "name": "wfoprod"},
    
]

CONFIG = {
    "user": os.environ.get("awsUserName", "Avraham.Yom-Tov"),
    "token_expiration_hours": 36,
    "default_region": "us-west-2",
    "source_profile": "nice-identity",
    "main_iam_acct_num": "736763050260",
    "role_name": "GroupAccess-Developers-Recording",
    "codeartifact_source_profile": "dev-test-perf",
    "mfa_secret_key": os.environ.get("awsSecretHere", "")
}


def generate_totp(secret):
    """Generate TOTP code from secret key - matching PowerShell New-TOTPCode function"""
    try:
        secret = secret.upper().replace(" ", "")
        
        base32_chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567"
        bits = ""
        
        for char in secret:
            index = base32_chars.find(char)
            if index == -1:
                raise ValueError(f"Invalid Base32 character: {char}")
            bits += format(index, '05b')
        
        byte_count = len(bits) // 8
        secret_bytes = bytes([int(bits[i*8:(i+1)*8], 2) for i in range(byte_count)])
        
        epoch = int(time.time()) // 30
        time_bytes = struct.pack(">Q", epoch)
        
        hmac_hash = hmac.new(secret_bytes, time_bytes, hashlib.sha1).digest()
        
        offset = hmac_hash[-1] & 0x0F
        binary = ((hmac_hash[offset] & 0x7F) << 24 |
                  (hmac_hash[offset + 1] & 0xFF) << 16 |
                  (hmac_hash[offset + 2] & 0xFF) << 8 |
                  (hmac_hash[offset + 3] & 0xFF))
        
        otp = binary % 1000000
        
        return str(otp).zfill(6)
        
    except Exception as e:
        print(f"Error generating TOTP: {e}")
        return None


class WorkerSignals(QObject):
    """Signals for background worker thread"""
    status_update = pyqtSignal(str)
    progress_update = pyqtSignal(bool)
    finished = pyqtSignal(bool, str)
    log_message = pyqtSignal(str)


class AWSCredentialWorker(threading.Thread):
    """Background worker for AWS credential management"""

    def __init__(self, default_profile_name, accounts, mfa_code, config, signals, npm_token=False, pip_token=False):
        super().__init__()
        self.default_profile_name = default_profile_name
        self.accounts = accounts
        self.mfa_code = mfa_code
        self.config = config
        self.signals = signals
        self.npm_token = npm_token
        self.pip_token = pip_token
        self.should_stop = False
        self.daemon = True
        
    def log(self, message):
        """Log message to file"""
        timestamp = datetime.now().strftime("%H:%M:%S")
        log_message = f"[{timestamp}] {message}"
        
        log_file = Path(__file__).parent / "aws_manager.log"
        try:
            with open(log_file, "a", encoding="utf-8") as f:
                f.write(log_message + "\n")
        except Exception as e:
            print(f"Error writing to log: {e}")
        
        self.signals.log_message.emit(log_message)
        
    def run_aws_command(self, command):
        """Run AWS CLI command"""
        try:
            result = subprocess.run(
                command,
                shell=True,
                capture_output=True,
                text=True,
                timeout=30,
                creationflags=subprocess.CREATE_NO_WINDOW
            )
            return result.returncode == 0, result.stdout if result.returncode == 0 else result.stderr
        except Exception as e:
            return False, str(e)
    
    def set_profile(self, profile, creds, region):
        """Write credentials + region directly to ~/.aws files.
        Replaces 4 'aws configure set' CLI spawns (~1s each) with instant file writes."""
        aws_dir = Path.home() / ".aws"
        aws_dir.mkdir(exist_ok=True)

        cp = configparser.ConfigParser()
        cp.read(aws_dir / "credentials", encoding='utf-8')
        if not cp.has_section(profile):
            cp.add_section(profile)
        cp[profile]["aws_access_key_id"] = creds["AccessKeyId"]
        cp[profile]["aws_secret_access_key"] = creds["SecretAccessKey"]
        cp[profile]["aws_session_token"] = creds["SessionToken"]
        with open(aws_dir / "credentials", "w", encoding='utf-8') as f:
            cp.write(f)

        cp = configparser.ConfigParser()
        cp.read(aws_dir / "config", encoding='utf-8')
        section = "default" if profile == "default" else f"profile {profile}"
        if not cp.has_section(section):
            cp.add_section(section)
        cp[section]["region"] = region
        with open(aws_dir / "config", "w", encoding='utf-8') as f:
            cp.write(f)
    
    def clear_unchecked_tokens(self):
        """Delete token files for unchecked options - like clearTokens.bat"""
        targets = []
        if not self.pip_token:
            appdata = os.environ.get("APPDATA", "")
            if appdata:
                targets.append(Path(appdata) / "pip" / "pip.ini")
            targets.append(Path.home() / "pip" / "pip.ini")
        if not self.npm_token:
            targets.append(Path.home() / ".npmrc")

        for f in targets:
            try:
                if f.exists():
                    f.unlink()
                    self.log(f"Deleted {f}")
            except Exception as e:
                self.log(f"Failed to delete {f}: {e}")

    def run(self):
        """Main worker thread logic - Following PowerShell script flow"""
        try:
            self.signals.progress_update.emit(True)
            self.clear_unchecked_tokens()
            self.signals.status_update.emit("🔐 Authenticating with MFA...")

            user = self.config['user']
            source_profile = self.config['source_profile']
            main_iam_acct_num = self.config['main_iam_acct_num']
            role_name = self.config['role_name']
            default_region = self.config['default_region']
            codeartifact_source_profile = self.config['codeartifact_source_profile']
            token_expiration_seconds = self.config['token_expiration_hours'] * 3600

            profile_names = ", ".join(a['name'] for a in self.accounts)
            self.log("**********************************************************************************************************")
            self.log(f"Default profile: {self.default_profile_name}. Renewing for: {profile_names}")
            self.log("This script will obtain temporary credentials and store them in your AWS CLI configuration.")
            self.log(f"The selected profile credentials will also be mirrored into [default] for tools like IntelliJ IDEA.")
            self.log("**********************************************************************************************************")

            MFA_SESSION = f"{source_profile}-mfa-session"
            DEFAULT_SESSION = "default"
            CODEARTIFACT_SESSION = "default-codeartifact"

            mfa_device = f"arn:aws:iam::{main_iam_acct_num}:mfa/{user}"

            self.log(f"MFA Device: {mfa_device}")

            cmd = f'aws sts get-session-token --serial-number {mfa_device} --duration-seconds {token_expiration_seconds} --token-code {self.mfa_code} --profile {source_profile} --output json'
            self.log(f"Running: aws sts get-session-token...")
            success, output = self.run_aws_command(cmd)

            if not success:
                self.log(f"MFA authentication failed: {output}")
                self.signals.finished.emit(False, f"MFA failed: {output}")
                return

            token_creds = json.loads(output)
            self.log("Renewed AWS CLI Session with temporary credentials with MFA info...")

            self.signals.status_update.emit("⚙️ Configuring MFA session...")

            self.set_profile(MFA_SESSION, token_creds["Credentials"], default_region)

            self.log(f"Successfully cached token for {token_expiration_seconds} seconds ..")

            self.signals.progress_update.emit(False)
            hours_remaining = self.config['token_expiration_hours']

            while hours_remaining > 0 and not self.should_stop:
                self.signals.progress_update.emit(True)
                self.signals.status_update.emit(f"🔄 Renewing all profiles...")

                codeartifact_creds = None
                renewal_failed = False

                for acct in self.accounts:
                    if self.should_stop:
                        break

                    target_profile_name = acct['name']
                    target_account_num = acct['id']
                    target_role = f"arn:aws:iam::{target_account_num}:role/{role_name}"

                    self.log(f"Renewing {target_profile_name} access keys...")
                    cmd = f'aws sts assume-role --role-arn {target_role} --role-session-name {user} --profile {MFA_SESSION} --query Credentials --output json'
                    success, output = self.run_aws_command(cmd)

                    if not success:
                        self.log(f"Failed to assume role for {target_profile_name} (Account: {target_account_num}): {output}")
                        renewal_failed = True
                        continue

                    creds = json.loads(output)

                    self.set_profile(target_profile_name, creds, default_region)
                    self.log(f"{target_profile_name} profile has been updated in ~/.aws/credentials.")

                    # If this is the user-selected default profile, mirror credentials into [default]
                    if target_profile_name == self.default_profile_name:
                        self.set_profile(DEFAULT_SESSION, creds, default_region)
                        self.log(f"Mirrored {target_profile_name} credentials into [{DEFAULT_SESSION}] profile.")

                    if target_profile_name == codeartifact_source_profile:
                        codeartifact_creds = creds

                # Use the dev-test-perf credentials for CodeArtifact (npm/pip) if requested
                if (self.npm_token or self.pip_token) and codeartifact_creds and not self.should_stop:
                    try:
                        self.set_profile(CODEARTIFACT_SESSION, codeartifact_creds, default_region)

                        if self.npm_token:
                            cmd_token = f'aws codeartifact get-authorization-token --domain nice-devops --domain-owner 369498121101 --query authorizationToken --output text --region us-west-2 --profile {CODEARTIFACT_SESSION}'
                            success_token, ca_token = self.run_aws_command(cmd_token)

                            if success_token:
                                self.log(f"Generated CodeArtifact Token using {codeartifact_source_profile} credentials.")
                                try:
                                    self.run_aws_command('npm config set registry "https://nice-devops-369498121101.d.codeartifact.us-west-2.amazonaws.com/npm/cxone-npm/"')
                                    self.run_aws_command(f'npm config set "//nice-devops-369498121101.d.codeartifact.us-west-2.amazonaws.com/npm/cxone-npm/:_authToken={ca_token.strip()}"')
                                    self.log("Updated NPM with CodeArtifact Token.")
                                except Exception as e:
                                    self.log(f"NPM not installed or error: {e}")
                            else:
                                self.log(f"Failed to get CodeArtifact token: {ca_token}")

                        if self.pip_token:
                            cmd_pip = f'aws codeartifact login --tool pip --repository cxone-pystore --domain nice-devops --domain-owner 369498121101 --region us-west-2 --profile {CODEARTIFACT_SESSION}'
                            success_pip, output_pip = self.run_aws_command(cmd_pip)
                            if success_pip:
                                self.log("pip authenticated against cxone-pystore.")
                            else:
                                self.log(f"pip CodeArtifact login failed: {output_pip}")
                    except Exception as e:
                        self.log(f"Error generating CodeArtifact token: {e}")
                elif self.npm_token or self.pip_token:
                    self.log(f"Skipping CodeArtifact: {codeartifact_source_profile} credentials not available.")

                if renewal_failed:
                    self.log("One or more profiles failed to renew. Continuing with next cycle.")

                self.signals.progress_update.emit(False)
                hour_text = "hour" if hours_remaining == 1 else "hours"
                self.signals.status_update.emit(f"✅ Running ({hours_remaining}h)")
                self.log(f"Keep this window open to have your keys renewed every 59 minutes for the next {hours_remaining} {hour_text}.")

                for minute in range(59, 0, -1):
                    # 1-second granularity so Stop reacts immediately (was a 60s blocking sleep)
                    for _ in range(60):
                        if self.should_stop:
                            break
                        time.sleep(1)
                    if self.should_stop:
                        break
                    if minute % 10 == 0:
                        self.signals.status_update.emit(f"⏳ Waiting... ({hours_remaining}h, {minute}m)")

                hours_remaining -= 1

            if self.should_stop:
                self.signals.finished.emit(True, "Stopped by user")
                self.log("Process stopped by user")
            else:
                self.signals.finished.emit(True, "MFA token credentials have expired. Please restart this script.")
                self.log("MFA token credentials have expired. Please restart this script.")

        except Exception as e:
            self.log(f"Error: {str(e)}")
            self.signals.finished.emit(False, f"Error: {str(e)}")
    
    def stop(self):
        """Stop the worker thread"""
        self.should_stop = True


class BackgroundImageWidget(QWidget):
    """Widget with background image and AWS cloud logo"""
    
    def __init__(self, parent=None):
        super().__init__(parent)
        self.backgroundPixmap = None
        self.loadBackgroundImage()
        
    def loadBackgroundImage(self):
        """Load background image"""
        bg_path = Path(resource_path("background.jpg"))
        if bg_path.exists():
            self.backgroundPixmap = QPixmap(str(bg_path))
        
    def paintEvent(self, event):
        """Paint background image with AWS logo"""
        painter = QPainter(self)
        painter.setRenderHint(QPainter.Antialiasing)
        painter.setRenderHint(QPainter.SmoothPixmapTransform)
        
        if self.backgroundPixmap:
            scaled = self.backgroundPixmap.scaled(
                self.size(),
                Qt.KeepAspectRatioByExpanding,
                Qt.SmoothTransformation
            )
            x = (self.width() - scaled.width()) // 2
            y = (self.height() - scaled.height()) // 2
            painter.drawPixmap(x, y, scaled)
        else:
            gradient = QLinearGradient(0, 0, self.width(), self.height())
            gradient.setColorAt(0.0, QColor(0, 120, 212))
            gradient.setColorAt(0.5, QColor(0, 160, 240))
            gradient.setColorAt(1.0, QColor(0, 120, 212))
            painter.fillRect(self.rect(), QBrush(gradient))
        


class MFADialog(MessageBoxBase):
    """Simple MFA Dialog"""
    
    def __init__(self, account_name, parent=None):
        super().__init__(parent)
        self.titleLabel = SubtitleLabel(f"Mfa Code")
        self.titleLabel.setAlignment(Qt.AlignCenter)
        self.mfaInput = LineEdit(self)
        self.mfaInput.setMaxLength(6)
        self.mfaInput.setClearButtonEnabled(True)
        self.warningLabel = CaptionLabel("MFA code must be 6 digits")
        self.warningLabel.setStyleSheet("color: #d13438;")
        self.warningLabel.setHidden(True)
        self.viewLayout.addWidget(self.titleLabel)
        self.viewLayout.addWidget(self.mfaInput)
        self.viewLayout.addWidget(self.warningLabel)
        
        self.widget.setMinimumWidth(320)
        self.yesButton.setText("Go !")
        self.cancelButton.setText("Exit !")
        
        self.mfaInput.setFocus()
    
    def validate(self):
        """Validate MFA code"""
        mfa_code = self.mfaInput.text()
        isValid = len(mfa_code) == 6 and mfa_code.isdigit()
        self.warningLabel.setHidden(isValid)
        return isValid


class AWSManagerWindow(Window):
    """Main AWS Credential Manager Window - Login Style"""
    
    def __init__(self):
        super().__init__()
        
        self.worker = None
        self.is_running = False
        self.shouldReallyClose = False
        
        setTheme(Theme.AUTO)
        setThemeColor('#0078d4')
        
        self.initUI()
        self.initWindow()
        self.initSystemTray()
        
    def initUI(self):
        """Initialize UI - Clean and elegant"""
        
        # Main horizontal layout
        mainLayout = QHBoxLayout(self)
        mainLayout.setContentsMargins(0, 0, 0, 0)
        mainLayout.setSpacing(0)
        
        # Left side - Background image with AWS logo
        self.backgroundWidget = BackgroundImageWidget(self)
        mainLayout.addWidget(self.backgroundWidget)
        
        # Right side - Clean control panel
        self.controlPanel = QWidget(self)
        self.controlPanel.setMinimumWidth(320)
        self.controlPanel.setMaximumWidth(320)
        self.controlPanel.setStyleSheet("""
            QWidget {
                background: transparent;
            }
            QLabel {
                font: 13px 'Segoe UI';
            }
        """)
        
        panelLayout = QVBoxLayout(self.controlPanel)
        panelLayout.setContentsMargins(25, 25, 25, 25)
        panelLayout.setSpacing(10)
        
        # Top spacer
        panelLayout.addSpacerItem(QSpacerItem(20, 60, QSizePolicy.Minimum, QSizePolicy.Expanding))
        
        # Logo - painted cloud (blue, sized so the glyph can't overflow onto the title)
        class CloudLogoWidget(QWidget):
            def __init__(self, parent=None):
                super().__init__(parent)
                self.setFixedSize(150, 130)

            def paintEvent(self, event):
                painter = QPainter(self)
                painter.setRenderHint(QPainter.Antialiasing)
                painter.setPen(QColor(96, 165, 250, 230))
                font = painter.font()
                font.setPointSize(58)
                font.setBold(True)
                painter.setFont(font)
                painter.drawText(self.rect(), Qt.AlignCenter, "☁")

        panelLayout.addWidget(CloudLogoWidget(), 0, Qt.AlignCenter)

        panelLayout.addSpacerItem(QSpacerItem(20, 16, QSizePolicy.Minimum, QSizePolicy.Fixed))

        # Title - styled, below the logo
        titleLabel = SubtitleLabel("AWS Credentials Manager")
        titleLabel.setAlignment(Qt.AlignCenter)
        titleLabel.setStyleSheet("font: 600 14px 'Segoe UI'; letter-spacing: 0.5px; color: #60A5FA;")
        panelLayout.addWidget(titleLabel)

        panelLayout.addSpacerItem(QSpacerItem(20, 30, QSizePolicy.Minimum, QSizePolicy.Fixed))

        self.accountCombo = ComboBox()
        defaultIndex = 0
        for i, account in enumerate(AWS_ACCOUNTS):
            self.accountCombo.addItem(f"{account['name']}", userData=account)
            if account['name'] == 'dev-test-perf':
                defaultIndex = i
        self.accountCombo.setCurrentIndex(defaultIndex)
        self.accountCombo.setFixedWidth(190)
        panelLayout.addWidget(self.accountCombo, 0, Qt.AlignCenter)

        panelLayout.addSpacerItem(QSpacerItem(20, 10, QSizePolicy.Minimum, QSizePolicy.Fixed))

        # CodeArtifact token options - unchecked by default, side by side
        tokenRow = QHBoxLayout()
        tokenRow.setSpacing(16)
        self.npmTokenCheck = CheckBox("npm")
        self.pipTokenCheck = CheckBox("pip")
        tokenRow.addStretch()
        tokenRow.addWidget(self.npmTokenCheck)
        tokenRow.addWidget(self.pipTokenCheck)
        tokenRow.addStretch()
        panelLayout.addLayout(tokenRow)

        panelLayout.addSpacerItem(QSpacerItem(20, 15, QSizePolicy.Minimum, QSizePolicy.Fixed))
        
        # Start button - compact, centered
        self.startButton = PrimaryPushButton(FIF.PLAY, "Start")
        self.startButton.setFixedSize(110, 32)
        self.startButton.clicked.connect(self.onStartClicked)
        panelLayout.addWidget(self.startButton, 0, Qt.AlignCenter)

        # Stop button
        self.stopButton = PushButton(FIF.PAUSE, "Stop")
        self.stopButton.setFixedSize(110, 32)
        self.stopButton.clicked.connect(self.onStopClicked)
        self.stopButton.hide()
        panelLayout.addWidget(self.stopButton, 0, Qt.AlignCenter)
        
        panelLayout.addSpacerItem(QSpacerItem(20, 10, QSizePolicy.Minimum, QSizePolicy.Fixed))
        
        # View logs link
        debug_log("initUI: creating viewLogsLink HyperlinkButton")
        self.viewLogsLink = HyperlinkButton(
            url="",
            text="View Logs",
            parent=self.controlPanel
        )
        self.viewLogsLink.clicked.connect(self.onViewLogsClicked)
        debug_log("initUI: viewLogsLink.clicked connected to onViewLogsClicked")
        panelLayout.addWidget(self.viewLogsLink, 0, Qt.AlignCenter)
        
        panelLayout.addSpacerItem(QSpacerItem(20, 20, QSizePolicy.Minimum, QSizePolicy.Fixed))
        
        # Status area - centered
        statusContainer = QWidget()
        statusLayout = QHBoxLayout(statusContainer)
        statusLayout.setContentsMargins(0, 0, 0, 0)
        statusLayout.setSpacing(8)
        
        statusLayout.addStretch()
        
        self.progressRing = ProgressRing()
        self.progressRing.setFixedSize(16, 16)
        self.progressRing.hide()
        statusLayout.addWidget(self.progressRing)
        
        self.statusLabel = CaptionLabel("⚪ Ready")
        self.statusLabel.setStyleSheet("color: gray;")
        statusLayout.addWidget(self.statusLabel)
        
        statusLayout.addStretch()
        
        panelLayout.addWidget(statusContainer)
        
        # Bottom spacer
        panelLayout.addSpacerItem(QSpacerItem(20, 60, QSizePolicy.Minimum, QSizePolicy.Expanding))
        
        mainLayout.addWidget(self.controlPanel)
        
    def initWindow(self):
        """Initialize window properties"""
        
        # Set split title bar (like login) - no icon/text over the background image
        self.setTitleBar(SplitTitleBar(self))
        self.titleBar.iconLabel.hide()
        self.titleBar.titleLabel.hide()
        self.titleBar.raise_()
        
        # self.titleBar.titleLabel.setText("🔐 AWS Credential Manager")
        self.titleBar.titleLabel.setStyleSheet("""
            QLabel {
                background: transparent;
                font: 13px 'Segoe UI';
                padding: 0 4px;
                color: white;
            }
        """)
        
        # Window properties - fixed size
        self.setWindowIcon(QIcon(resource_path("managerAws.ico")))
        self.setWindowTitle("AWS Credential Manager")
        self.setFixedSize(600, 425)
        
        # Center on screen
        desktop = QApplication.desktop().availableGeometry()
        w, h = desktop.width(), desktop.height()
        self.move(w//2 - self.width()//2, h//2 - self.height()//2)
        
        # Apply Mica effect for Windows 11
        if isWin11():
            try:
                self.windowEffect.setMicaEffect(self.winId(), isDarkMode=isDarkTheme())
            except:
                pass
        
        # Fallback background
        if not isWin11():
            color = QColor(25, 33, 42) if isDarkTheme() else QColor(240, 244, 249)
            self.setStyleSheet(f"AWSManagerWindow{{background: {color.name()}}}")
    
    def initSystemTray(self):
        """Initialize system tray"""
        
        self.trayIcon = QSystemTrayIcon(self)
        self.trayIcon.setIcon(QIcon(resource_path("managerAws.ico")))
        self.trayIcon.setToolTip("AWS Credential Manager")
        
        trayMenu = QMenu()
        
        showAction = QAction("Show Window", self)
        showAction.triggered.connect(self.showNormal)
        trayMenu.addAction(showAction)
        
        trayMenu.addSeparator()
        
        exitAction = QAction("Exit", self)
        exitAction.triggered.connect(self.reallyClose)
        trayMenu.addAction(exitAction)
        
        self.trayIcon.setContextMenu(trayMenu)
        self.trayIcon.activated.connect(self.onTrayIconActivated)
    
    def changeEvent(self, event):
        """Minimize button hides to system tray - same behavior as managerAws.ps1"""
        if event.type() == QEvent.WindowStateChange and self.isMinimized():
            event.ignore()
            QTimer.singleShot(0, self.hide)
            self.trayIcon.show()
            self.trayIcon.showMessage(
                "AWS Credential Manager",
                "Application minimized to system tray",
                QSystemTrayIcon.Information,
                2000
            )
            return
        super().changeEvent(event)

    def onTrayIconActivated(self, reason):
        """Handle tray icon activation"""
        if reason == QSystemTrayIcon.DoubleClick:
            self.showNormal()
            self.activateWindow()
    
    def onAccountSelected(self, index):
        """Handle account icon selection"""
        self.accountCombo.setCurrentIndex(index)
    
    def getSelectedAccount(self):
        """Get currently selected account"""
        index = self.accountCombo.currentIndex()
        return AWS_ACCOUNTS[index]
    
    def onStartClicked(self):
        """Handle start button - show MFA dialog or auto-generate code"""
        account = self.getSelectedAccount()
        mfa_secret_key = CONFIG.get("mfa_secret_key", "")
        
        if not mfa_secret_key:
            mfaDialog = MFADialog(account['name'], self)
            
            if mfaDialog.exec():
                mfa_code = mfaDialog.mfaInput.text()
                self.startCredentialProcess(account, mfa_code)
        else:
            mfa_code = generate_totp(mfa_secret_key)
            
            if not mfa_code:
                InfoBar.error(
                    title="MFA Generation Error",
                    content="Failed to generate MFA code automatically. Please check your secret key configuration.",
                    orient=Qt.Horizontal,
                    isClosable=True,
                    position=InfoBarPosition.TOP,
                    duration=5000,
                    parent=self
                )
                return
            
            InfoBar.info(
                title="Auto MFA",
                content=f"MFA code generated: {mfa_code}",
                orient=Qt.Horizontal,
                isClosable=True,
                position=InfoBarPosition.TOP,
                duration=2000,
                parent=self
            )
            self.startCredentialProcess(account, mfa_code)
    
    def startCredentialProcess(self, account, mfa_code):
        """Start credential process"""

        self.is_running = True
        self.startButton.hide()
        self.stopButton.show()
        self.accountCombo.setEnabled(False)
        self.npmTokenCheck.setEnabled(False)
        self.pipTokenCheck.setEnabled(False)

        self.updateStatus("🔄 Starting...")

        InfoBar.success(
            title="Starting",
            content=f"Default: {account['name']} | All profiles will be renewed",
            orient=Qt.Horizontal,
            isClosable=True,
            position=InfoBarPosition.TOP,
            duration=2000,
            parent=self
        )

        signals = WorkerSignals()
        signals.status_update.connect(self.updateStatus)
        signals.progress_update.connect(self.updateProgress)
        signals.finished.connect(self.onProcessFinished)

        self.worker = AWSCredentialWorker(
            account['name'], AWS_ACCOUNTS, mfa_code, CONFIG, signals,
            npm_token=self.npmTokenCheck.isChecked(),
            pip_token=self.pipTokenCheck.isChecked()
        )
        self.worker.start()
    
    def onStopClicked(self):
        """Handle stop button"""
        if self.worker:
            self.updateStatus("⏸️ Stopping...")
            self.worker.stop()
    
    def onViewLogsClicked(self):
        """Open log file"""
        debug_log("onViewLogsClicked: clicked")
        log_file = Path(__file__).parent / "aws_manager.log"
        debug_log(f"onViewLogsClicked: log_file = {log_file.resolve()}")
        debug_log(f"onViewLogsClicked: log_file.exists() = {log_file.exists()}")

        if not log_file.exists():
            debug_log("onViewLogsClicked: file does not exist, creating placeholder")
            try:
                log_file.parent.mkdir(parents=True, exist_ok=True)
                with open(log_file, "a", encoding="utf-8") as f:
                    timestamp = datetime.now().strftime("%H:%M:%S")
                    f.write(f"[{timestamp}] Log file created. Start the service to see activity.\n")
                debug_log("onViewLogsClicked: placeholder created successfully")
            except Exception as e:
                debug_log(f"onViewLogsClicked: failed to create placeholder: {e}\n{traceback.format_exc()}")
                InfoBar.error(
                    title="Cannot Create Log",
                    content=str(e),
                    orient=Qt.Horizontal,
                    isClosable=True,
                    position=InfoBarPosition.TOP,
                    duration=4000,
                    parent=self
                )
                return

        # Open with notepad directly - .log files often have no file association,
        # which causes os.startfile to silently do nothing.
        try:
            debug_log(f"onViewLogsClicked: launching notepad for {log_file}")
            subprocess.Popen(["notepad.exe", str(log_file)])
            debug_log("onViewLogsClicked: notepad launched successfully")
        except Exception as e:
            debug_log(f"onViewLogsClicked: notepad failed: {e}\n{traceback.format_exc()}")
            # Fallback to os.startfile in case notepad isn't on PATH for some reason
            try:
                debug_log("onViewLogsClicked: trying os.startfile fallback")
                os.startfile(str(log_file))
                debug_log("onViewLogsClicked: os.startfile fallback returned")
            except Exception as e2:
                debug_log(f"onViewLogsClicked: os.startfile fallback failed: {e2}\n{traceback.format_exc()}")
                InfoBar.error(
                    title="Cannot Open Log",
                    content=f"{e2}",
                    orient=Qt.Horizontal,
                    isClosable=True,
                    position=InfoBarPosition.TOP,
                    duration=4000,
                    parent=self
                )
    
    def updateStatus(self, message):
        """Update status label"""
        self.statusLabel.setText(message)
    
    def updateProgress(self, show):
        """Show/hide progress ring"""
        if show:
            self.progressRing.show()
        else:
            self.progressRing.hide()
    
    def onProcessFinished(self, success, message):
        """Handle process completion"""
        
        self.is_running = False
        self.startButton.show()
        self.stopButton.hide()
        self.accountCombo.setEnabled(True)
        self.npmTokenCheck.setEnabled(True)
        self.pipTokenCheck.setEnabled(True)
        self.progressRing.hide()
        
        if success:
            self.statusLabel.setText("⚪ Ready")
            InfoBar.success(
                title="Completed",
                content=message,
                orient=Qt.Horizontal,
                isClosable=True,
                position=InfoBarPosition.TOP,
                duration=3000,
                parent=self
            )
        else:
            self.statusLabel.setText("❌ Error")
            InfoBar.error(
                title="Failed",
                content=message,
                orient=Qt.Horizontal,
                isClosable=True,
                position=InfoBarPosition.TOP,
                duration=5000,
                parent=self
            )
    
    def closeEvent(self, event):
        """Handle window close - minimize to tray"""
        if not self.shouldReallyClose:
            event.ignore()
            self.hide()
            self.trayIcon.show()
            self.trayIcon.showMessage(
                "AWS Credential Manager",
                "Application minimized to system tray",
                QSystemTrayIcon.Information,
                2000
            )
        else:
            if self.worker:
                self.worker.stop()
            self.trayIcon.hide()
            event.accept()
    
    def reallyClose(self):
        """Actually close the application"""
        self.shouldReallyClose = True
        self.close()


def main():
    """Main entry point"""
    
    # Enable high DPI scaling
    QApplication.setHighDpiScaleFactorRoundingPolicy(
        Qt.HighDpiScaleFactorRoundingPolicy.PassThrough)
    QApplication.setAttribute(Qt.AA_EnableHighDpiScaling)
    QApplication.setAttribute(Qt.AA_UseHighDpiPixmaps)
    
    app = QApplication(sys.argv)
    app.setApplicationName("awsCredentialsManager")
    
    window = AWSManagerWindow()
    window.show()
    
    sys.exit(app.exec_())


if __name__ == '__main__':
    main()









# pyinstaller --onefile --windowed --name "AWSCredentialsManager" --icon "your_icon.ico" --add-data "background.jpg;." awsManager.py
# pyinstaller --onefile --windowed --name "AWSCredentialsManager" --add-data "background.jpg;." --hidden-import "qfluentwidgets" --hidden-import "qframelesswindow" awsManager.py