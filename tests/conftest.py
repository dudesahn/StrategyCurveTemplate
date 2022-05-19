import pytest
from brownie import config, Contract, convert, config, Wei, interface


@pytest.fixture(scope="module")
def Strategy():
    Strategy = config["strategy"]["name"]
    Strategy = getattr(__import__("brownie"), Strategy)
    yield Strategy


# Snapshots the chain before each test and reverts after test completion.
@pytest.fixture(autouse=True)
def isolation(fn_isolation):
    pass


@pytest.fixture(scope="module")
def whale(accounts):
    # Totally in it for the tech
    # Update this with a large holder of your want token (the largest EOA holder of LP)
    whale = accounts.at(convert.to_address(config["wallets"]["lp_whale"]), force=True)
    yield whale


# this is the amount of funds we have our whale deposit. adjust this as needed based on their wallet balance
@pytest.fixture(scope="module")
def amount():
    amount = Wei("5_000 ether")
    yield amount


# this is the name we want to give our strategy
@pytest.fixture(scope="module")
def strategy_name():
    strategy_name = config["strategy"]["name"]
    yield strategy_name


# use this when we might lose a few wei on conversions between want and another deposit token
@pytest.fixture(scope="module")
def is_slippery():
    is_slippery = False
    yield is_slippery


# use this to test our strategy in case there are no profits
@pytest.fixture(scope="module")
def no_profit():
    no_profit = False
    yield no_profit


# gauge for the curve pool
@pytest.fixture(scope="module")
def gauge():
    # this should be the address of the curve deposit token
    gauge = interface.ICurveGauge(convert.to_address(config["contracts"]["gauge"]))
    yield gauge


# gauge factory for the curve gauge
@pytest.fixture(scope="module")
def gaugeFactory():
    # this should be the address of the curve deposit token
    gaugeFactory = interface.ICurveGaugeFactory(
        convert.to_address(config["contracts"]["gaugeFactory"])
    )
    yield gaugeFactory


# curve deposit pool
@pytest.fixture(scope="module")
def pool():
    pool = interface.ICurvePool(convert.to_address(config["contracts"]["pool"]))
    yield pool


# Define relevant tokens and contracts in this section
@pytest.fixture(scope="module")
def token():
    # this should be the address of the ERC-20 used by the strategy/vault.
    # note that the pool is tokenized so the address is the same as above.
    token = interface.ERC20(convert.to_address(config["contracts"]["token"]))
    yield token


@pytest.fixture(scope="module")
def usdc():
    usdc = interface.ERC20(convert.to_address(config["contracts"]["usdc"]))
    yield usdc


@pytest.fixture(scope="module")
def usdt():
    usdt = interface.ERC20(convert.to_address(config["contracts"]["usdt"]))
    yield usdt


@pytest.fixture(scope="module")
def dai():
    # used to test strategy.sweep()
    dai = interface.ERC20(convert.to_address(config["contracts"]["dai"]))
    yield dai


@pytest.fixture(scope="module")
def rewardToken():
    # this should be the address of the ERC-20 rewarded by the gauge, by staking
    # the want token.
    rewardToken = interface.ERC20(convert.to_address(config["contracts"]["crv"]))
    yield rewardToken


@pytest.fixture(scope="function")
def other_vault_strategy():
    # used to test strategy.migrate()
    yield Contract(convert.to_address(config["contracts"]["other-vault-strat"]))


@pytest.fixture(scope="module")
def healthCheck():
    healthCheck = Contract(convert.to_address(config["contracts"]["healthCheck"]))
    yield healthCheck


# Define any accounts in this section
# for live testing, governance is the strategist MS; we will update this before we endorse
# normal gov is ychad, 0xFEB4acf3df3cDEA7399794D0869ef76A6EfAff52
@pytest.fixture(scope="module")
def gov(accounts):
    gov = accounts.at(convert.to_address(config["wallets"]["governance"]), force=True)
    yield gov


@pytest.fixture(scope="module")
def strategist_ms(accounts):
    # like governance, but better
    strategist_ms = accounts.at(
        convert.to_address(config["wallets"]["strategist_ms"]), force=True
    )
    yield strategist_ms


