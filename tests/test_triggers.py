def test_triggers(
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

    # update our creditThreshold so harvest triggers true
    strategy.setCreditThreshold(1, {"from": gov})
    tx = strategy.harvestTrigger(0, {"from": gov})
    assert tx == True, "Should we harvest? Should have been True"
    # increase this so it doesn't trigger stuff below
    strategy.setCreditThreshold(1e30, {"from": gov})

    chain.sleep(1)
    strategy.harvest({"from": gov})
    chain.sleep(1)

    # simulate a day of earnings
    chain.sleep(86400)
    chain.mine(1)

    # harvest should trigger false; hasn't been long enough
    tx = strategy.harvestTrigger(0, {"from": gov})
    assert tx == False, "Should we harvest? Should have been False"

    # simulate 5 days of earnings
    chain.sleep(86400 * 5)
    chain.mine(1)

    # harvest should trigger true
    tx = strategy.harvestTrigger(0, {"from": gov})
    assert tx == True, "Should we harvest? Should have been True"

    # simulate 5 days of earnings
    chain.sleep(86400 * 5)
    chain.mine(1)

    # harvest should trigger true
    tx = strategy.harvestTrigger(0, {"from": gov})
    assert tx == True, "Should we harvest? Should have been True"

    # withdraw and confirm we made money
    strategy.harvest({"from": gov})
    vault.withdraw({"from": whale})
    assert token.balanceOf(whale) >= startingWhale


def test_less_useful_triggers(
    gov,
    token,
    vault,
    whale,
    strategy,
    chain,
    amount,
):
    ## deposit to the vault after approving
    token.approve(vault, 2**256 - 1, {"from": whale})
    vault.deposit(amount, {"from": whale})
    chain.sleep(1)
    strategy.harvest({"from": gov})
    chain.sleep(1)

    strategy.setMinReportDelay(100, {"from": gov})
    tx = strategy.harvestTrigger(0, {"from": gov})
    assert tx == False, "Should we harvest? Should have been False"

    chain.sleep(200)
