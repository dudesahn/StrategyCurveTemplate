from scripts.utils import getSnapshot


def test_simple_harvest(
    gov,
    token,
    vault,
    whale,
    strategy,
    chain,
    gauge,
    amount,
):
    print("#######################################################")
    print("Start of test #########################################")
    print("#######################################################\n")

    getSnapshot(vault, strategy)

    ## deposit to the vault after approving
    startingWhale = token.balanceOf(whale)
    token.approve(vault, 2**256 - 1, {"from": whale})
    vault.deposit(amount, {"from": whale})

    # yVault shares are minted 1:1 with the first deposit
    assert vault.balanceOf(whale) == amount, "Shares were not minted 1:1"

    # The vault should now hold the deposit token
    assert token.balanceOf(vault) == amount, "The vault is not holding `token`"

    # The whale should now have a lower balance of token by `amount`
    assert (
        token.balanceOf(whale) == startingWhale - amount
    ), "Balance did not decrease as expected"

    # Note that up to this point, the strategy assets/liabilities have not changed.

    # change our optimal deposit asset
    strategy.setTargetToken(0, {"from": gov})

    # this is part of our check into the staking contract balance
    stakingBeforeHarvest = gauge.balanceOf(strategy)

    assert (
        stakingBeforeHarvest == 0
    ), "The amount of gauge tokens should have been zero as nothing has been deposited into the strategy yet"

    print("#######################################################")
    print("After first deposit ###################################")
    print("#######################################################\n")

    getSnapshot(vault, strategy)

    # harvest, store asset amount
    chain.sleep(1)
    strategy.harvest({"from": gov})
    chain.sleep(1)

    # totalAssets() is in `want` units net of harvest costs (uniswap fees, mgmt fees and perf. fees)
    # Beause there hasn't been any gains yet, all these fees will be zero
    old_assets = vault.totalAssets()

    print("#######################################################")
    print("After first deposit and harvest #######################")
    print("#######################################################\n")

    getSnapshot(vault, strategy)

    assert old_assets > 0
    assert token.balanceOf(strategy) == 0, "Want not deposited into the gauge"
    assert strategy.estimatedTotalAssets() > 0

    assert gauge.balanceOf(strategy) > stakingBeforeHarvest

    # simulate 'x' hours of earnings because more CRV need to be sent over
    hours = 8
    chain.sleep(60 * 60 * hours)
    chain.mine(1)

    # harvest, store new asset amount
    chain.sleep(1)
    strategy.harvest({"from": gov})

    print("#######################################################")
    print(f"Harvest after {hours} hours ###############################")
    print("#######################################################\n")

    getSnapshot(vault, strategy)

    # totalAssets() is in `want` units net of harvest costs incurred by the strategy (uniswap fees,
    # mgmt fees and perf. fees)
    # _freeFunds() is [totalAssets() - lockedProfit()]
    # lockedProfit() is the amount of profits that have been time-locked.
    # pricePerShare() = [freeFunds() / totalSupply()] * 10^18

    new_assets = vault.totalAssets()

    # confirm we made money
    assert new_assets > old_assets

    # Note that new vault shares are issued to cover fees. This reduces
    # overall share price by the combined fee (perf + mgmt)

    # Display estimated APR
    print(
        "#######################################################\n",
        "Estimated 2CRV APR: ",
        "{:.2%}".format(
            ((new_assets - old_assets) * (365.25 * (24 / hours)))
            / (strategy.estimatedTotalAssets())
        ),
        "\n#######################################################\n",
    )

    # change our optimal deposit asset
    # selling into USDC is ...
    strategy.setTargetToken(1, {"from": gov})

    assert token.balanceOf(strategy) == 0
    assert gauge.balanceOf(strategy) > 0

    # simulate 'x'' hours of earnings because more CRV need to be sent over
    hours = 8
    chain.sleep(60 * 60 * hours)
    chain.mine(1)  # needed to accrue CRV for the time elapsed

    # harvest, store new asset amount
    chain.sleep(1)
    strategy.harvest({"from": gov})
    chain.sleep(1)
    after_harvest_assets = vault.totalAssets()

    # confirm we made money, or at least that we have about the same
    assert after_harvest_assets > new_assets

    print("#######################################################")
    print(f"After {hours} more hours with different target token #######")
    print("#######################################################\n")

    getSnapshot(vault, strategy)

    # Display estimated APR
    print(
        "#######################################################\n",
        "Estimated 2CRV APR: ",
        "{:.2%}".format(
            ((after_harvest_assets - new_assets) * (365.25 * (24 / hours)))
            / (strategy.estimatedTotalAssets())
        ),
        "\n#######################################################\n",
    )

    # simulate 'x'' hours of earnings because more CRV need to be sent over
    hours = 8
    chain.sleep(60 * 60 * hours)
    chain.mine(1)  # needed to accrue CRV for the time elapsed

    # withdraw and confirm we made money
    vault.withdraw({"from": whale})
    assert token.balanceOf(whale) > startingWhale

    # Check that once everyone is out that the outstading shares are equal to those
    # rewarded to the protocol
    assert vault.totalSupply() == vault.balanceOf(vault.rewards())

    print("#######################################################")
    print(f"After {hours} more hours, the whale withdraws ##############")
    print("#######################################################\n")

    getSnapshot(vault, strategy)
