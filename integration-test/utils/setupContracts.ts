import { Contract, num, shortString } from "starknet";
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
import { createAccount } from "./provider";

export async function setupContracts() {
  const deployer = await createAccount();

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
  });

  const positions = new Contract(
    PositionsCompiledContract.abi,
    positionsDeploy.contract_address[0],
    deployer
  );

  const routerDeploy = await deployer.deploy({
    classHash: routerDeclare.class_hash,
    constructorCalldata: [coreDeploy.contract_address[0]],
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
