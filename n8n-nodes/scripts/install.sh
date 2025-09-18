#!/bin/bash

# Installation script for n8n Reminders API nodes

set -e

echo "🚀 Installing n8n Reminders API nodes..."

# Check if n8n instance path is provided
if [ -z "$1" ]; then
    echo "❌ Please provide the path to your n8n instance:"
    echo "   ./install.sh /path/to/your/n8n/instance"
    exit 1
fi

N8N_PATH="$1"

# Check if the n8n directory exists
if [ ! -d "$N8N_PATH" ]; then
    echo "❌ n8n directory not found: $N8N_PATH"
    exit 1
fi

# Check if package.json exists in n8n directory
if [ ! -f "$N8N_PATH/package.json" ]; then
    echo "❌ This doesn't appear to be an n8n instance directory (no package.json found)"
    exit 1
fi

# Build the package first
echo "🔨 Building the package..."
npm run build

# Create package tarball
echo "📦 Creating package tarball..."
npm pack

# Install in n8n instance
echo "📥 Installing in n8n instance at: $N8N_PATH"
cd "$N8N_PATH"
npm install "$(pwd)/../n8n-nodes-reminders-api-1.0.0.tgz"

echo "✅ Installation completed successfully!"
echo ""
echo "🔄 Please restart your n8n instance to load the new nodes."
echo ""
echo "📋 Next steps:"
echo "   1. Restart n8n: npm start (or your preferred method)"
echo "   2. Go to Credentials → Add Credential → Reminders API"
echo "   3. Configure your API base URL and token"
echo "   4. Start creating workflows with the new nodes!"
