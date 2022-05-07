from scripts.utils import getSnapshot
import math

# test passes as of 21-06-26
def test_change_debt(
    gov,
    token,
    vault,
    whale,
    strategy,
    chain,
    amount,
):

    ## deposit to the vault after approving
    startingWhale = token.balanceOf(whale)
    token.approve(vault, 2**256 - 1, {"from": whale})
    vault.deposit(amount, {"from": whale})
    chain.sleep(1)
    strategy.harvest({"from": gov})
    chain.sleep(1)

    getSnapshot(vault, strategy)

    # evaluate our current total assets
    old_assets = vault.totalAssets()
    startingStrategy = strategy.estimatedTotalAssets()

    # debtRatio is in BPS (aka, max is 10,000, which represents 100%), and is a fraction of the funds that can be in the strategy
    currentDebt = 10000
    vault.updateStrategyDebtRatio(strategy, currentDebt / 2, {"from": gov})
    # sleep for a day to make sure we are swapping enough (Uni v3 combined with only 6 decimals)
    chain.sleep(60 * 60 * 24)
    strategy.harvest({"from": gov})
    chain.sleep(1)

    getSnapshot(vault, strategy)

    assert strategy.estimatedTotalAssets() < startingStrategy

    # simulate one day of earnings
    chain.sleep(86400)
    chain.mine(1)

    # set DebtRatio back to 100%
    vault.updateStrategyDebtRatio(strategy, currentDebt, {"from": gov})
    chain.sleep(1)
    strategy.harvest({"from": gov})
    chain.sleep(1)

    # evaluate our current total assets
    new_assets = vault.totalAssets()

    getSnapshot(vault, strategy)

    # confirm we made money, or at least that we have about the same
    assert new_assets >= old_assets or math.isclose(new_assets, old_assets, abs_tol=5)

    # simulate a day of waiting for share price to bump back up
    chain.sleep(86400)
    chain.mine(1)

    # withdraw and confirm our whale made money
    vault.withdraw({"from": whale})
    assert token.balanceOf(whale) >= startingWhale

    # Check that once everyone is out that the outstading shares are equal to those
    # rewarded to the protocol
    assert vault.totalSupply() == vault.balanceOf(vault.rewards())

    getSnapshot(vault, strategy)
