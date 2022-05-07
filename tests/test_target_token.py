def test_target_token(usdt, usdc, strategy, gov):

    # The strategy is deployed with USDT being the target token
    assert strategy.targetToken() == usdt.address, "Strategy not initiated with USDT"

    # change our optimal deposit asset
    strategy.setTargetToken(1, {"from": gov})

    assert strategy.targetToken() == usdc.address, "Optimal token wasn't updated"

    strategy.setOptimal(0, {"from": gov})

    assert strategy.targetToken() == usdt.address, "Optimal token wasn't updated"
