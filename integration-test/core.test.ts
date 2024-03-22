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
import {
  TWAMM_ACTION_SETS,
  TWAMM_ORDER_CASES,
  TWAMM_POOL_CASES,
} from "./cases/twammCases";
import { MAX_BOUNDS_TWAMM, MAX_TICK_SPACING } from "./utils/constants";

describe("core", () => {
  let setup: Awaited<ReturnType<typeof setupContracts>>;

  beforeAll(async () => {
    setup = await setupContracts({
      core: '0x572dd1ec97fff1a02d7c03af6a649a6543ca639a0452178842108a35ab85bcd',
      positions: '0x7b7066d14974e43bddf2243771d1ee94b404ce07f4257fe39021405454a9fd3',
      router: '0x2039a0b5b49e828abbf2cf98d735380298a3ff68d1135a35b58efd040be5dd2',
      nft: '0x3d48f6f6558df7a13f82bf81ec352e0100241a1718e212f898dd38cf9c5cea7',
      twamm: '0x45679fef9e4593a0f1caa0fe28dc9cbae46716ad27c7a23c94fb73474b16034',
      tokenClassHash: '0x77756dd5c3db3eb64ee050f2fa217662193b8be2838b27872fa21193948154a'
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

  describe("twamm", () => {
    for (const {
      name: twammCaseName,
      pool,
      positions_liquidities,
    } of TWAMM_POOL_CASES) {
      describe(twammCaseName, () => {
        for (const { name: orderCaseName, orders } of TWAMM_ORDER_CASES) {
          describe(orderCaseName, () => {
            for (const { name: actionSetName, actions } of TWAMM_ACTION_SETS) {
              it(
                actionSetName,
                async ({ expect }) => {
                  const {
                    account,
                    core,
                    positionsContract,
                    token0,
                    token1,
                    twamm,
                    getTxSettings,
                    nft,
                    router,
                  } = await prepareContracts(setup);

                  const poolKey = {
                    token0: token0.address,
                    token1: token1.address,
                    fee: pool.fee,
                    tick_spacing: MAX_TICK_SPACING,
                    extension: twamm.address,
                  };

                  const startingTime = 16;
                  const endingTime =
                    startingTime + actions[actions.length - 1].after;

                  const initializePoolCall = core.populate(
                    "maybe_initialize_pool",
                    [
                      poolKey,

                      // starting tick
                      toI129(pool.startingTick),
                    ]
                  );

                  const txHashes: string[] = [];
                  for (const liquidity of positions_liquidities) {
                    const bounds = MAX_BOUNDS_TWAMM;
                    const { amount0, amount1 } = getAmountsForLiquidity({
                      tick: pool.startingTick,
                      liquidity,
                      bounds,
                    });
                    await setDevnetTime(startingTime);
                    const { transaction_hash } = await account.execute(
                      [
                        initializePoolCall,
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

                  expect(
                    mintReceipts.every(
                      (receipt) => receipt.execution_status === "SUCCEEDED"
                    ),
                    `mints did not succeed: ${mintReceipts
                      .map((r) => r.revert_reason)
                      .join("; ")}`
                  ).toEqual(true);

                  const mintedPositionTokens = mintReceipts.map((receipt) => ({
                    liquidity: fromI129(
                      (
                        core
                          .parseEvents(receipt)
                          .find(({ PositionUpdated }) => PositionUpdated)
                          ?.PositionUpdated as unknown as {
                          params: {
                            liquidity_delta: { mag: bigint; sign: boolean };
                          };
                        }
                      ).params.liquidity_delta
                    ),
                    token_id: (
                      nft.parseEvents(receipt).find(({ Transfer }) => Transfer)
                        ?.Transfer as {
                        from: bigint;
                        to: bigint;
                        token_id: bigint;
                      }
                    )?.token_id,
                  }));

                  let mintedOrders: {
                    token_id: bigint;
                    order_key: {};
                    sale_rate: bigint;
                  }[] = [];

                  if (orders.length > 0) {
                    const [balance0, balance1] = await Promise.all([
                      token0.balanceOf(account.address),
                      token1.balanceOf(account.address),
                    ]);

                    await setDevnetTime(startingTime);
                    const { transaction_hash } = await account.execute(
                      [
                        initializePoolCall,
                        token0.populate("transfer", [
                          setup.positions,
                          balance0 / 2n,
                        ]),
                        token1.populate("transfer", [
                          setup.positions,
                          balance1 / 2n,
                        ]),
                        ...orders.map((order) => {
                          const [buy_token, sell_token] = order.isToken1
                            ? [poolKey.token0, poolKey.token1]
                            : [poolKey.token1, poolKey.token0];

                          return positionsContract.populate(
                            "mint_and_increase_sell_amount",
                            [
                              {
                                sell_token,
                                buy_token,
                                fee: poolKey.fee,
                                start_time:
                                  startingTime + order.relativeTimes.start,
                                end_time:
                                  startingTime + order.relativeTimes.end,
                              },
                              order.amount,
                            ]
                          );
                        }),
                      ],
                      [],
                      getTxSettings()
                    );

                    const orderPlacementReceipt =
                      await account.waitForTransaction(transaction_hash, {
                        retryInterval: 0,
                      });

                    expect(
                      orderPlacementReceipt.execution_status,
                      `order placement succeeded: ${orderPlacementReceipt.revert_reason}`
                    ).toEqual("SUCCEEDED");

                    mintedOrders = twamm
                      .parseEvents(orderPlacementReceipt)
                      .map(({ OrderUpdated }) => OrderUpdated)
                      .filter((x) => !!x)
                      .map(({ salt, order_key, sale_rate_delta }: any) => ({
                        token_id: salt,
                        order_key,
                        sale_rate: fromI129(sale_rate_delta),
                      }));
                  }

                  for (const action of actions) {
                    const { after, type } = action;

                    await setDevnetTime(startingTime + after);

                    switch (type) {
                      case "execute_virtual_orders": {
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

                        const VirtualOrdersExecuted = twamm
                          .parseEvents(executeVirtualOrdersReceipt)
                          .find(
                            ({ VirtualOrdersExecuted }) => VirtualOrdersExecuted
                          )?.VirtualOrdersExecuted;
                        // the token0 and token1 change with each run
                        if (VirtualOrdersExecuted)
                          delete VirtualOrdersExecuted["key"];

                        const Swapped = core
                          .parseEvents(executeVirtualOrdersReceipt)
                          .find(({ Swapped }) => Swapped)?.Swapped;

                        const executionResources =
                          executeVirtualOrdersReceipt.execution_resources;
                        if ("memory_holes" in executionResources) {
                          delete executionResources["memory_holes"];
                        }

                        const executedSwap = Swapped
                          ? {
                              delta: Swapped.delta,
                              liquidity_after: Swapped.liquidity_after,
                              sqrt_ratio_after: Swapped.sqrt_ratio_after,
                              tick_after: Swapped.tick_after,
                            }
                          : null;

                        expect({
                          VirtualOrdersExecuted,
                          executedSwap,
                          executionResources,
                        }).toMatchSnapshot(
                          `execute_virtual_orders after ${after} seconds`
                        );
                        break;
                      }
                      case "swap": {
                        if (positions_liquidities.length == 0) {
                          break;
                        }

                        let swap_token = action.isToken1 ? token1 : token0;

                        const { transaction_hash } = await account.execute(
                          [
                            swap_token.populate("transfer", [
                              setup.router,
                              action.amount,
                            ]),
                            router.populate("swap", [
                              {
                                pool_key: poolKey,
                                sqrt_ratio_limit: action.sqrtRatioLimit ?? 0,
                                skip_ahead: action.skipAhead ?? 0,
                              },
                              {
                                amount: toI129(action.amount),
                                token: swap_token.address,
                              },
                            ]),
                          ],
                          [],
                          getTxSettings()
                        );

                        const swap_receipt = await provider.waitForTransaction(
                          transaction_hash,
                          { retryInterval: 0 }
                        );

                        expect(
                          swap_receipt.execution_status,
                          "swap success"
                        ).toEqual("SUCCEEDED");

                        const VirtualOrdersExecuted = twamm
                          .parseEvents(swap_receipt)
                          .find(
                            ({ VirtualOrdersExecuted }) => VirtualOrdersExecuted
                          )?.VirtualOrdersExecuted;
                        // the token0 and token1 change with each run
                        if (VirtualOrdersExecuted)
                          delete VirtualOrdersExecuted["key"];

                        const Swaps = core
                          .parseEvents(swap_receipt)
                          .filter(({ Swapped }) => Swapped);

                        const executedSwaps = Swaps.map((swap) => {
                          return {
                            delta: swap.Swapped.delta,
                            liquidity_after: swap.Swapped.liquidity_after,
                            sqrt_ratio_after: swap.Swapped.sqrt_ratio_after,
                            tick_after: swap.Swapped.tick_after,
                          };
                        });

                        const executionResources =
                          swap_receipt.execution_resources;
                        if ("memory_holes" in executionResources) {
                          delete executionResources["memory_holes"];
                        }

                        expect({
                          VirtualOrdersExecuted,
                          executedSwaps,
                          executionResources,
                        }).toMatchSnapshot(`swap after ${after} seconds`);
                        break;
                      }
                      default:
                        throw new Error("Unsupported action type");
                    }
                  }

                  if (mintedPositionTokens.length > 0) {
                    await setDevnetTime(endingTime);
                    const { transaction_hash: withdrawalTransactionHash } =
                      await account.execute(
                        mintedPositionTokens.map(({ token_id, liquidity }) =>
                          positionsContract.populate("withdraw", [
                            token_id,
                            poolKey,
                            {
                              lower: toI129(MAX_BOUNDS_TWAMM.lower),
                              upper: toI129(MAX_BOUNDS_TWAMM.upper),
                            },
                            liquidity,
                            0,
                            0,
                            // collect_fees =
                            true,
                          ])
                        ),
                        [],
                        getTxSettings()
                      );

                    const {
                      execution_status: positionWithdrawalTransactionStatus,
                      revert_reason,
                    } = await account.waitForTransaction(
                      withdrawalTransactionHash
                    );
                    expect(
                      positionWithdrawalTransactionStatus,
                      `position withdrawal succeeded: ${revert_reason}`
                    ).toEqual("SUCCEEDED");
                  }

                  if (mintedOrders.length > 0) {
                    await setDevnetTime(endingTime);
                    const {
                      transaction_hash: withdrawProceedsTransactionHash,
                    } = await account.execute(
                      mintedOrders.map(({ token_id, order_key }) =>
                        positionsContract.populate(
                          "withdraw_proceeds_from_sale",
                          [token_id, order_key]
                        )
                      ),
                      [],
                      getTxSettings()
                    );

                    const withdrawProceedsReceipt =
                      await account.waitForTransaction(
                        withdrawProceedsTransactionHash
                      );

                    expect(
                      withdrawProceedsReceipt.execution_status,
                      `withdraw proceeds failed: ${withdrawProceedsReceipt.revert_reason}`
                    ).toEqual("SUCCEEDED");
                  }
                },
                300_000
              );
            }
          });
        }
      });
    }
  });
});
