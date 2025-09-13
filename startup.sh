#!/bin/bash
chmod +x startup.sh

# startup.sh - Azure App Service startup script for PrepMyCert
# This script is executed when the Azure App Service container starts

echo "🚀 PrepMyCert Azure Startup Script"
echo "========================================"

# Set environment variables for production
export FLASK_ENV=production
export FLASK_DEBUG=False
export PYTHONPATH=/home/site/wwwroot:$PYTHONPATH

echo "📂 Working Directory: $(pwd)"
echo "🐍 Python Version: $(python3 --version)"

# Install dependencies if requirements.txt is newer than installed packages
echo "📦 Installing Python dependencies..."
if [ -f requirements.txt ]; then
    pip3 install --no-cache-dir -r requirements.txt
    if [ $? -eq 0 ]; then
        echo "✅ Dependencies installed successfully"
    else
        echo "❌ Failed to install dependencies"
        exit 1
    fi
else
    echo "❌ requirements.txt not found"
    exit 1
fi

# Wait for database to be ready (especially important for first deployment)
echo "⏳ Checking database connectivity..."
python3 -c "
import os
import psycopg2
import time

max_retries = 30
retry_count = 0

while retry_count < max_retries:
    try:
        conn = psycopg2.connect(os.environ.get('DATABASE_URL'))
        conn.close()
        print('✅ Database connection successful')
        break
    except Exception as e:
        print(f'⏳ Database not ready, attempt {retry_count + 1}/{max_retries}: {str(e)}')
        retry_count += 1
        time.sleep(2)
        
if retry_count == max_retries:
    print('❌ Could not connect to database after maximum retries')
    exit(1)
"

# Run database migrations
echo "🗄️  Running database migrations..."
if python3 migrate_database.py; then
    echo "✅ Database migrations completed successfully"
else
    echo "❌ Database migrations failed"
    exit 1
fi

# Create admin user if specified
if [ ! -z "$ADMIN_EMAIL" ] && [ ! -z "$ADMIN_PASSWORD" ]; then
    echo "👤 Setting up admin user..."
    if python3 setup_admin.py; then
        echo "✅ Admin user setup completed"
    else
        echo "⚠️  Admin user setup failed (user may already exist)"
    fi
fi

# Check if all required environment variables are set
echo "🔧 Checking environment configuration..."
required_vars=("DATABASE_URL" "SESSION_SECRET")
missing_vars=()

for var in "${required_vars[@]}"; do
    if [ -z "${!var}" ]; then
        missing_vars+=("$var")
    fi
done

if [ ${#missing_vars[@]} -ne 0 ]; then
    echo "❌ Missing required environment variables: ${missing_vars[*]}"
    exit 1
fi

echo "✅ All required environment variables are set"

# Optional variables check
optional_vars=("STRIPE_SECRET_KEY" "AZURE_STORAGE_CONNECTION_STRING" "MAIL_SERVER")
for var in "${optional_vars[@]}"; do
    if [ -z "${!var}" ]; then
        echo "⚠️  Optional environment variable not set: $var"
    else
        echo "✅ $var is configured"
    fi
done

# Set Gunicorn configuration
export GUNICORN_CMD_ARGS="--bind=0.0.0.0:8000 --timeout=600 --workers=4 --worker-class=sync --max-requests=1000 --max-requests-jitter=50 --access-logfile=- --error-logfile=-"

echo "🌐 Starting Gunicorn server..."
echo "   Workers: 4"
echo "   Timeout: 600 seconds"
echo "   Binding: 0.0.0.0:8000"
echo "========================================"

# Start the application with Gunicorn
# The main:app refers to the app object in main.py
exec gunicorn main:app \
  --bind=0.0.0.0:8000 \
  --timeout=600 \
  --workers=4 \
  --worker-class=sync \
  --max-requests=1000 \
  --max-requests-jitter=50 \
  --preload \
  --access-logfile=- \
  --error-logfile=- \
  --log-level=info \
  --capture-output \
  --enable-stdio-inheritance
