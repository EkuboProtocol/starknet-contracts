#!/bin/sh
wc -l `find . -name "*.cairo" ! -name "*_test.cairo" ! -path "./src/tests/*" ! -name "tests.cairo"`