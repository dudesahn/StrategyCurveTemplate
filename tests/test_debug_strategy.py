from brownie import accounts, Wei, Contract

def test_debug_strategy(strategy, rewardToken):

    crv_whale = accounts.at("0x4a65e76be1b4e8dd6ef618277fa55200e3f8f20a", True)
    usdt = Contract("0xFd086bC7CD5C481DCC9C85ebE478A1C0b69FCbb9")
    rewardToken.transfer(strategy, Wei("1_000 ether"), {"from": crv_whale})
    tx = strategy.sell(rewardToken.balanceOf(strategy), {"from": crv_whale})

    assert usdt.balanceOf(strategy) > 0
