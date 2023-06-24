#!/bin/sh

rm -r out
mkdir out

starknet-compile --allowed-libfuncs-list-name all . -c ekubo::core::Core out/core.json
starknet-compile --allowed-libfuncs-list-name all . -c ekubo::positions::Positions out/positions.json
starknet-compile --allowed-libfuncs-list-name all . -c ekubo::quoter::Quoter out/quoter.json
starknet-compile --allowed-libfuncs-list-name all . -c ekubo::extensions::oracle::Oracle out/oracle.json
starknet-compile --allowed-libfuncs-list-name all . -c ekubo::extensions::option_incentives::OptionIncentives out/option_incentives.json

