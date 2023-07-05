#!/bin/sh

rm -r out
mkdir out

starknet-compile --allowed-libfuncs-list-name audited . -c ekubo::core::Core out/core.json
starknet-sierra-compile --allowed-libfuncs-list-name audited out/core.json out/core.casm.json

starknet-compile --allowed-libfuncs-list-name audited . -c ekubo::positions::Positions out/positions.json
starknet-sierra-compile --allowed-libfuncs-list-name audited out/positions.json out/positions.casm.json

starknet-compile --allowed-libfuncs-list-name audited . -c ekubo::quoter::Quoter out/quoter.json
starknet-sierra-compile --allowed-libfuncs-list-name audited out/quoter.json out/quoter.casm.json

starknet-compile --allowed-libfuncs-list-name audited . -c ekubo::extensions::oracle::Oracle out/oracle.json
starknet-sierra-compile --allowed-libfuncs-list-name audited out/oracle.json out/oracle.casm.json

starknet-compile --allowed-libfuncs-list-name audited . -c ekubo::option_incentives::OptionIncentives out/option_incentives.json
starknet-sierra-compile --allowed-libfuncs-list-name audited out/option_incentives.json out/option_incentives.casm.json