@pytest.fixture(scope="module")
def keeper(accounts):
    keeper = accounts.at(convert.to_address(config["wallets"]["keeper"]), force=True)
    yield keeper


@pytest.fixture(scope="module")
def rewards(accounts):
    rewards = accounts.at(convert.to_address(config["wallets"]["rewards"]), force=True)
    yield rewards


@pytest.fixture(scope="module")
def guardian(accounts):
    guardian = accounts.at(
        convert.to_address(config["wallets"]["guardian"]), force=True
    )
    yield guardian


@pytest.fixture(scope="module")
def management(accounts):
    management = accounts.at(
        convert.to_address(config["wallets"]["management"]), force=True
    )
    yield management


@pytest.fixture(scope="module")
def strategist(accounts):
    strategist = accounts.at(
        convert.to_address(config["wallets"]["strategist"]), force=True
    )
    yield strategist


# use this if you need to deploy the vault
# @pytest.fixture(scope="function")
# def vault(pm, gov, rewards, guardian, management, token, chain):
#     Vault = pm(config["dependencies"][0]).Vault
#     vault = guardian.deploy(Vault)
#     vault.initialize(token, gov, rewards, "", "", guardian)
#     vault.setDepositLimit(2**256 - 1, {"from": gov})
#     vault.setManagement(management, {"from": gov})
#     chain.sleep(1)
#     yield vault


# use this if your vault is already deployed
@pytest.fixture(scope="function")
def vault():
    vault = Contract(convert.to_address(config["contracts"]["vault"]))
    yield vault


# replace the first value with the name of your strategy
@pytest.fixture(scope="function")
def strategy(vault, Strategy, strategist, gov, usdt, usdc):

    contractAddress = [
        vault.address,
        convert.to_address(config["contracts"]["healthCheck"]),
        convert.to_address(config["contracts"]["usdt"]),
        convert.to_address(config["contracts"]["usdc"]),
        convert.to_address(config["contracts"]["weth"]),
        convert.to_address(config["contracts"]["crv"]),
        convert.to_address(config["contracts"]["router"]),
        convert.to_address(config["contracts"]["gauge"]),
        convert.to_address(config["contracts"]["gaugeFactory"]),
        convert.to_address(config["contracts"]["pool"]),
    ]

    args = [config["strategy"]["name"], contractAddress]

    strategy = Strategy.deploy(*args, {"from": strategist})

    assert strategy.want() == vault.token(), "The token addresses are not the same."

    # The strategy is deployed with USDC being the target token
    assert (
        strategy.targetTokenAddress() == usdc.address
    ), "Strategy not initiated with USDC"

    # params => addStrategy() v0.4.3
    #
    # strategy: address,
    # debtRatio: uint256,
    # minDebtPerHarvest: uint256,
    # maxDebtPerHarvest: uint256,
    # performanceFee: uint256,

    # Only vault.governance() can call addStrategy(). If it's early on in the development
    # process, it's possible that the strategist is still set as governance, as that is the
    # default when creating a strategy.
    if vault.governance() != gov.address:
        vault.acceptGovernance({"from": gov})

    vault.addStrategy(strategy, 10_000, 0, 2**256 - 1, 0, {"from": gov})

    # By default, the `strategist`, `rewards` and `keeper` addresses are initialized to `dev`
    # We update `keeper` and `rewards`. Only the strategist or governance can make this change.
    strategy.setKeeper(
        convert.to_address(config["wallets"]["keeper"]), {"from": strategist}
    )

    # Only the strategist can make this change.
    strategy.setRewards(
        convert.to_address(config["wallets"]["rewards"]), {"from": strategist}
    )

    yield strategy


# use this if your strategy is already deployed
# @pytest.fixture(scope="function")
# def strategy():
#     # parameters for this are: strategy, vault, max deposit, minTimePerInvest, slippage protection (10000 = 100% slippage allowed),
#     strategy = Contract("0xC1810aa7F733269C39D640f240555d0A4ebF4264")
#     yield strategy
