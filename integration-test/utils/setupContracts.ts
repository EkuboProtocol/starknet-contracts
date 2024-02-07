import { Account, Contract, num, shortString } from "starknet";
import MockERC20 from "../../target/dev/ekubo_MockERC20.contract_class.json";
import MockERC20CASM from "../../target/dev/ekubo_MockERC20.compiled_contract_class.json";
import CoreCompiledContract from "../../target/dev/ekubo_Core.contract_class.json";
import CoreCompiledContractCASM from "../../target/dev/ekubo_Core.compiled_contract_class.json";
import OwnedNFTContract from "../../target/dev/ekubo_OwnedNFT.contract_class.json";
import OwnedNFTContractCASM from "../../target/dev/ekubo_OwnedNFT.compiled_contract_class.json";
import PositionsCompiledContract from "../../target/dev/ekubo_Positions.contract_class.json";
import PositionsCompiledContractCASM from "../../target/dev/ekubo_Positions.compiled_contract_class.json";
import Router from "../../target/dev/ekubo_Router.contract_class.json";
import RouterCASM from "../../target/dev/ekubo_Router.compiled_contract_class.json";
import { provider } from "./provider";

export async function setupContracts(expected?: {
  core: string;
  positions: string;
  router: string;
  nft: string;
  tokenClassHash: string;
}) {
  if (expected) {
    try {
      const [ch0, ch1, ch2, ch3, c] = await Promise.all([
        provider.getClassHashAt(expected.core),
        provider.getClassHashAt(expected.positions),
        provider.getClassHashAt(expected.router),
        provider.getClassHashAt(expected.nft),
        provider.getClass(expected.tokenClassHash),
      ]);
      if (ch0 && ch1 && ch2 && ch3 && c) return expected;
    } catch (error) {}
  }

  // starknet-devnet-rs with seed 0
  const deployer = new Account(
    provider,
    "0x64b48806902a367c8598f4f95c305e8c1a1acba5f082d294a43793113115691",
    "0x71d7bb07b9a64f6f78ac4c816aff4da9"
  );

  const simpleTokenContractDeclare = await deployer.declareIfNot({
    contract: MockERC20 as any,
    casm: MockERC20CASM as any,
  });
  const coreContractDeclare = await deployer.declareIfNot({
    contract: CoreCompiledContract as any,
    casm: CoreCompiledContractCASM as any,
  });
  const declareNftResponse = await deployer.declareIfNot({
    contract: OwnedNFTContract as any,
    casm: OwnedNFTContractCASM as any,
  });
  const positionsDeclare = await deployer.declareIfNot({
    contract: PositionsCompiledContract as any,
    casm: PositionsCompiledContractCASM as any,
  });
  const routerDeclare = await deployer.declareIfNot({
    contract: Router as any,
    casm: RouterCASM as any,
  });

  const coreDeploy = await deployer.deploy({
    classHash: coreContractDeclare.class_hash,
    constructorCalldata: [deployer.address],
    salt: "0x0",
  });

  const positionsConstructorCalldata = [
    deployer.address,
    coreDeploy.contract_address[0],
    declareNftResponse.class_hash,
    shortString.encodeShortString("https://f.ekubo.org/"),
  ];

  const positionsDeploy = await deployer.deploy({
    classHash: positionsDeclare.class_hash,
    constructorCalldata: positionsConstructorCalldata,
    salt: "0x1",
  });

  const positions = new Contract(
    PositionsCompiledContract.abi,
    positionsDeploy.contract_address[0],
    deployer
  );

  const routerDeploy = await deployer.deploy({
    classHash: routerDeclare.class_hash,
    constructorCalldata: [coreDeploy.contract_address[0]],
    salt: "0x2",
  });

  const nftAddress = (await positions.call("get_nft_address")) as bigint;

  return {
    core: coreDeploy.contract_address[0],
    positions: positionsDeploy.contract_address[0],
    router: routerDeploy.contract_address[0],
    nft: num.toHexString(nftAddress),
    tokenClassHash: simpleTokenContractDeclare.class_hash,
  };
}
