import brownie
from brownie import Contract
from brownie import config
import math


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
    voter,
    amount,
):
    ## deposit to the vault after approving
    startingWhale = token.balanceOf(whale)
    token.approve(vault, 2**256 - 1, {"from": whale})
    vault.deposit(amount, {"from": whale})
    newWhale = token.balanceOf(whale)

    # change our optimal deposit asset
    strategy.setOptimal(0, {"from": gov})

    # this is part of our check into the staking contract balance
    stakingBeforeHarvest = gauge.balanceOf(strategy)

    # harvest, store asset amount
    chain.sleep(1)
    strategy.harvest({"from": gov})
    chain.sleep(1)
    old_assets = vault.totalAssets()
    assert old_assets > 0
    assert token.balanceOf(strategy) == 0
    assert strategy.estimatedTotalAssets() > 0
    print("\nStarting Assets: ", old_assets / 1e18)

    # try and include custom logic here to check that funds are in the staking contract (if needed)
    assert gauge.balanceOf(strategy) > stakingBeforeHarvest

    # simulate 12 hours of earnings because more CRV need to be sent over
    chain.sleep(43200)
    chain.mine(1)

    # harvest, store new asset amount
    chain.sleep(1)
    strategy.harvest({"from": gov})
    chain.sleep(1)
    new_assets = vault.totalAssets()
    # confirm we made money, or at least that we have about the same
    assert new_assets > old_assets
    print("\nAssets after 1 day: ", new_assets / 1e18)

    # Display estimated APR
    print(
        "\nEstimated DAI APR: ",
        "{:.2%}".format(
            ((new_assets - old_assets) * (365 * 2)) / (strategy.estimatedTotalAssets())
        ),
    )

    # change our optimal deposit asset
    strategy.setOptimal(1, {"from": gov})

    # store asset amount
    before_usdc_assets = vault.totalAssets()
    assert token.balanceOf(strategy) == 0

    # try and include custom logic here to check that funds are in the staking contract (if needed)
    assert gauge.balanceOf(strategy) > 0

    # simulate 12 hours of earnings because more CRV need to be sent over
    chain.sleep(43200)
    chain.mine(1)

    # harvest, store new asset amount
    chain.sleep(1)
    strategy.harvest({"from": gov})
    chain.sleep(1)
    after_usdc_assets = vault.totalAssets()
    # confirm we made money, or at least that we have about the same
    assert after_usdc_assets > before_usdc_assets

    # Display estimated APR
    print(
        "\nEstimated USDC APR: ",
        "{:.2%}".format(
            ((after_usdc_assets - before_usdc_assets) * (365 * 2))
            / (strategy.estimatedTotalAssets())
        ),
    )

    # change our optimal deposit asset
    strategy.setOptimal(2, {"from": gov})

    # store asset amount
    before_usdc_assets = vault.totalAssets()
    assert token.balanceOf(strategy) == 0

    # try and include custom logic here to check that funds are in the staking contract (if needed)
    assert gauge.balanceOf(strategy) > 0

    # simulate 12 hours of earnings because more CRV need to be sent over
    chain.sleep(43200)
    chain.mine(1)

    # harvest, store new asset amount
    chain.sleep(1)
    strategy.harvest({"from": gov})
    chain.sleep(1)
    after_usdc_assets = vault.totalAssets()
    # confirm we made money, or at least that we have about the same
    assert after_usdc_assets > before_usdc_assets

    # Display estimated APR
    print(
        "\nEstimated fUSDT APR: ",
        "{:.2%}".format(
            ((after_usdc_assets - before_usdc_assets) * (365 * 2))
            / (strategy.estimatedTotalAssets())
        ),
    )

    # simulate a day of waiting for share price to bump back up
    chain.sleep(86400)
    chain.mine(1)

    # withdraw and confirm we made money, or at least that we have about the same
    vault.withdraw({"from": whale})
    assert token.balanceOf(whale) > startingWhale
