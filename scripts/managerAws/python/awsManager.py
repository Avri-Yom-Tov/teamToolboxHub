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
import hmac
import hashlib
import struct
from datetime import datetime
from pathlib import Path

from PyQt5.QtCore import Qt, pyqtSignal, QObject, QSize
from PyQt5.QtGui import QIcon, QColor, QPixmap, QPainter, QLinearGradient, QBrush
from PyQt5.QtWidgets import QApplication, QWidget, QVBoxLayout, QHBoxLayout, QSystemTrayIcon, QMenu, QAction, QLabel, QSpacerItem, QSizePolicy
from qfluentwidgets import (
    setTheme, Theme, setThemeColor, isDarkTheme,
    PrimaryPushButton, PushButton, ComboBox, LineEdit,
    TitleLabel, SubtitleLabel, BodyLabel, CaptionLabel, StrongBodyLabel,
    ProgressRing, InfoBar, InfoBarPosition, MessageBox, MessageBoxBase,
    FluentIcon as FIF, SplitTitleBar, CheckBox, HyperlinkButton
)

def isWin11():
    """Check if running on Windows 11"""
    return sys.platform == 'win32' and sys.getwindowsversion().build >= 22000

if isWin11():
    from qframelesswindow import AcrylicWindow as Window
else:
    from qframelesswindow import FramelessWindow as Window


# Configuration - matching PowerShell script
AWS_ACCOUNTS = [
    {"id": "730335479582", "name": "rec-dev"},
    {"id": "211125581625", "name": "rec-test"},
    {"id": "339712875220", "name": "rec-perf"},
    {"id": "918987959928", "name": "production"},
    {"id": "891377049518", "name": "rec-staging"},
    {"id": "934137132601", "name": "dev-test-perf"},
    {"id": "654654430801", "name": "production-rec"},
    {"id": "891377174057", "name": "production-rec-uk"},
]

