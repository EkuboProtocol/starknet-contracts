import { Account, Contract, num, shortString } from "starknet";
import MockERC20 from "../../target/dev/ekubo_MockERC20.contract_class.json";
import MockERC20Contract from "../../target/dev/ekubo_MockERC20.contract_class.json";
import MockERC20CASM from "../../target/dev/ekubo_MockERC20.compiled_contract_class.json";
import CoreCompiledContract from "../../target/dev/ekubo_Core.contract_class.json";
import CoreContract from "../../target/dev/ekubo_Core.contract_class.json";
import CoreCompiledContractCASM from "../../target/dev/ekubo_Core.compiled_contract_class.json";
import OwnedNFTContract from "../../target/dev/ekubo_OwnedNFT.contract_class.json";
import OwnedNFTContractCASM from "../../target/dev/ekubo_OwnedNFT.compiled_contract_class.json";
import PositionsCompiledContract from "../../target/dev/ekubo_Positions.contract_class.json";
import PositionsContract from "../../target/dev/ekubo_Positions.contract_class.json";
import PositionsCompiledContractCASM from "../../target/dev/ekubo_Positions.compiled_contract_class.json";
import TWAMMCompiledContract from "../../target/dev/ekubo_TWAMM.contract_class.json";
import TWAMMCompiledContractCASM from "../../target/dev/ekubo_TWAMM.compiled_contract_class.json";
import Router from "../../target/dev/ekubo_Router.contract_class.json";
import RouterContract from "../../target/dev/ekubo_Router.contract_class.json";
import RouterCASM from "../../target/dev/ekubo_Router.compiled_contract_class.json";
import { createAccount, provider } from "./provider";
import { getNextTransactionSettingsFunction } from "./getNextTransactionSettingsFunction";
import { deployTokens } from "./deployTokens";

export async function setupContracts(expected?: {
  core: string;
  positions: string;
  router: string;
  nft: string;
  twamm: string;
  tokenClassHash: string;
}) {
  if (expected) {
    try {
      const [ch0, ch1, ch2, ch3, ch4, c] = await Promise.all([
        provider.getClassHashAt(expected.core),
        provider.getClassHashAt(expected.positions),
        provider.getClassHashAt(expected.router),
        provider.getClassHashAt(expected.nft),
        provider.getClassHashAt(expected.twamm),
        provider.getClass(expected.tokenClassHash),
      ]);
      if (ch0 && ch1 && ch2 && ch3 && ch4 && c) return expected;
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
  const twammDeclare = await deployer.declareIfNot({
    contract: TWAMMCompiledContract as any,
    casm: TWAMMCompiledContractCASM as any,
  });

  const {
    contract_address: [coreAddress],
  } = await deployer.deploy({
    classHash: coreContractDeclare.class_hash,
    constructorCalldata: [deployer.address],
    salt: "0x0",
  });

  const positionsConstructorCalldata = [
    deployer.address,
    coreAddress,
    declareNftResponse.class_hash,
    shortString.encodeShortString("https://f.ekubo.org/"),
  ];

  const {
    contract_address: [positionsAddress, routerAddress, twammAddress],
  } = await deployer.deploy([
    {
      classHash: positionsDeclare.class_hash,
      constructorCalldata: positionsConstructorCalldata,
      salt: "0x1",
    },
    {
      classHash: routerDeclare.class_hash,
      constructorCalldata: [coreAddress],
      salt: "0x2",
    },
    {
      classHash: twammDeclare.class_hash,
      constructorCalldata: [deployer.address, coreAddress],
      salt: "0x3",
    },
  ]);

  const positions = new Contract(
    PositionsCompiledContract.abi,
    positionsAddress,
    deployer
  );

  await positions.invoke("set_twamm", [twammAddress]);

  const nftAddress = (await positions.call("get_nft_address")) as bigint;

  return {
    core: coreAddress,
    positions: positionsAddress,
    router: routerAddress,
    nft: num.toHexString(nftAddress),
    twamm: twammAddress,
    tokenClassHash: simpleTokenContractDeclare.class_hash,
  };
}

export async function prepareContracts(
  setup: Awaited<ReturnType<typeof setupContracts>>
) {
  const account = await createAccount();
  const getTxSettings = await getNextTransactionSettingsFunction(
    account,
    "0x1"
  );

  const core = new Contract(CoreContract.abi, setup.core, account);
  const nft = new Contract(OwnedNFTContract.abi, setup.nft, account);
  const positionsContract = new Contract(
    PositionsContract.abi,
    setup.positions,
    account
  );
  const router = new Contract(RouterContract.abi, setup.router, account);
  const twamm = new Contract(TWAMMCompiledContract.abi, setup.twamm, account);

  const [token0Address, token1Address] = await deployTokens({
    deployer: account,
    classHash: setup.tokenClassHash,
    getTxSettings,
  });

  const token0 = new Contract(MockERC20Contract.abi, token0Address, account);
  const token1 = new Contract(MockERC20Contract.abi, token1Address, account);

  return {
    account,
    core,
    twamm,
    nft,
    positionsContract,
    router,
    token0,
    token1,
    getTxSettings,
  };
}
