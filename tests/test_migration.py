import brownie
import math


def test_migration(
    StrategyCurveTricrypto,
    gov,
    token,
    vault,
    guardian,
    strategist,
    whale,
    strategy,
    chain,
    strategist_ms,
    healthCheck,
    amount,
    pool,
    strategy_name,
    gauge,
    crv,
):

    ## deposit to the vault after approving
    token.approve(vault, 2**256 - 1, {"from": whale})
    vault.deposit(amount, {"from": whale})
    chain.sleep(1)
    strategy.harvest({"from": gov})
    chain.sleep(1)

    # deploy our new strategy
    new_strategy = strategist.deploy(
        StrategyCurveTricrypto,
        vault,
        strategy_name,
    )
    total_old = strategy.estimatedTotalAssets()

    # can we harvest an unactivated strategy? should be no
    # under our new method of using min and maxDelay, this no longer matters or works
    # tx = new_strategy.harvestTrigger(0, {"from": gov})
    # print("\nShould we harvest? Should be False.", tx)
    # assert tx == False

    # simulate 1 day of earnings
    chain.sleep(86400)
    chain.mine(1)

    claimable_tokens = gauge.claimable_tokens.call(strategy)
    crv_balance_old_strat = crv.balanceOf(strategy)

    assert claimable_tokens > 0, "No tokens to be claimed"

    # migrate our old strategy
    vault.migrateStrategy(strategy, new_strategy, {"from": gov})
    new_strategy.setHealthCheck(healthCheck, {"from": gov})
    new_strategy.setDoHealthCheck(True, {"from": gov})

    with brownie.reverts("!authorized"):
        strategy.claimRewards({"from": whale})

    strategy.claimRewards({"from": gov})

    assert crv.balanceOf(strategy) > 0, "No tokens were claimed"

    strategy.sweep(crv, {"from": gov})

    assert crv.balanceOf(strategy) == 0, "Tokens were not swept"

    # assert that our old strategy is empty
    updated_total_old = strategy.estimatedTotalAssets()
    assert updated_total_old == 0

    # harvest to get funds back in strategy
    chain.sleep(1)
    new_strategy.harvest({"from": gov})
    new_strat_balance = new_strategy.estimatedTotalAssets()

    # confirm we made money, or at least that we have about the same
    assert new_strat_balance >= total_old or math.isclose(
        new_strat_balance, total_old, abs_tol=5
    )

    starting_vault_assets = vault.totalAssets()
    print("\nVault starting assets with new strategy: ", starting_vault_assets)

    # simulate one day of earnings
    chain.sleep(86400)
    chain.mine(1)

    # Test out our migrated strategy, confirm we're making a profit
    new_strategy.harvest({"from": gov})
    vaultAssets_2 = vault.totalAssets()
    # confirm we made money, or at least that we have about the same
    assert vaultAssets_2 >= starting_vault_assets or math.isclose(
        vaultAssets_2, starting_vault_assets, abs_tol=5
    )
    print("\nAssets after 1 day harvest: ", vaultAssets_2)


def test_migration_from_real_strat(
    gov,
    vaultDeployed,
    strategist,
    chain,
    healthCheck,
    strategy_to_migrate_from,
    StrategyCurveTricrypto,
    strategy_name,
):

    strategy_to_migrate_from.harvest({"from": gov})

    total_old = strategy_to_migrate_from.estimatedTotalAssets()

    # deploy our new strategy
    new_strategy = strategist.deploy(
        StrategyCurveTricrypto,
        vaultDeployed,
        strategy_name,
    )

    # migrate our old strategy
    vaultDeployed.migrateStrategy(strategy_to_migrate_from, new_strategy, {"from": gov})
    new_strategy.setDoHealthCheck(True, {"from": gov})

    # assert that our old strategy is empty
    updated_total_old = strategy_to_migrate_from.estimatedTotalAssets()
    assert updated_total_old == 0

    # harvest to get funds back in strategy
    new_strategy.harvest({"from": gov})
    new_strat_balance = new_strategy.estimatedTotalAssets()

    # confirm the same amount of assets were moved to the new strat
    assert new_strat_balance == total_old

    starting_vault_assets = vaultDeployed.totalAssets()
    print("\nVault starting assets with new strategy: ", starting_vault_assets)

    # simulate one day of earnings
    chain.sleep(86400)
    chain.mine(1)

    # Test out our migrated strategy, confirm we're making a profit
    new_strategy.harvest({"from": gov})
    vaultAssets_2 = vaultDeployed.totalAssets()

    # confirm we made money
    assert vaultAssets_2 > starting_vault_assets
