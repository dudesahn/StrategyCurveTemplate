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
    whale = accounts.at("0x7d6fAdb02e70bfb6325cFD6Ec5605e552115AA76", force=True)
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


# Uniswap V3 router
@pytest.fixture(scope="module")
def router():
    # this should be the address of the curve deposit token
    router = interface.ISwapRouter("0xE592427A0AEce92De3Edee1F18E0157C05861564")
    yield router


# gauge for the curve pool
@pytest.fixture(scope="module")
def gauge():
    # this should be the address of the curve deposit token
    gauge = interface.ICurveGauge("0xCE5F24B7A95e9cBa7df4B54E911B4A3Dc8CDAf6f")
    yield gauge


# gauge factory for the curve gauge
@pytest.fixture(scope="module")
def gaugeFactory():
    # this should be the address of the curve deposit token
    gaugeFactory = interface.ICurveGaugeFactory(
        "0xabC000d88f23Bb45525E447528DBF656A9D55bf5"
    )
    yield gaugeFactory


# curve deposit pool
@pytest.fixture(scope="module")
def pool():
    pool = interface.ICurvePool("0x7f90122BF0700F9E7e1F688fe926940E8839F353")
    yield pool


# Define relevant tokens and contracts in this section
@pytest.fixture(scope="module")
def token():
    # this should be the address of the ERC-20 used by the strategy/vault.
    # note that the pool is tokenized so the address is the same as above.
    token = interface.ERC20("0x7f90122BF0700F9E7e1F688fe926940E8839F353")
    yield token


@pytest.fixture(scope="module")
def usdc():
    usdc = interface.ERC20("0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8")
    yield usdc


@pytest.fixture(scope="module")
def usdt():
    usdt = interface.ERC20("0xFd086bC7CD5C481DCC9C85ebE478A1C0b69FCbb9")
    yield usdt


@pytest.fixture(scope="module")
def dai():
    # used to test strategy.sweep()
    dai = interface.ERC20("0xDA10009cBd5D07dd0CeCc66161FC93D7c9000da1")
    yield dai


@pytest.fixture(scope="module")
def crv():
    # this should be the address of the ERC-20 rewarded by the gauge, by staking
    # the want token.
    crv = interface.ERC20("0x11cDb42B0EB46D95f990BeDD4695A6e3fA034978")
    yield crv


@pytest.fixture(scope="module")
def weth():
    weth = interface.ERC20("0x82aF49447D8a07e3bd95BD0d56f35241523fBab1")
    yield weth


@pytest.fixture(scope="function")
def other_vault_strategy():
    # used to test strategy.migrate()
    yield Contract("0x19e70E3195fEC1A33745D9260Bf26c3f915Bb0CC")


@pytest.fixture(scope="module")
def healthCheck():
    healthCheck = Contract("0x32059ccE723b4DD15dD5cb2a5187f814e6c470bC")
    yield healthCheck


# Define any accounts in this section
# for live testing, governance is the strategist MS; we will update this before we endorse
# normal gov is ychad, 0xFEB4acf3df3cDEA7399794D0869ef76A6EfAff52
@pytest.fixture(scope="module")
def gov(accounts):
    gov = accounts.at("0xb6bc033D34733329971B938fEf32faD7e98E56aD", force=True)
    yield gov


@pytest.fixture(scope="module")
def strategist_ms(accounts):
    # like governance, but better
    strategist_ms = accounts.at(
        convert.to_address("0x6346282DB8323A54E840c6C772B4399C9c655C0d"), force=True
    )
    yield strategist_ms


@pytest.fixture(scope="module")
def keeper(accounts):
    keeper = accounts.at("0x2757AE02F65dB7Ce8CF2b2261c58f07a0170e58e", force=True)
    yield keeper


# Set voter to the strategists multi-sig
@pytest.fixture(scope="function")
def voter():
    yield Contract("0x6346282DB8323A54E840c6C772B4399C9c655C0d")


@pytest.fixture(scope="module")
def rewards(accounts):
    rewards = accounts.at("0x6346282DB8323A54E840c6C772B4399C9c655C0d", force=True)
    yield rewards


@pytest.fixture(scope="module")
def guardian(accounts):
    guardian = accounts.at("0x6346282DB8323A54E840c6C772B4399C9c655C0d", force=True)
    yield guardian


@pytest.fixture(scope="module")
def management(accounts):
    management = accounts.at("0x6346282DB8323A54E840c6C772B4399C9c655C0d", force=True)
    yield management


@pytest.fixture(scope="module")
def strategist(accounts):
    strategist = accounts.at("0x2757AE02F65dB7Ce8CF2b2261c58f07a0170e58e", force=True)
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
    vault = Contract("0x49448d2B94fb9C4e41a30aD8315D32f46004A34b")
    yield vault


# replace the first value with the name of your strategy
@pytest.fixture(scope="function")
def strategy(
    vault,
    Strategy,
    strategist,
    healthCheck,
    keeper,
    rewards,
    gov,
    usdt,
    usdc,
):

    strategy = Strategy.deploy(
        vault.address, config["strategy"]["name"], {"from": strategist}
    )

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

    yield strategy


# use this if your strategy is already deployed
# @pytest.fixture(scope="function")
# def strategy():
#     # parameters for this are: strategy, vault, max deposit, minTimePerInvest, slippage protection (10000 = 100% slippage allowed),
#     strategy = Contract("0xC1810aa7F733269C39D640f240555d0A4ebF4264")
#     yield strategy