CONFIG = {
    "user": os.environ.get("awsUserName", "Avraham.Yom-Tov"),
    "token_expiration_hours": 36,
    "default_region": "us-west-2",
    "source_profile": "nice-identity",
    "main_iam_acct_num": "736763050260",
    "role_name": "GroupAccess-Developers-Recording",
    "target_account_num_codeartifact": "369498121101",
    "target_profile_name_codeartifact": "GroupAccess-NICE-Developers",
    "mfa_secret_key": os.environ.get("mfaSecretKey", "")
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
    
    def __init__(self, account, mfa_code, config, signals):
        super().__init__()
        self.account = account
        self.mfa_code = mfa_code
        self.config = config
        self.signals = signals
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
                timeout=30
            )
            return result.returncode == 0, result.stdout if result.returncode == 0 else result.stderr
        except Exception as e:
            return False, str(e)
    
    def add_new_line(self, profile_name):
        """Add new line to credentials and config files to prevent CLI issues"""
        home = Path.home()
        
        creds_file = home / ".aws" / "credentials"
        if creds_file.exists():
            try:
                content = creds_file.read_text(encoding='utf-8')
                if profile_name not in content:
                    with open(creds_file, 'a', encoding='utf-8') as f:
                        f.write("\r\n")
            except Exception as e:
                self.log(f"Error adding newline to credentials: {e}")
        
        config_file = home / ".aws" / "config"
        if config_file.exists():
            try:
                content = config_file.read_text(encoding='utf-8')
                if profile_name not in content:
                    with open(config_file, 'a', encoding='utf-8') as f:
                        f.write("\r\n")
            except Exception as e:
                self.log(f"Error adding newline to config: {e}")
    
    def run(self):
        """Main worker thread logic - Following PowerShell script flow"""
        try:
            self.signals.progress_update.emit(True)
            self.signals.status_update.emit("🔐 Authenticating with MFA...")
            
            user = self.config['user']
            source_profile = self.config['source_profile']
            main_iam_acct_num = self.config['main_iam_acct_num']
            role_name = self.config['role_name']
            default_region = self.config['default_region']
            target_account_num = self.account['id']
            target_profile_name = self.account['name']
            target_account_num_codeartifact = self.config['target_account_num_codeartifact']
            target_profile_name_codeartifact = self.config['target_profile_name_codeartifact']
            token_expiration_seconds = self.config['token_expiration_hours'] * 3600
            
            self.log("**********************************************************************************************************")
            self.log(f"This script will obtain temporary credentials for {target_profile_name} and {target_profile_name_codeartifact} and store them")
            self.log("in your AWS CLI configuration. This will allow certain programs (e.g., IntelliJ IDEA)")
            self.log(f"to access {target_profile_name} and {target_profile_name_codeartifact} through your {source_profile} account.")
            self.log("**********************************************************************************************************")
            
            MFA_SESSION = f"{source_profile}-mfa-session"
            DEFAULT_SESSION = "default"
            CODEARTIFACT_SESSION = "default-codeartifact"
            
            mfa_device = f"arn:aws:iam::{main_iam_acct_num}:mfa/{user}"
            target_role = f"arn:aws:iam::{target_account_num}:role/{role_name}"
            target_role_codeartifact = f"arn:aws:iam::{target_account_num_codeartifact}:role/{role_name}"
            
            self.log(f"MFA Device: {mfa_device}")
            self.log(f"Target Role: {target_role}")
            
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
            
            self.run_aws_command(f'aws configure set aws_access_key_id {token_creds["Credentials"]["AccessKeyId"]} --profile {MFA_SESSION}')
            self.run_aws_command(f'aws configure set aws_secret_access_key {token_creds["Credentials"]["SecretAccessKey"]} --profile {MFA_SESSION}')
            self.run_aws_command(f'aws configure set aws_session_token {token_creds["Credentials"]["SessionToken"]} --profile {MFA_SESSION}')
            self.run_aws_command(f'aws configure set region {default_region} --profile {target_profile_name}')
            self.run_aws_command(f'aws configure set region {default_region} --profile {target_profile_name_codeartifact}')
            
            self.log(f"Successfully cached token for {token_expiration_seconds} seconds ..")
            
            self.signals.progress_update.emit(False)
            hours_remaining = self.config['token_expiration_hours']
            
            while hours_remaining > 0 and not self.should_stop:
                self.signals.progress_update.emit(True)
                self.signals.status_update.emit(f"🔄 Renewing {target_profile_name}...")
                self.log(f"Renewing {target_profile_name} access keys...")
                
                cmd = f'aws sts assume-role --role-arn {target_role} --role-session-name {user} --profile {MFA_SESSION} --query Credentials --output json'
                success, output = self.run_aws_command(cmd)
                
                if not success:
                    self.log(f"Failed to assume role: {output}")
                    self.signals.finished.emit(False, f"Role assumption failed: {output}")
                    return
                
                creds = json.loads(output)
                
                self.log(f"Renewing {target_profile_name_codeartifact} access keys...")
                cmd_ca = f'aws sts assume-role --role-arn {target_role_codeartifact} --role-session-name {user} --profile {MFA_SESSION} --query Credentials --output json'
                success_ca, output_ca = self.run_aws_command(cmd_ca)
                
                if not success_ca:
                    self.log(f"Failed to assume codeartifact role: {output_ca}")
                
                creds_codeartifact = json.loads(output_ca) if success_ca else None
                
                self.add_new_line(target_profile_name)
                
                self.run_aws_command(f'aws configure set aws_access_key_id {creds["AccessKeyId"]} --profile {DEFAULT_SESSION}')
                self.run_aws_command(f'aws configure set aws_secret_access_key {creds["SecretAccessKey"]} --profile {DEFAULT_SESSION}')
                self.run_aws_command(f'aws configure set aws_session_token {creds["SessionToken"]} --profile {DEFAULT_SESSION}')
                self.run_aws_command(f'aws configure set region {default_region} --profile {DEFAULT_SESSION}')
                
                self.log(f"{target_profile_name} profile has been updated in ~/.aws/credentials.")
                
                if creds_codeartifact:
                    self.add_new_line(target_profile_name_codeartifact)
                    
                    self.run_aws_command(f'aws configure set aws_access_key_id {creds_codeartifact["AccessKeyId"]} --profile {CODEARTIFACT_SESSION}')
                    self.run_aws_command(f'aws configure set aws_secret_access_key {creds_codeartifact["SecretAccessKey"]} --profile {CODEARTIFACT_SESSION}')
                    self.run_aws_command(f'aws configure set aws_session_token {creds_codeartifact["SessionToken"]} --profile {CODEARTIFACT_SESSION}')
                    self.run_aws_command(f'aws configure set region {default_region} --profile {CODEARTIFACT_SESSION}')
                    
                    self.log(f"{target_profile_name_codeartifact} profile has been updated in ~/.aws/credentials.")
                    
                    cmd_token = f'aws codeartifact get-authorization-token --domain nice-devops --domain-owner 369498121101 --query authorizationToken --output text --region us-west-2 --profile {CODEARTIFACT_SESSION}'
                    success_token, ca_token = self.run_aws_command(cmd_token)
                    
                    if success_token:
                        self.log("Generated CodeArtifact Token.")
                        
                        try:
                            import xml.etree.ElementTree as ET
                            settings_file = Path(f"C:\\Users\\{os.environ.get('USERNAME')}\\.m2\\settings.xml")
                            if settings_file.exists():
                                ET.register_namespace('', 'http://maven.apache.org/SETTINGS/1.0.0')
                                tree = ET.parse(settings_file)
                                root = tree.getroot()
                                
                                for server in root.iter():
                                    if server.tag.endswith('server'):
                                        server_id = None
                                        password_elem = None
                                        for child in server:
                                            if child.tag.endswith('id'):
                                                server_id = child.text
                                            if child.tag.endswith('password'):
                                                password_elem = child
                                        
                                        if server_id in ['cxone-codeartifact', 'platform-utils', 'plugins-codeartifact'] and password_elem is not None:
                                            password_elem.text = ca_token.strip()
                                
                                tree.write(settings_file, encoding='utf-8', xml_declaration=True)
                                self.log(f"Updated {settings_file} with CodeArtifact Token.")
                        except Exception as e:
                            self.log(f"No settings.xml found or using old version: {e}")
                        
                        try:
                            self.run_aws_command('npm config set registry "https://nice-devops-369498121101.d.codeartifact.us-west-2.amazonaws.com/npm/cxone-npm/"')
                            self.run_aws_command(f'npm config set "//nice-devops-369498121101.d.codeartifact.us-west-2.amazonaws.com/npm/cxone-npm/:_authToken={ca_token.strip()}"')
                            self.log("Updated NPM with CodeArtifact Token.")
                        except Exception as e:
                            self.log(f"NPM not installed or error: {e}")
                
                self.signals.progress_update.emit(False)
                hour_text = "hour" if hours_remaining == 1 else "hours"
                self.signals.status_update.emit(f"✅ Running ({hours_remaining}h)")
                self.log(f"Keep this window open to have your keys renewed every 59 minutes for the next {hours_remaining} {hour_text}.")
                
                for minute in range(59, 0, -1):
                    if self.should_stop:
                        break
                    time.sleep(60)
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
        bg_path = Path(__file__).parent / "background.jpg"
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
        
        # Logo - Custom painted cloud
        class CloudLogoWidget(QWidget):
            def __init__(self, parent=None):
                super().__init__(parent)
                self.setFixedSize(100, 80)
            
            def paintEvent(self, event):
                painter = QPainter(self)
                painter.setRenderHint(QPainter.Antialiasing)
                
                painter.setPen(QColor(255, 255, 255, 200))
                font = painter.font()
                font.setPointSize(55)
                font.setBold(True)
                painter.setFont(font)
                painter.drawText(self.rect(), Qt.AlignCenter, "☁")
        
        logoWidget = CloudLogoWidget()
        panelLayout.addWidget(logoWidget, 0, Qt.AlignCenter)
        
        panelLayout.addSpacerItem(QSpacerItem(20, 5, QSizePolicy.Minimum, QSizePolicy.Fixed))
        
        # Title - centered
        titleLabel = SubtitleLabel("Aws Credentials Manager")
        titleLabel.setAlignment(Qt.AlignCenter)
        panelLayout.addWidget(titleLabel)
        
        panelLayout.addSpacerItem(QSpacerItem(20, 30, QSizePolicy.Minimum, QSizePolicy.Fixed))
        
        
        self.accountCombo = ComboBox()
        for account in AWS_ACCOUNTS:
            self.accountCombo.addItem(f"{account['name']}", userData=account)
        self.accountCombo.setCurrentIndex(0)
        panelLayout.addWidget(self.accountCombo)
        
        panelLayout.addSpacerItem(QSpacerItem(20, 15, QSizePolicy.Minimum, QSizePolicy.Fixed))
        
        # Start button - smaller and elegant
        self.startButton = PrimaryPushButton(FIF.PLAY, "Start")
        self.startButton.setFixedHeight(36)
        self.startButton.clicked.connect(self.onStartClicked)
        panelLayout.addWidget(self.startButton)
        
        # Stop button
        self.stopButton = PushButton(FIF.PAUSE, "Stop")
        self.stopButton.setFixedHeight(36)
        self.stopButton.clicked.connect(self.onStopClicked)
        self.stopButton.hide()
        panelLayout.addWidget(self.stopButton)
        
        panelLayout.addSpacerItem(QSpacerItem(20, 10, QSizePolicy.Minimum, QSizePolicy.Fixed))
        
        # View logs link
        self.viewLogsLink = HyperlinkButton(
            url="",
            text="View Logs",
            parent=self.controlPanel
        )
        self.viewLogsLink.clicked.connect(self.onViewLogsClicked)
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
        
        # Set split title bar (like login)
        self.setTitleBar(SplitTitleBar(self))
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
        self.trayIcon.setToolTip("awsAppManager")
        
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
        
        self.updateStatus("🔄 Starting...")
        
        InfoBar.success(
            title="Starting",
            content=f"Connecting to {account['name']}",
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
        
        self.worker = AWSCredentialWorker(account, mfa_code, CONFIG, signals)
        self.worker.start()
    
    def onStopClicked(self):
        """Handle stop button"""
        if self.worker:
            self.updateStatus("⏸️ Stopping...")
            self.worker.stop()
    
    def onViewLogsClicked(self):
        """Open log file"""
        log_file = Path(__file__).parent / "aws_manager.log"
        if log_file.exists():
            os.startfile(str(log_file))
        else:
            InfoBar.warning(
                title="No Logs",
                content="Start the service first",
                orient=Qt.Horizontal,
                isClosable=True,
                position=InfoBarPosition.TOP,
                duration=2000,
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
                # "AWS Credential Manager",
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