@echo off
if not exist venv (
    echo Creating virtualenv...
    python -m venv venv
)

call venv\Scripts\activate.bat
pip install -r requirements.txt -q

if not exist .env (
    copy .env.example .env
    echo Created .env - add your GEMINI_API_KEY before running!
    pause
    exit /b 1
)

if not exist data mkdir data

echo Starting Jarvis backend...
uvicorn app.main:app --host 0.0.0.0 --port 8000 --reload
