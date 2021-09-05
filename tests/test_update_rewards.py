import brownie
from brownie import Wei, accounts, Contract, config


def test_update_from_zero(
    gov,
    token,
    vault,
    strategist,
    whale,
    strategy,
    keeper,
    rewards,
    chain,
    StrategyCurve3CrvRewardsClonable,
    voter,
    proxy,
    pid,
    amount,
    pool,
    strategy_name,
    gauge,
    has_rewards,
    rewards_token,
    zero_address,
):
    ## clone our strategy, set our rewards to zero address
    tx = strategy.cloneCurve3CrvRewards(
        vault,
        strategist,
        rewards,
        keeper,
        pool,
        gauge,
        False,
        zero_address,
        strategy_name,
        {"from": gov},
    )
    newStrategy = StrategyCurve3CrvRewardsClonable.at(tx.return_value)

    # revoke and send all funds back to vault
    vault.revokeStrategy(strategy, {"from": gov})
    strategy.harvest({"from": gov})

    # attach our new strategy and approve it on the proxy
    vault.addStrategy(newStrategy, 10_000, 0, 2 ** 256 - 1, 1_000, {"from": gov})
    proxy.approveStrategy(newStrategy.gauge(), newStrategy, {"from": gov})

    assert vault.withdrawalQueue(1) == newStrategy
    assert vault.strategies(newStrategy)[2] == 10_000
    assert vault.withdrawalQueue(0) == strategy
    assert vault.strategies(strategy)[2] == 0

    ## deposit to the vault after approving; this is basically just our simple_harvest test
    before_pps = vault.pricePerShare()
    startingWhale = token.balanceOf(whale)
    token.approve(vault, 2 ** 256 - 1, {"from": whale})
    vault.deposit(1000e18, {"from": whale})

    # simulate 1 day of waiting
    chain.sleep(86400)
    chain.mine(1)

    # harvest, store asset amount
    tx = newStrategy.harvest({"from": gov})
    old_assets_dai = vault.totalAssets()
    assert old_assets_dai > 0
    assert token.balanceOf(newStrategy) == 0
    assert newStrategy.estimatedTotalAssets() > 0
    assert gauge.balanceOf(voter) > 0

    # simulate 1 day of earnings
    chain.sleep(86400)
    chain.mine(1)

    # harvest after a day, store new asset amount
    newStrategy.harvest({"from": gov})
    new_assets_dai = vault.totalAssets()
    # we can't use strategyEstimated Assets because the profits are sent to the vault
    assert new_assets_dai >= old_assets_dai

    # Display estimated APR
    print(
        "\nEstimated DAI APR (Rewards Off): ",
        "{:.2%}".format(
            ((new_assets_dai - old_assets_dai) * (365))
            / (newStrategy.estimatedTotalAssets())
        ),
    )

    # check that we still don't have a rewards token set
    assert newStrategy.rewardsToken() == zero_address
    assert newStrategy.hasRewards() == False
    assert (
        rewards_token.allowance(
            newStrategy, "0xd9e1cE17f2641f24aE83637ab66a2cca9C378B9F"
        )
        == 0
    )

    # add our rewards token, harvest to take the profit from it. this should be extra high yield from this harvest
    newStrategy.updateRewards(rewards_token, {"from": gov})

    # assert that we set things up correctly
    assert newStrategy.rewardsToken() == rewards_token
    assert newStrategy.hasRewards() == True
    assert (
        rewards_token.allowance(
            newStrategy, "0xd9e1cE17f2641f24aE83637ab66a2cca9C378B9F"
        )
        > 0
    )

    # track our new pps and assets
    new_pps = vault.pricePerShare()
    old_assets_dai = vault.totalAssets()

    # harvest with our new rewards token attached
    chain.sleep(86400)
    chain.mine(1)
    newStrategy.harvest({"from": gov})

    # confirm that we are selling our rewards token
    assert newStrategy.rewardsToken() == rewards_token
    assert newStrategy.hasRewards() == True
    assert rewards_token.balanceOf(newStrategy) == 0
    new_assets_dai = vault.totalAssets()

    # Display estimated APR
    print(
        "\nEstimated DAI APR (Rewards On, 2 days of rewards tokens): ",
        "{:.2%}".format(
            ((new_assets_dai - old_assets_dai) * (365))
            / (newStrategy.estimatedTotalAssets())
        ),
    )

    # simulate a day of waiting for share price to bump back up
    chain.sleep(86400)
    chain.mine(1)

    # withdraw and confirm we made money
    vault.withdraw({"from": whale})
    assert token.balanceOf(whale) >= startingWhale
    assert vault.pricePerShare() > before_pps
    assert vault.pricePerShare() > new_pps


