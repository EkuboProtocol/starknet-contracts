#!/bin/bash

total=0

# Find all .cairo files in current directory and its subdirectories, excluding *_test.cairo
find . -name "*.cairo" ! -name "*_test.cairo" -print0 | while IFS= read -r -d '' file
do
    # Get the count of non-empty and non-comment lines
    count=$(grep -vc '^\s*$\|^\s*//' "$file")
    # Add the count to the total
    total=$((total + count))
    # Print the file name and count on one line
    echo "$file: $count"
done

# Print the total count
echo "Total: $total"
