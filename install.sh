#!/bin/bash

# tkal Installation Script

set -e

echo "Building tkal..."
swift build -c release

echo ""
echo "Build successful!"
echo ""
echo "The executable is located at: .build/release/tkal"
echo ""
echo "To install to your PATH, choose an option:"
echo ""
echo "Option 1: Copy to /usr/local/bin (requires sudo)"
echo "  sudo cp .build/release/tkal /usr/local/bin/"
echo ""
echo "Option 2: Copy to ~/bin (user directory)"
echo "  mkdir -p ~/bin"
echo "  cp .build/release/tkal ~/bin/"
echo "  # Make sure ~/bin is in your PATH"
echo ""
echo "Option 3: Create an alias in your shell rc file"
echo "  alias tkal='$(pwd)/.build/release/tkal'"
echo ""

read -p "Install to /usr/local/bin? (y/n) " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]
then
    sudo cp .build/release/tkal /usr/local/bin/
    echo "✓ Installed to /usr/local/bin/tkal"
    echo "You can now run 'tkal' from anywhere!"
fi
