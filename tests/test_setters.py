import brownie


def test_setters(
    gov,
    strategy,
    strategist,
    chain,
    whale,
    token,
    vault,
    amount,
):

    # test our manual harvest trigger
    strategy.setForceHarvestTriggerOnce(True, {"from": gov})
    tx = strategy.harvestTrigger(0, {"from": gov})
    assert tx == True, "Should we harvest? Should have been true."

    strategy.setForceHarvestTriggerOnce(False, {"from": gov})
    tx = strategy.harvestTrigger(0, {"from": gov})
    assert tx == False, "Should we harvest? Should have been false."

    # test our manual harvest trigger, and that a harvest turns it off
    strategy.setForceHarvestTriggerOnce(True, {"from": gov})
    tx = strategy.harvestTrigger(0, {"from": gov})
    assert tx == True, "Should we harvest? Should have been true."

    strategy.harvest({"from": gov})
    tx = strategy.harvestTrigger(0, {"from": gov})
    assert tx == False, "Should we harvest? Should have been false."

    ## deposit to the vault after approving
    token.approve(vault, 2**256 - 1, {"from": whale})
    vault.deposit(amount, {"from": whale})
    chain.sleep(1)
    strategy.harvest({"from": gov})

    # test our setters in baseStrategy and our main strategy
    strategy.setDebtThreshold(1, {"from": gov})
    strategy.setMaxReportDelay(0, {"from": gov})
    strategy.setMaxReportDelay(1e18, {"from": gov})
    strategy.setMetadataURI(0, {"from": gov})
    strategy.setMinReportDelay(100, {"from": gov})
    strategy.setProfitFactor(1000, {"from": gov})
    strategy.setRewards(gov, {"from": strategist})
    strategy.setCreditThreshold(10, {"from": gov})

    strategy.setStrategist(strategist, {"from": gov})
    name = strategy.name()
    print("Strategy Name:", name)

    # health check stuff
    chain.sleep(86400)
    strategy.harvest({"from": gov})
    chain.sleep(1)
    strategy.setDoHealthCheck(False, {"from": gov})
    chain.sleep(86400)
    strategy.harvest({"from": gov})
    chain.sleep(86400)

    zero = "0x0000000000000000000000000000000000000000"

    # change our target deposit asset
    strategy.setTargetToken(0, {"from": gov})
    strategy.setTargetToken(1, {"from": gov})

    with brownie.reverts():
        strategy.setTargetToken(2, {"from": gov})
    with brownie.reverts():
        strategy.setKeeper(zero, {"from": gov})
    with brownie.reverts():
        strategy.setRewards(zero, {"from": strategist})
    with brownie.reverts():
        strategy.setStrategist(zero, {"from": gov})
    with brownie.reverts():
        strategy.setDoHealthCheck(False, {"from": whale})
    with brownie.reverts():
        strategy.setEmergencyExit({"from": whale})
    with brownie.reverts():
        strategy.setMaxReportDelay(1000, {"from": whale})
    with brownie.reverts():
        strategy.setRewards(strategist, {"from": whale})
    with brownie.reverts():
        strategy.harvest({"from": whale})

    # try a health check with zero address as health check
    strategy.setHealthCheck(zero, {"from": gov})
    strategy.setDoHealthCheck(True, {"from": gov})
    strategy.harvest({"from": gov})

    # try a health check with random contract as health check
    strategy.setHealthCheck(gov, {"from": gov})
    strategy.setDoHealthCheck(True, {"from": gov})
    # this is causing the RPC to crash now, weirdly

    # set emergency exit last
    strategy.setEmergencyExit({"from": gov})
    with brownie.reverts():
        strategy.setEmergencyExit({"from": gov})