def test_turn_off_rewards(
    gov,
    token,
    vault,
    strategist,
    whale,
    strategy,
    keeper,
    rewards,
    chain,
    StrategyCurve3CrvRewardsClonable,
    voter,
    proxy,
    pid,
    amount,
    pool,
    strategy_name,
    gauge,
    has_rewards,
    rewards_token,
    zero_address,
):
    ## clone our strategy, set our rewards to zero address
    tx = strategy.cloneCurve3CrvRewards(
        vault,
        strategist,
        rewards,
        keeper,
        pool,
        gauge,
        has_rewards,
        rewards_token,
        strategy_name,
        {"from": gov},
    )
    newStrategy = StrategyCurve3CrvRewardsClonable.at(tx.return_value)

    # revoke and send all funds back to vault
    vault.revokeStrategy(strategy, {"from": gov})
    strategy.harvest({"from": gov})

    # attach our new strategy and approve it on the proxy
    vault.addStrategy(newStrategy, 10_000, 0, 2 ** 256 - 1, 1_000, {"from": gov})
    proxy.approveStrategy(newStrategy.gauge(), newStrategy, {"from": gov})

    ## deposit to the vault after approving; this is basically just our simple_harvest test
    before_pps = vault.pricePerShare()
    startingWhale = token.balanceOf(whale)
    token.approve(vault, 2 ** 256 - 1, {"from": whale})
    vault.deposit(1000e18, {"from": whale})

    # simulate 1 day of waiting
    chain.sleep(86400)
    chain.mine(1)

    # harvest, store asset amount
    tx = newStrategy.harvest({"from": gov})
    old_assets_dai = vault.totalAssets()
    assert old_assets_dai > 0

    # simulate 1 day of earnings
    chain.sleep(86400)
    chain.mine(1)

    # harvest after a day, store new asset amount
    newStrategy.harvest({"from": gov})
    new_assets_dai = vault.totalAssets()
    # we can't use strategyEstimated Assets because the profits are sent to the vault
    assert new_assets_dai >= old_assets_dai

    # Display estimated APR based on the two days before the pay out
    print(
        "\nEstimated DAI APR (Rewards On): ",
        "{:.2%}".format(
            ((new_assets_dai - old_assets_dai) * (365))
            / (newStrategy.estimatedTotalAssets())
        ),
    )

    # turn off rewards claiming
    old_assets_dai = vault.totalAssets()
    newStrategy.turnOffRewards({"from": gov})
    assert newStrategy.hasRewards() == False
    assert newStrategy.rewardsToken() == zero_address
    assert (
        rewards_token.allowance(
            newStrategy, "0xd9e1cE17f2641f24aE83637ab66a2cca9C378B9F"
        )
        == 0
    )
    new_pps = vault.pricePerShare()

    # harvest with our rewards token off
    chain.sleep(86400)
    chain.mine(1)
    newStrategy.harvest({"from": gov})
    new_assets_dai = vault.totalAssets()

    print(
        "\nEstimated DAI APR (Rewards Off): ",
        "{:.2%}".format(
            ((new_assets_dai - old_assets_dai) * (365))
            / (newStrategy.estimatedTotalAssets())
        ),
    )

    # simulate a day of waiting for share price to bump back up
    chain.sleep(86400)
    chain.mine(1)

    # withdraw and confirm we made money
    vault.withdraw({"from": whale})
    assert token.balanceOf(whale) >= startingWhale
    assert vault.pricePerShare() > before_pps
    assert vault.pricePerShare() > new_pps


