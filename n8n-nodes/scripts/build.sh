#!/bin/bash

# Build script for n8n Reminders API nodes

set -e

echo "🔨 Building n8n Reminders API nodes..."

# Check if Node.js is installed
if ! command -v node &> /dev/null; then
    echo "❌ Node.js is not installed. Please install Node.js first."
    exit 1
fi

# Check if npm is installed
if ! command -v npm &> /dev/null; then
    echo "❌ npm is not installed. Please install npm first."
    exit 1
fi

# Install dependencies
echo "📦 Installing dependencies..."
npm install

# Run linting
echo "🔍 Running linter..."
npm run lint

# Build the package
echo "🏗️  Building TypeScript..."
npm run build

# Create package tarball
echo "📦 Creating package tarball..."
npm pack

echo "✅ Build completed successfully!"
echo ""
echo "📁 Files created:"
echo "   - dist/ (compiled JavaScript)"
echo "   - n8n-nodes-reminders-api-1.0.0.tgz (package tarball)"
echo ""
echo "🚀 Next steps:"
echo "   1. Install in your n8n instance:"
echo "      npm install ./n8n-nodes-reminders-api-1.0.0.tgz"
echo "   2. Or copy the dist/ folder to your n8n nodes directory"
echo "   3. Restart your n8n instance"
