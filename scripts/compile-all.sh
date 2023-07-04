#!/bin/sh

rm -r out
mkdir out

starknet-compile --allowed-libfuncs-list-name all . -c ekubo::core::Core out/core.json
starknet-sierra-compile --allowed-libfuncs-list-name all out/core.json out/core.casm.json

starknet-compile --allowed-libfuncs-list-name all . -c ekubo::positions::Positions out/positions.json
starknet-sierra-compile --allowed-libfuncs-list-name all out/positions.json out/positions.casm.json

starknet-compile --allowed-libfuncs-list-name all . -c ekubo::quoter::Quoter out/quoter.json
starknet-sierra-compile --allowed-libfuncs-list-name all out/quoter.json out/quoter.casm.json

starknet-compile --allowed-libfuncs-list-name all . -c ekubo::extensions::oracle::Oracle out/oracle.json
starknet-sierra-compile --allowed-libfuncs-list-name all out/oracle.json out/oracle.casm.json

starknet-compile --allowed-libfuncs-list-name all . -c ekubo::option_incentives::OptionIncentives out/option_incentives.json
starknet-sierra-compile --allowed-libfuncs-list-name all out/option_incentives.json out/option_incentives.casm.json
