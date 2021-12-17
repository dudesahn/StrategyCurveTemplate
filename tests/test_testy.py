import brownie
from brownie import Contract
from brownie import config
import math


def test_testy(
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
    accounts,
):
    ## deposit to the vault after approving
    startingWhale = token.balanceOf(whale)
    token.approve(vault, 2 ** 256 - 1, {"from": whale})
    vault.deposit(amount, {"from": whale})
    newWhale = token.balanceOf(whale)

    chain.sleep(1)
    strategy.harvest({"from": gov})
    chain.sleep(1)

    # change our optimal deposit asset
    strategy.setOptimal(0, {"from": gov})

    # send some crv to our strategy
    crv = Contract(strategy.crv())
    crv_whale = accounts.at("0xa3dC11221BAe3B770e0B61a5BfC640a1BE9c0B8a", force=True)
    crv.transfer(strategy, 800e18, {"from": crv_whale})
    geist = Contract(strategy.geist())
    geist.transfer(strategy, 800e18, {"from": crv_whale})
    wftm = Contract(strategy.wftm())
    wftm_whale = accounts.at("0xD9a9bD506589beEA88825A8F0868C2EF0Ed0fBee", force=True)
    wftm.transfer(strategy, 800e18, {"from": wftm_whale})

    # harvest, store asset amount
    chain.sleep(1)
    strategy.setDoHealthCheck(False, {"from": gov})
    tx = strategy.harvest({"from": gov})
    profits = tx.events["Harvested"]["profit"]
    print("This is our profit:", profits)
    chain.sleep(1)

    # simulate a day of waiting for share price to bump back up
    chain.sleep(86400)
    chain.mine(1)

    # withdraw and confirm we made money, or at least that we have about the same
    vault.withdraw({"from": whale})
    assert token.balanceOf(whale) >= startingWhale
