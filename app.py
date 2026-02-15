import time
import threading
import requests
import sys
import RPi.GPIO as GPIO
from flask import Flask, render_template
from flask_socketio import SocketIO
import os
from dotenv import load_dotenv

import board
import busio
from adafruit_pn532.i2c import PN532_I2C
import digitalio

# Load configuration from .env file
load_dotenv()

# Configuration from Environment Variables
ODOO_WEBHOOK_URL = os.getenv("ODOO_WEBHOOK_URL")
APP_SECRET_KEY = os.getenv("APP_SECRET_KEY", "default_secret_for_dev")

# Initialize Flask with the secret
app = Flask(__name__)
app.config['SECRET_KEY'] = APP_SECRET_KEY


# Get the directory where app.py is located
current_dir = os.path.dirname(os.path.abspath(__file__))

# Check if the folder exists and is visible
""" if os.path.isdir(os.path.join(current_dir, 'pn532')):
    sys.path.append(current_dir)
    print("✅ Found 'pn532' folder in local directory")
else:
    print(f"❌ Error: Could not find 'pn532' folder at {current_dir}")
    sys.exit(1)
 """
# Now try the import
""" try:
    from adafruit_pn532.i2c import PN532_I2C
except Exception as e:
    print(f"❌ Import failed: {e}")
    sys.exit(1)
 """
app = Flask(__name__)
app.config['SECRET_KEY'] = 'odoo_nfc_kiosk_2026'
socketio = SocketIO(app, cors_allowed_origins="*", async_mode='threading', logger=True, engineio_logger=True)

# Global hardware object
pn532_hw = None

def init_hardware():
    global pn532_hw
    try:
        # I2C setup
        i2c = busio.I2C(board.SCL, board.SDA)
        # On Raspberry Pi, the PN532 usually needs a reset pin, but often works without it.
        # If it fails, connect a GPIO to the RST pin and define it here.
        
        # 1. Physical Reset
        GPIO.setwarnings(False)
        GPIO.setmode(GPIO.BCM)
        pn532_hw = PN532_I2C(i2c, debug=False)
        # 2. Initialize ONCE using your working pins
        #pn532_hw = PN532_SPI(debug=False, reset=20, cs=4)
        ic, ver, rev, support = pn532_hw.get_firmware_version()
        #ic, ver, rev, support = pn532_hw.firmware_version
        print(f"✅ PN532 Detected! Firmware version: {ver}.{rev}")
        
        pn532_hw.SAM_configuration()
        return True
    except Exception as e:
        print(f"❌ Hardware Init Failed: {e}")
        return False

def trigger_odoo(card_id):
    try:
        payload = {"card_id": card_id}
        # We send the request and wait for Odoo's response
        r = requests.post(ODOO_WEBHOOK_URL, json=payload, timeout=5)
        return r.status_code == 200
    except Exception as e:
        print(f"Odoo Connection Error: {e}")
        return False

def nfc_worker():
    print("🚀 Background NFC listener started...")
    while True:
        socketio.sleep(0.1)
        try:
            # Use the global hardware object
            #uid = pn532_hw.read_passive_target(timeout=0.5)
            uid = pn532_hw.read_passive_target(timeout=0.5)
            if uid is not None:
                card_id = "".join([hex(i)[2:].upper().zfill(2) for i in uid])
                print(f"🔍 Card Scanned: {card_id}")
                
                success = trigger_odoo(card_id)
                
                # Use the global socketio object to emit
                socketio.emit('scan_result', {
                    'status': 'success' if success else 'error',
                    'card_id': card_id,
                    'msg': '' if success else f"Odoo Error: {card_id}"
                })
                socketio.sleep(2) # Cooldown
        except Exception as e:
            print(f"Loop Error: {e}")
            time.sleep(1)

@app.route('/')
def index():
    return render_template('index.html')

if __name__ == '__main__':
    try:
        if init_hardware():
            # Start background thread
            socketio.start_background_task(nfc_worker)
            socketio.run(app, host='0.0.0.0', port=5000, debug=False, allow_unsafe_werkzeug=True)
    except KeyboardInterrupt:
        print("\nStopping...")
    finally:
        GPIO.cleanup()
