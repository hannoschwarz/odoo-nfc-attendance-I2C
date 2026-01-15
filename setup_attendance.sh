#!/bin/bash

# Exit immediately if a command exits with a non-zero status.
set -e

PROJECT_DIR="~/attendance"

echo "🚀 Starting Odoo NFC Kiosk Installation..."

# --- 1. SYSTEM UPDATES & BUILD TOOLS ---
echo "⚙️ Installing System Dependencies..."
sudo apt update
sudo apt install -y python3-pip python3-venv git unclutter chromium-browser \
     netcat-openbsd swig python3-dev liblgpio-dev build-essential p7zip-full \
     python3-lgpio wget

# --- 2. INSTALL WIRINGPI (DEBIAN BUILD) ---
echo "🏗️ Building WiringPi..."
cd ~
if [ ! -d "WiringPi" ]; then
    git clone https://github.com/WiringPi/WiringPi.git
fi
cd WiringPi
./build debian
DEB_FILE=$(ls wiringpi-*.deb | head -n 1)
sudo apt install ./"$DEB_FILE" -y

# --- 3. DOWNLOAD & EXTRACT PN532 DEMO ---
echo "📦 Downloading Waveshare PN532 Library..."
cd ~
wget -N https://files.waveshare.com/upload/6/67/pn532-nfc-hat-code.7z
7z x pn532-nfc-hat-code.7z -r -o./Pn532-nfc-hat-code -y
sudo chmod 777 -R Pn532-nfc-hat-code/

# --- 4. PROJECT STRUCTURE ---
echo "📂 Organizing Project Folders..."
mkdir -p $PROJECT_DIR/templates

# Copy only the driver folder into our project
cp -r ~/Pn532-nfc-hat-code/RaspberryPi/python/pn532 $PROJECT_DIR/
touch $PROJECT_DIR/pn532/__init__.py

# --- 5. PYTHON VIRTUAL ENVIRONMENT ---
echo "🐍 Setting up Python Environment..."
cd $PROJECT_DIR
python3 -m venv env
source env/bin/activate
# Install all required libraries
pip install flask flask-socketio requests eventlet pyserial spidev rpi-lgpio python-dotenv
deactivate

# --- 6. CONFIGURATION (DOTENV) ---
echo "📄 Setting up Configuration template..."
if [ ! -f .env ]; then
    cat <<EOF > .env
# Odoo Webhook URL (from Automation Rule)
ODOO_WEBHOOK_URL=https://your-odoo-domain.com/web/hook/xxxx-xxxx-xxxx

# Flask Security (Random string)
APP_SECRET_KEY=$(python3 -c 'import secrets; print(secrets.token_hex(16))')
EOF
fi

# --- 7. ENABLE SPI HARDWARE ---
echo "🔌 Enabling SPI Interface..."
sudo raspi-config nonint do_spi 0

# --- 8. SYSTEMD SERVICES ---
echo "🖥️ Configuring System Services..."

# Backend Service
sudo bash -c "cat <<EOF > /etc/systemd/system/attendance_app.service
[Unit]
Description=Odoo NFC Backend
After=network.target

[Service]
User=conceptos
WorkingDirectory=$PROJECT_DIR
ExecStart=$PROJECT_DIR/env/bin/python $PROJECT_DIR/app.py
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF"

# Kiosk Service
sudo bash -c "cat <<EOF > /etc/systemd/system/attendance_kiosk.service
[Unit]
Description=Odoo NFC Kiosk Browser
After=attendance_app.service

[Service]
User=conceptos
Environment=DISPLAY=:0
Environment=XAUTHORITY=/home/conceptos/.Xauthority
ExecStartPre=/bin/bash -c \"sed -i 's/\\\"exited_cleanly\\\":false/\\\"exited_cleanly\\\":true/' /home/conceptos/.config/chromium/Default/Preferences || true\"
ExecStart=/usr/bin/chromium --noerrdialogs --disable-infobars --kiosk --no-first-run http://localhost:5000
Restart=always
RestartSec=10

[Install]
WantedBy=graphical.target
EOF"

sudo systemctl daemon-reload
sudo systemctl enable attendance_app.service attendance_kiosk.service

echo "-------------------------------------------------------"
echo "✅ INSTALLATION COMPLETE!"
echo "-------------------------------------------------------"
echo "1. Put your app.py and templates/index.html in: $PROJECT_DIR"
echo "2. Edit your Odoo URL in: $PROJECT_DIR/.env"
echo "3. Run: sudo systemctl restart attendance_app.service"
echo "-------------------------------------------------------"
