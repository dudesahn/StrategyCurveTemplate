from brownie import Contract
from eth_abi import encode_abi


def test_simple_harvest(
    gov,
    token,
    vault,
    strategist,
    whale,
    strategy,
    chain,
    strategist_ms,
    gauge,
    amount,
    trade_factory,
    ymechanic,
):
    ## deposit to the vault after approving
    startingWhale = token.balanceOf(whale)
    token.approve(vault, 2 ** 256 - 1, {"from": whale})
    vault.deposit(amount, {"from": whale})
    newWhale = token.balanceOf(whale)

    strategy.harvest({"from": gov})

    old_assets = vault.totalAssets()
    assert old_assets > 0
    assert token.balanceOf(strategy) == 0
    assert strategy.estimatedTotalAssets() > 0
    print("\nStarting Assets: ", old_assets / 1e18)

    # simulate 1 day of earnings
    chain.sleep(86400)
    chain.mine(1)

    # harvest to create ySwap trades
    strategy.harvest({"from": gov})

    # Execute the yswap trades
    print(f"Executing trades...")
    for id in trade_factory.pendingTradesIds(strategy):
        trade = trade_factory.pendingTradesById(id).dict()
        token_in = trade["_tokenIn"]
        token_out = trade["_tokenOut"]
        print(f"Executing trade {id}, tokenIn: {token_in} -> tokenOut {token_out}")

        path = []
        if token_in == strategy.wftm():
            path = [strategy.wftm(), strategy.dai()]
        else:
            path = [strategy.crv(), strategy.wftm(), strategy.dai()]

        trade_data = encode_abi(["address[]"], [path])
        trade_factory.execute["uint256, bytes"](id, trade_data, {"from": ymechanic})

    dai = Contract(strategy.dai())
    assert dai.balanceOf(strategy) > 0

    # We should have dai to deposit
    strategy.harvest({"from": gov})
    assert dai.balanceOf(strategy) == 0

    new_assets = vault.totalAssets()
    # confirm we made money, or at least that we have about the same
    assert new_assets >= old_assets
    print("\nAssets after 1 day: ", new_assets / 1e18)

    # Display estimated APR
    print(
        "\nEstimated DAI APR: ",
        "{:.2%}".format(
            ((new_assets - old_assets) * (365)) / (strategy.estimatedTotalAssets())
        ),
    )

    # withdraw and confirm we made money, or at least that we have about the same
    vault.withdraw({"from": whale})
    assert token.balanceOf(whale) >= startingWhale
