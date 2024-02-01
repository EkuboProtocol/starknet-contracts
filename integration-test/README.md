# Integration tests

Must install `starknet-devnet==0.6.0`, because sequencer support is removed from the latest version.

Then, you need to download the correct version of the cairo compiler release and extract it to your `~/Downloads` folder.

The tests run in two steps for performance reasons. 

- First, do `npm run create-dump` to create a `dump.bin` file and a `addresses.json` file containing the state and addresses of all the deployed test contracts
- Then, run `npm run test:update` to start the integration tests. They can take about an hour to run.
