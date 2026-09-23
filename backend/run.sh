#!/bin/bash
set -e

# Create venv if not exists
if [ ! -d "venv" ]; then
    echo "Creating virtualenv..."
    python3 -m venv venv
fi

source venv/bin/activate

# Install dependencies
pip install -r requirements.txt -q

# Copy env if not exists
if [ ! -f ".env" ]; then
    cp .env.example .env
    echo "⚠️  Created .env — add your GEMINI_API_KEY before running!"
    exit 1
fi

mkdir -p data

echo "🚀 Starting Jarvis backend..."
uvicorn app.main:app --host 0.0.0.0 --port 8000 --reload
