#!/bin/bash

total=0

find . -name "*.cairo" ! -name "*_test.cairo" -print0 | while IFS= read -r -d '' file
do
    count=$(grep -vc '^\s*$\|^\s*//' "$file")
    total=$((total + count))
    echo "$file: $count"
done

echo "Total: $total"
