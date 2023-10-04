import { Contract } from "starknet";
import CoreCompiledContract from "../target/dev/ekubo_Core.contract_class.json";
import CoreCompiledContractCASM from "../target/dev/ekubo_Core.compiled_contract_class.json";
import PositionsCompiledContract from "../target/dev/ekubo_Positions.contract_class.json";
import PositionsCompiledContractCASM from "../target/dev/ekubo_Positions.compiled_contract_class.json";
import EnumerableOwnedNFTContract from "../target/dev/ekubo_EnumerableOwnedNFT.contract_class.json";
import EnumerableOwnedNFTContractCASM from "../target/dev/ekubo_EnumerableOwnedNFT.compiled_contract_class.json";
import SimpleERC20 from "../target/dev/ekubo_SimpleERC20.contract_class.json";
import SimpleERC20CASM from "../target/dev/ekubo_SimpleERC20.compiled_contract_class.json";
import SimpleSwapper from "../target/dev/ekubo_SimpleSwapper.contract_class.json";
import SimpleSwapperCASM from "../target/dev/ekubo_SimpleSwapper.compiled_contract_class.json";
import { DevnetProvider } from "./devnet";
import { writeFileSync } from "fs";
import { getAccounts } from "./accounts";

(async function () {
  const provider = new DevnetProvider();
  const accounts = getAccounts(provider);

  console.log("Deploying tokens");
  const simpleTokenContractDeclare = await accounts[0].declare(
    {
      contract: SimpleERC20 as any,
      casm: SimpleERC20CASM as any,
    },
    { maxFee: 10000000000000 } // workaround
  );

  const {
    contract_address: [tokenAddressA],
  } = await accounts[0].deploy({
    classHash: simpleTokenContractDeclare.class_hash,
    constructorCalldata: [accounts[0].address],
  });

  const {
    contract_address: [tokenAddressB],
  } = await accounts[0].deploy({
    classHash: simpleTokenContractDeclare.class_hash,
    constructorCalldata: [accounts[0].address],
  });

  const [token0, token1] =
    BigInt(tokenAddressA) < BigInt(tokenAddressB)
      ? [tokenAddressA, tokenAddressB]
      : [tokenAddressB, tokenAddressA];

  console.log("Deploying core");
  const coreResponse = await accounts[0].declareAndDeploy(
    {
      contract: CoreCompiledContract as any,
      casm: CoreCompiledContractCASM as any,
    },
    { maxFee: 10000000000000 } // workaround
  );

  console.log("Declaring NFTs");

  const declareNftResponse = await accounts[0].declare(
    {
      contract: EnumerableOwnedNFTContract as any,
      casm: EnumerableOwnedNFTContractCASM as any,
    },
    { maxFee: 10000000000000 } // workaround
  );

  const positionsConstructorCalldata = [
    coreResponse.deploy.address,
    declareNftResponse.class_hash,
    `0x${Buffer.from("https://f.ekubo.org/", "ascii").toString("hex")}`,
  ];

  console.log("Deploying positions");

  const positionsResponse = await accounts[0].declareAndDeploy(
    {
      contract: PositionsCompiledContract as any,
      casm: PositionsCompiledContractCASM as any,
      constructorCalldata: positionsConstructorCalldata,
    },
    { maxFee: 10000000000000 } // workaround
  );

  const positions = new Contract(
    PositionsCompiledContract.abi,
    positionsResponse.deploy.address,
    accounts[0]
  );

  const nftAddress = (await positions.call("get_nft_address")) as bigint;

  console.log("Deploying swapper");

  const swapperResponse = await accounts[0].declareAndDeploy(
    {
      contract: SimpleSwapper as any,
      casm: SimpleSwapperCASM as any,
      constructorCalldata: [coreResponse.deploy.address],
    },
    { maxFee: 10000000000000 } // workaround
  );

  await provider.dumpState();

  const addresses = {
    token0,
    token1,
    core: coreResponse.deploy.address,
    positions: positions.address,
    swapper: swapperResponse.deploy.address,
    nft: `0x${nftAddress.toString(16)}`,
  };

  writeFileSync("./addresses.json", JSON.stringify(addresses));

  console.log("Saved deployment state", addresses);
})();
