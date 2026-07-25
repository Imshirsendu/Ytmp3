# 🎵 Ytmp3 - Installation & Setup Guide

Welcome to **Ytmp3**, a personal music player using YouTube as its engine. This guide will help you set up and run both the Python backend and the Flutter frontend on your local machine.

---

## 📋 Prerequisites
Before getting started, make sure you have the following installed:
- [Python 3.10+](https://python.org)
- [Flutter SDK](https://flutter.dev)
- [Git](https://git-scm.com)

---

## 🛠️ Step 1: Clone the Repository
Open your terminal or command prompt and clone this project:
```bash
git clone https://github.com
cd Ytmp3
```

---

## 🐍 Step 2: Backend Setup (Python Server)
The backend manages the YouTube media scraping and extraction logic using `yt-dlp`. 

1. Navigate to the backend directory:
   ```bash
   cd backend
   ```
2. Create a clean local Python virtual environment:
   ```bash
   python -m venv .venv
   ```
3. Activate the virtual environment:
   - **Windows (PowerShell):** `.\.venv\Scripts\activate`
   - **Windows (CMD):** `.\.venv\Scripts\activate.bat`
   - **Mac/Linux:** `source .venv/bin/activate`
4. Install all required dependencies from the blueprint:
   ```bash
   pip install -r requirements.txt
   ```
5. Start your backend server:
   ```bash
   python main.py
   ```
   *(Note: Change `main.py` to your actual backend entry script name if it is named differently, like `app.py`)*

---

## 📱 Step 3: Frontend Setup (Flutter Application)
The frontend serves as the visual app interface, offering ad-free streaming and offline downloading capabilities.

1. Open a new terminal tab or window and navigate to the frontend directory:
   ```bash
   cd ../frontend
   ```
2. Fetch all required Flutter and Dart packages:
   ```bash
   flutter pub get
   ```
3. Run the application on your connected device or emulator:
   ```bash
   flutter run
   ```
(you will need to enable developers mode on the device you tend to install this app on --adb platform tools required --if flutter run doesnt work explicitly mentin device name --to fetch device name type flutter devices ,then get the device name and run command as flutter run -d YourDevicename)
---

## ⚠️ Troubleshooting
- **Virtual Environment Permissions (Windows):** If your terminal blocks you from activating the `.venv`, run PowerShell as Administrator and execute: `Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope Process`.
- **Backend Connection:** Ensure your local Flutter configuration points to the correct backend server port (usually `http://localhost:5000` or `8000`).
