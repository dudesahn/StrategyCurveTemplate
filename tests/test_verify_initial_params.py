from brownie import config


def test_verify_initial_params(strategy, healthCheck, vault):

    assert strategy.vault() == config["contracts"]["vault"]
    assert strategy.vault() == vault.address

    # doHealthCheck() returns a bool that enables/disables calls to the healthcheck contract
    assert (
        strategy.doHealthCheck() == False
    ), "A freshly added strategy has doHealthCheck() returning False."

    # The healthCheck contract is called within harvest() only when doHealthCheck() == True and healthCheck()
    # returns a valid healthcheck address
    assert strategy.healthCheck() == healthCheck.address

    assert (
        strategy.apiVersion() == vault.apiVersion()
    ), "The version of the strategy and vault contracts does not match."

    assert (
        strategy.name() == config["strategy"]["name"]
    ), "Strategy name not setup properly"

    # delegatedAssets ais the amount in want that may have been transfered to another
    # contract - e.g., a different vault. Management fees are not charged to delegated assets.
    assert strategy.delegatedAssets() == 0, "Delegated Assets are not 0"

    # Check roles were assigned as planned
    assert strategy.strategist() == config["wallets"]["strategist"]
    assert strategy.rewards() == config["wallets"]["rewards"]
    assert strategy.keeper() == config["wallets"]["keeper"]

    assert vault.governance() in [
        config["wallets"]["governance"],
        config["wallets"]["strategist"],
    ]

    assert strategy.want() == config["contracts"]["token"]
    assert strategy.gauge() == config["contracts"]["gauge"]
    assert strategy.want() == config["contracts"]["token"]
    assert strategy.targetToken() == config["contracts"]["usdc"]

    # The maximum number of seconds between harvest calls.
    assert (
        strategy.minReportDelay() >= 0
        and strategy.minReportDelay() < strategy.maxReportDelay()
    )

    # The maximum number of seconds between harvest calls.
    assert strategy.maxReportDelay() <= 60 * 60 * 48

    # The minimum multiple that `callCost` must be above the credit/profit to be "justifiable".
    assert strategy.profitFactor() >= 100

    #  `debtThreshold`` =>  how far the Strategy can go into loss without a harvest and report
    #  being required.
    #
    #  By default this is 0, meaning any losses would cause a harvest which
    #  will subsequently report the loss to the Vault for tracking. (See
    #  `harvestTrigger()` for more details.)
    assert strategy.debtThreshold() == 0

    # emergencyExit() True or False. Initialized as False. setEmergencyExit()
    # sets it to True before running revokeStrategy()
    assert strategy.emergencyExit() == False
