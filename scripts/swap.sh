#!/bin/bash

if [ $# -ne 1 ]; then
    echo "Usage: $0 filename"
    exit 1
fi

FILE="$1"
BACKUP="${FILE}.back"

if [ ! -f "$FILE" ]; then
    echo "Error: File $FILE does not exist"
    exit 1
fi

if [ ! -f "$BACKUP" ]; then
    echo "Creating $FILE.back"
    cp "$FILE" "$BACKUP"
fi

SWAP="${FILE}.swap"
if [ ! -f "$SWAP" ]; then
    echo "Creating $FILE.swap"
    cp "$FILE" "$SWAP"
fi

# Perform the swap using a temporary file
echo "Swapping $FILE with $SWAP"
TEMP="${FILE}.temp"
mv "$FILE" "$TEMP"
mv "$SWAP" "$FILE"
mv "$TEMP" "$SWAP"

echo "Swap complete"