def test_update_from_zero_to_off(
    gov,
    token,
    vault,
    strategist,
    whale,
    strategy,
    keeper,
    rewards,
    chain,
    StrategyCurve3CrvRewardsClonable,
    voter,
    proxy,
    pid,
    amount,
    pool,
    strategy_name,
    gauge,
    has_rewards,
    rewards_token,
    zero_address,
):
    ## clone our strategy, set our rewards to zero address
    tx = strategy.cloneCurve3CrvRewards(
        vault,
        strategist,
        rewards,
        keeper,
        pool,
        gauge,
        False,
        zero_address,
        strategy_name,
        {"from": gov},
    )
    newStrategy = StrategyCurve3CrvRewardsClonable.at(tx.return_value)

    # revoke and send all funds back to vault
    vault.revokeStrategy(strategy, {"from": gov})
    strategy.harvest({"from": gov})

    # attach our new strategy and approve it on the proxy
    vault.addStrategy(newStrategy, 10_000, 0, 2 ** 256 - 1, 1_000, {"from": gov})
    proxy.approveStrategy(newStrategy.gauge(), newStrategy, {"from": gov})

    ## deposit to the vault after approving; this is basically just our simple_harvest test
    before_pps = vault.pricePerShare()
    startingWhale = token.balanceOf(whale)
    token.approve(vault, 2 ** 256 - 1, {"from": whale})
    vault.deposit(1000e18, {"from": whale})

    # simulate 1 day of waiting
    chain.sleep(86400)
    chain.mine(1)

    # harvest, store asset amount
    tx = newStrategy.harvest({"from": gov})
    old_assets_dai = vault.totalAssets()

    # simulate 1 day of earnings
    chain.sleep(86400)
    chain.mine(1)

    # harvest after a day, store new asset amount
    newStrategy.harvest({"from": gov})
    new_assets_dai = vault.totalAssets()
    # we can't use strategyEstimated Assets because the profits are sent to the vault
    assert new_assets_dai >= old_assets_dai

    # Display estimated APR
    print(
        "\nEstimated DAI APR (Rewards Off): ",
        "{:.2%}".format(
            ((new_assets_dai - old_assets_dai) * (365))
            / (newStrategy.estimatedTotalAssets())
        ),
    )

    # try turning off our rewards again
    assert newStrategy.rewardsToken() == zero_address
    assert newStrategy.hasRewards() == False
    assert (
        rewards_token.allowance(
            newStrategy, "0xd9e1cE17f2641f24aE83637ab66a2cca9C378B9F"
        )
        == 0
    )

    newStrategy.turnOffRewards({"from": gov})
    assert newStrategy.rewardsToken() == zero_address
    assert newStrategy.hasRewards() == False
    assert (
        rewards_token.allowance(
            newStrategy, "0xd9e1cE17f2641f24aE83637ab66a2cca9C378B9F"
        )
        == 0
    )

    # track our new pps and assets
    old_assets_dai = vault.totalAssets()

    # harvest with our new rewards token attached
    chain.sleep(86400)
    chain.mine(1)
    newStrategy.harvest({"from": gov})

    # confirm that we are selling our rewards token
    assert rewards_token.balanceOf(newStrategy) == 0
    new_assets_dai = vault.totalAssets()

    # Display estimated APR
    print(
        "\nEstimated DAI APR (Rewards Off Still): ",
        "{:.2%}".format(
            ((new_assets_dai - old_assets_dai) * (365))
            / (newStrategy.estimatedTotalAssets())
        ),
    )

    # simulate a day of waiting for share price to bump back up
    chain.sleep(86400)
    chain.mine(1)

    # withdraw and confirm we made money
    vault.withdraw({"from": whale})
    assert token.balanceOf(whale) >= startingWhale
    assert vault.pricePerShare() > before_pps


def test_change_rewards(
    gov,
    token,
    vault,
    strategist,
    whale,
    strategy,
    keeper,
    rewards,
    chain,
    StrategyCurve3CrvRewardsClonable,
    voter,
    proxy,
    pid,
    amount,
    pool,
    strategy_name,
    gauge,
    has_rewards,
    rewards_token,
    zero_address,
):
    ## clone our strategy, set our rewards to zero address
    tx = strategy.cloneCurve3CrvRewards(
        vault,
        strategist,
        rewards,
        keeper,
        pool,
        gauge,
        has_rewards,
        rewards_token,
        strategy_name,
        {"from": gov},
    )
    newStrategy = StrategyCurve3CrvRewardsClonable.at(tx.return_value)

    # revoke and send all funds back to vault
    vault.revokeStrategy(strategy, {"from": gov})
    strategy.harvest({"from": gov})

    # attach our new strategy and approve it on the proxy
    vault.addStrategy(newStrategy, 10_000, 0, 2 ** 256 - 1, 1_000, {"from": gov})
    proxy.approveStrategy(newStrategy.gauge(), newStrategy, {"from": gov})

    ## deposit to the vault after approving; this is basically just our simple_harvest test
    before_pps = vault.pricePerShare()
    startingWhale = token.balanceOf(whale)
    token.approve(vault, 2 ** 256 - 1, {"from": whale})
    vault.deposit(1000e18, {"from": whale})

    # simulate 1 day of waiting
    chain.sleep(86400)
    chain.mine(1)

    # harvest, store asset amount
    tx = newStrategy.harvest({"from": gov})
    old_assets_dai = vault.totalAssets()

    # simulate 1 day of earnings
    chain.sleep(86400)
    chain.mine(1)

    # harvest after a day, store new asset amount
    newStrategy.harvest({"from": gov})
    new_assets_dai = vault.totalAssets()
    # we can't use strategyEstimated Assets because the profits are sent to the vault
    assert new_assets_dai >= old_assets_dai

    # confirm that we are still selling our rewards token
    assert rewards_token.balanceOf(newStrategy) == 0

    # Display estimated APR
    print(
        "\nEstimated DAI APR (Rewards On): ",
        "{:.2%}".format(
            ((new_assets_dai - old_assets_dai) * (365))
            / (newStrategy.estimatedTotalAssets())
        ),
    )

    # pretend that we're getting our underlying token as a reward, assert that the approvals worked on sushi router
    newStrategy.updateRewards(token, {"from": gov})
    assert (
        token.allowance(newStrategy, "0xd9e1cE17f2641f24aE83637ab66a2cca9C378B9F") > 0
    )
    assert newStrategy.rewardsToken() == token
    assert newStrategy.hasRewards() == True
