import { BlockTag, Call } from "starknet";
import { POOL_CASES } from "./cases/poolCases";
import { SWAP_CASES } from "./cases/swapCases";
import { getAmountsForLiquidity } from "./utils/liquidityMath";
import { prepareContracts, setupContracts } from "./utils/setupContracts";
import { fromI129, i129, toI129 } from "./utils/serialize";
import { provider, setDevnetTime } from "./utils/provider";
import { computeFee } from "./utils/computeFee";
import { beforeAll, describe, it } from "vitest";
import { formatPrice } from "./utils/formatPrice";
import { TWAMM_POOL_CASES, TWAMM_SWAP_CASES } from "./cases/twammCases";
import { MAX_BOUNDS_TWAMM, MAX_TICK_SPACING } from "./utils/constants";

describe("core", () => {
  let setup: Awaited<ReturnType<typeof setupContracts>>;

  beforeAll(async () => {
    setup = await setupContracts({
      core: "0x7bebe73b57806307db657aa0bc94a482c8489b9dd5abca1048c9f39828e6907",
      positions:
        "0x11d0b4ccfaadd8d817909be9dd7a0ee40a04c6a1a0aaeb0b6c199e1e0011b30",
      router:
        "0x28078e4b34563d7259c79b86378568b30660e30b1e9def79b845a32eed7ea7e",
      nft: "0x3b3caf33631251cb60863d28b7dd36c2a5922396b90d2da77cb2ec855077fd5",
      twamm:
        "0x5d03a26cb527275e9ee635a668c65e25a363ca4b7aee64e1d54db4c29560bf3",
      tokenClassHash:
        "0x645bbd4bf9fb2bd4ad4dd44a0a97fa36cce3f848ab715ddb82a093337c1e42e",
    });
    console.log(setup);
  }, 300_000);

  describe("regular pool", () => {
    for (const { name: poolCaseName, pool, positions } of POOL_CASES) {
      describe.concurrent(poolCaseName, () => {
        for (const swapCase of SWAP_CASES) {
          it(`swap ${swapCase.amount} ${
            swapCase.isToken1 ? "token1" : "token0"
          }${swapCase.skipAhead ? ` skip ${swapCase.skipAhead}` : ""}${
            swapCase.sqrtRatioLimit
              ? ` limit ${formatPrice(swapCase.sqrtRatioLimit)}`
              : ""
          }`, async ({ expect }) => {
            const {
              nft,
              account,
              token1,
              token0,
              router,
              positionsContract,
              core,
              getTxSettings,
            } = await prepareContracts(setup);

            const poolKey = {
              token0: token0.address,
              token1: token1.address,
              fee: pool.fee,
              tick_spacing: pool.tickSpacing,
              extension: "0x0",
            };

            const txHashes: string[] = [];
            for (const { liquidity, bounds } of positions) {
              const { amount0, amount1 } = getAmountsForLiquidity({
                tick: pool.startingTick,
                liquidity,
                bounds,
              });
              const { transaction_hash } = await account.execute(
                [
                  core.populate("maybe_initialize_pool", [
                    poolKey,

                    // starting tick
                    toI129(pool.startingTick),
                  ]),
                  token0.populate("transfer", [setup.positions, amount0]),
                  token1.populate("transfer", [setup.positions, amount1]),
                  positionsContract.populate(
                    "mint_and_deposit_and_clear_both",
                    [
                      poolKey,
                      {
                        lower: toI129(bounds.lower),
                        upper: toI129(bounds.upper),
                      },
                      liquidity,
                    ]
                  ),
                ],
                [],
                getTxSettings()
              );

              txHashes.push(transaction_hash);
            }

            const mintReceipts = await Promise.all(
              txHashes.map((txHash) =>
                provider.waitForTransaction(txHash, {
                  retryInterval: 0,
                })
              )
            );

            const positionsMinted: { token_id: bigint; liquidity: bigint }[] =
              mintReceipts.map((receipt) => {
                const { Transfer } = nft
                  .parseEvents(receipt)
                  .find(({ Transfer }) => Transfer);

                const { PositionUpdated } = core
                  .parseEvents(receipt)
                  .find(({ PositionUpdated }) => PositionUpdated);

                return {
                  token_id: (Transfer as unknown as { token_id: bigint })
                    .token_id,
                  liquidity: (
                    PositionUpdated as unknown as {
                      params: {
                        liquidity_delta: { mag: bigint; sign: boolean };
                      };
                    }
                  ).params.liquidity_delta.mag,
                };
              });

            const [remaining0, remaining1] = await Promise.all([
              token0.call("balanceOf", [account.address]),
              token1.call("balanceOf", [account.address]),
            ]);
            // transfer remaining balances to router
            await account.execute(
              [
                token0.populate("transfer", [setup.router, remaining0]),
                token1.populate("transfer", [setup.router, remaining1]),
              ],
              [],
              getTxSettings()
            );

            let transaction_hash: string;
            try {
              ({ transaction_hash } = await router.invoke(
                "swap",
                [
                  {
                    pool_key: poolKey,
                    sqrt_ratio_limit: swapCase.sqrtRatioLimit ?? 0,
                    skip_ahead: swapCase.skipAhead ?? 0,
                  },
                  {
                    amount: toI129(swapCase.amount),
                    token: swapCase.isToken1 ? token1.address : token0.address,
                  },
                ],
                getTxSettings()
              ));
            } catch (error) {
              transaction_hash = error.transaction_hash;
              if (!transaction_hash) throw error;
            }

            const swap_receipt = await provider.waitForTransaction(
              transaction_hash,
              { retryInterval: 0 }
            );

            switch (swap_receipt.execution_status) {
              case "REVERTED": {
                const revertReason = swap_receipt.revert_reason;

                const hexErrorMessage =
                  /Failure reason: 0x([a-fA-F0-9]+)/g.exec(revertReason)?.[1];

                expect({
                  revert_reason: hexErrorMessage
                    ? Buffer.from(hexErrorMessage, "hex").toString("ascii")
                    : /(RunResources has no remaining steps)/g.exec(
                        revertReason
                      )?.[1] ?? revertReason,
                }).toMatchSnapshot();
                break;
              }
              case "SUCCEEDED": {
                const execution_resources = swap_receipt.execution_resources;
                if ("memory_holes" in execution_resources) {
                  delete execution_resources["memory_holes"];
                }

                const { sqrt_ratio_after, tick_after, liquidity_after, delta } =
                  core.parseEvents(swap_receipt)[0].Swapped;

                const { amount0, amount1 } = delta as unknown as {
                  amount0: i129;
                  amount1: i129;
                };

                expect({
                  execution_resources,
                  delta: {
                    amount0: fromI129(amount0),
                    amount1: fromI129(amount1),
                  },
                  liquidity_after,
                  sqrt_ratio_after,
                  tick_after: fromI129(tick_after as unknown as i129),
                }).toMatchSnapshot();
                break;
              }
            }

            let cumulativeProtocolFee0 = 0n;
            let cumulativeProtocolFee1 = 0n;

            const withdrawalCalls: Call[] = [];
            for (let i = 0; i < positions.length; i++) {
              const { bounds } = positions[i];

              const boundsArgument = {
                lower: toI129(bounds.lower),
                upper: toI129(bounds.upper),
              };

              const { liquidity: expectedLiquidity, token_id } =
                positionsMinted[i];

              const { liquidity, amount0, amount1 } =
                (await positionsContract.call(
                  "get_token_info",
                  [token_id, poolKey, boundsArgument],
                  { blockIdentifier: BlockTag.pending }
                )) as unknown as {
                  liquidity: bigint;
                  amount0: bigint;
                  amount1: bigint;
                  fees0: bigint;
                  fees1: bigint;
                };

              expect(liquidity).toEqual(expectedLiquidity);

              cumulativeProtocolFee0 += computeFee(amount0, poolKey.fee);
              cumulativeProtocolFee1 += computeFee(amount1, poolKey.fee);

              withdrawalCalls.push(
                positionsContract.populate("withdraw", [
                  token_id,
                  poolKey,
                  boundsArgument,
                  liquidity,
                  0,
                  0,
                  // collect_fees =
                  true,
                ])
              );
            }

            // wait for all the withdrawals to be mined
            await account.execute(withdrawalCalls, [], getTxSettings());

            const [protocolFee0, protocolFee1, balance0, balance1] =
              await Promise.all([
                core.call("get_protocol_fees_collected", [token0.address]),
                core.call("get_protocol_fees_collected", [token1.address]),

                token0.call("balanceOf", [setup.core]),
                token1.call("balanceOf", [setup.core]),
              ]);

            expect(protocolFee0).toEqual(cumulativeProtocolFee0);
            expect(protocolFee1).toEqual(cumulativeProtocolFee1);

            // assuming up to 1 wei of rounding error per swap / withdrawal
            expect(balance0).toBeGreaterThanOrEqual(cumulativeProtocolFee0);
            expect(balance1).toBeGreaterThanOrEqual(cumulativeProtocolFee1);

            // extra is just to account for rounding error for position mints and withdraws as well as swaps (each iteration causes rounding error)
            expect(balance0).toBeLessThanOrEqual(cumulativeProtocolFee0 + 200n);
            expect(balance1).toBeLessThanOrEqual(cumulativeProtocolFee1 + 200n);
          }, 300_000);
        }
      });
    }
  });

  describe.only("twamm", () => {
    for (const {
      name: twammCaseName,
      pool,
      positions_liquidities,
    } of TWAMM_POOL_CASES) {
      describe(twammCaseName, () => {
        for (const { name, orders, snapshot_times } of TWAMM_SWAP_CASES) {
          it(
            name,
            async ({ expect }) => {
              const {
                account,
                core,
                positionsContract,
                token0,
                token1,
                twamm,
                getTxSettings,
              } = await prepareContracts(setup);

              const poolKey = {
                token0: token0.address,
                token1: token1.address,
                fee: pool.fee,
                tick_spacing: MAX_TICK_SPACING,
                extension: twamm.address,
              };

              const txHashes: string[] = [];
              for (const liquidity of positions_liquidities) {
                const bounds = MAX_BOUNDS_TWAMM;
                const { amount0, amount1 } = getAmountsForLiquidity({
                  tick: pool.startingTick,
                  liquidity,
                  bounds,
                });
                const { transaction_hash } = await account.execute(
                  [
                    core.populate("maybe_initialize_pool", [
                      poolKey,

                      // starting tick
                      toI129(pool.startingTick),
                    ]),
                    token0.populate("transfer", [setup.positions, amount0]),
                    token1.populate("transfer", [setup.positions, amount1]),
                    positionsContract.populate(
                      "mint_and_deposit_and_clear_both",
                      [
                        poolKey,
                        {
                          lower: toI129(bounds.lower),
                          upper: toI129(bounds.upper),
                        },
                        liquidity,
                      ]
                    ),
                  ],
                  [],
                  getTxSettings()
                );

                txHashes.push(transaction_hash);
              }

              await Promise.all(
                txHashes.map((txHash) =>
                  provider.waitForTransaction(txHash, {
                    retryInterval: 0,
                  })
                )
              );

              const startingTime = 16; // (await provider.getBlock("pending")).timestamp;
              await setDevnetTime(startingTime);

              if (orders.length > 0) {
                const [balance0, balance1] = await Promise.all([
                  token0.balanceOf(account.address),
                  token1.balanceOf(account.address),
                ]);

                const { transaction_hash } = await account.execute(
                  [
                    token0.populate("transfer", [setup.positions, balance0]),
                    token1.populate("transfer", [setup.positions, balance1]),
                    ...orders.map((order) => {
                      const [buy_token, sell_token] = order.is_token1
                        ? [poolKey.token0, poolKey.token1]
                        : [poolKey.token1, poolKey.token0];
                      return positionsContract.populate(
                        "mint_and_increase_amount",
                        [
                          {
                            sell_token,
                            buy_token,
                            fee: poolKey.fee,
                            start_time:
                              startingTime + order.relative_times.start,
                            end_time: startingTime + order.relative_times.end,
                          },
                          order.amount,
                        ]
                      );
                    }),
                  ],
                  [],
                  getTxSettings()
                );

                const orderPlacementReceipt = await account.waitForTransaction(
                  transaction_hash,
                  { retryInterval: 0 }
                );

                const orderUpdatedEvents = twamm
                  .parseEvents(orderPlacementReceipt)
                  .map(({ OrderUpdated }) => OrderUpdated)
                  .filter((x) => !!x);

                console.log(orderUpdatedEvents);
              }

              for (const snapshotTime of snapshot_times) {
                await setDevnetTime(startingTime + snapshotTime);

                const { transaction_hash } = await account.execute(
                  [
                    twamm.populate("execute_virtual_orders", [
                      {
                        token0: poolKey.token0,
                        token1: poolKey.token1,
                        fee: poolKey.fee,
                      },
                    ]),
                  ],
                  [],
                  getTxSettings()
                );

                const executeVirtualOrdersReceipt =
                  await account.waitForTransaction(transaction_hash, {
                    retryInterval: 0,
                  });

                console.log(
                  "timestamp",
                  (
                    await provider.getBlock(
                      executeVirtualOrdersReceipt.block_number
                    )
                  ).timestamp
                );

                console.log(executeVirtualOrdersReceipt);

                const twammEvents = twamm.parseEvents(
                  executeVirtualOrdersReceipt
                );
                const coreEvents = core.parseEvents(
                  executeVirtualOrdersReceipt
                );
                expect({ twammEvents, coreEvents }).toMatchSnapshot();
              }
            },
            300_000
          );
        }
      });
    }
  });
});
