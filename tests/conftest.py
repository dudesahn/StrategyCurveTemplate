import pytest
from brownie import config, Contract, interface

# Snapshots the chain before each test and reverts after test completion.
@pytest.fixture(autouse=True)
def isolation(fn_isolation):
    pass


@pytest.fixture(scope="module")
def whale(accounts):
    # Totally in it for the tech
    # Update this with a large holder of your want token (the largest EOA holder of LP)
    whale = accounts.at("0xA86D37706162B45ABB83C8C93d380CFE5cD472Ed", force=True)
    yield whale


# this is the amount of funds we have our whale deposit. adjust this as needed based on their wallet balance
@pytest.fixture(scope="module")
def amount(token, whale):
    amount = token.balanceOf(whale) // 2
    yield amount


# this is the name we want to give our strategy
@pytest.fixture(scope="module")
def strategy_name():
    strategy_name = "StrategyCurveTricrypto"
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
    # this should be the address of the convex deposit token
    gauge = "0x555766f3da968ecBefa690Ffd49A2Ac02f47aa5f"
    yield Contract(gauge)


# curve deposit pool
@pytest.fixture(scope="module")
def pool():
    poolAddress = Contract("0x960ea3e3C7FB317332d990873d354E18d7645590")
    yield poolAddress


# Define relevant tokens and contracts in this section
@pytest.fixture(scope="module")
def token():
    # this should be the address of the ERC-20 used by the strategy/vault
    token_address = "0x8e0B8c8BB9db49a46697F3a5Bb8A308e744821D2"
    yield Contract(token_address)


@pytest.fixture(scope="module")
def crv():
    # this should be the address of the ERC-20 used by the strategy/vault
    crv_address = "0x11cDb42B0EB46D95f990BeDD4695A6e3fA034978"
    yield interface.IERC20(crv_address)


# Only worry about changing things above this line
# ----------------------------------------------------------------------- #
# FOR NOW THIS IS DAI, since SMS isn't verified on dumb arbiscan
@pytest.fixture(scope="function")
def voter():
    yield Contract("0xDA10009cBd5D07dd0CeCc66161FC93D7c9000da1")


@pytest.fixture(scope="function")
def dai():
    yield Contract("0xDA10009cBd5D07dd0CeCc66161FC93D7c9000da1")


@pytest.fixture(scope="function")
def other_vault_strategy():
    yield Contract("0xDA10009cBd5D07dd0CeCc66161FC93D7c9000da1")


# only applicable if you are migrating an existing strategy (i.e., you are not
# deploying a brand new one). This strat is using an old version of a curve gauge
@pytest.fixture(scope="module")
def strategy_to_migrate_from():
    yield Contract("0x19e70E3195fEC1A33745D9260Bf26c3f915Bb0CC")


@pytest.fixture(scope="module")
def healthCheck():
    yield Contract("0x32059ccE723b4DD15dD5cb2a5187f814e6c470bC")


# zero address
@pytest.fixture(scope="module")
def zero_address():
    zero_address = "0x0000000000000000000000000000000000000000"
    yield zero_address


# Define any accounts in this section
# for live testing, governance is the strategist MS; we will update this before we endorse
# normal gov is ychad, 0xFEB4acf3df3cDEA7399794D0869ef76A6EfAff52
@pytest.fixture(scope="module")
def gov(accounts):
    yield accounts.at("0xb6bc033D34733329971B938fEf32faD7e98E56aD", force=True)


@pytest.fixture(scope="module")
def strategist_ms(accounts):
    # like governance, but better
    yield accounts.at("0x72a34AbafAB09b15E7191822A679f28E067C4a16", force=True)


@pytest.fixture(scope="module")
def keeper(accounts):
    yield accounts.at("0xBedf3Cf16ba1FcE6c3B751903Cf77E51d51E05b8", force=True)


@pytest.fixture(scope="module")
def rewards(accounts):
    yield accounts.at("0xBedf3Cf16ba1FcE6c3B751903Cf77E51d51E05b8", force=True)


@pytest.fixture(scope="module")
def guardian(accounts):
    yield accounts[2]


@pytest.fixture(scope="module")
def management(accounts):
    yield accounts[3]


@pytest.fixture(scope="module")
def strategist(accounts):
    yield accounts.at("0xBedf3Cf16ba1FcE6c3B751903Cf77E51d51E05b8", force=True)


# # list any existing strategies here
# @pytest.fixture(scope="module")
# def LiveStrategy_1():
#     yield Contract("0xC1810aa7F733269C39D640f240555d0A4ebF4264")


# use this if you need to deploy the vault
@pytest.fixture(scope="function")
def vault(pm, gov, rewards, guardian, management, token, chain):
    Vault = pm(config["dependencies"][0]).Vault
    vault = guardian.deploy(Vault)
    vault.initialize(token, gov, rewards, "", "", guardian)
    vault.setDepositLimit(2 ** 256 - 1, {"from": gov})
    vault.setManagement(management, {"from": gov})
    chain.sleep(1)
    yield vault


@pytest.fixture(scope="function")
def vaultDeployed():
    vaultDeployed = Contract("0x239e14A19DFF93a17339DCC444f74406C17f8E67")
    yield vaultDeployed


# replace the first value with the name of your strategy
@pytest.fixture(scope="function")
def strategy(
    StrategyCurveTricrypto,
    strategist,
    keeper,
    vault,
    gov,
    guardian,
    token,
    healthCheck,
    chain,
    pool,
    strategy_name,
    gauge,
    strategist_ms,
):
    # make sure to include all constructor parameters needed here
    strategy = strategist.deploy(
        StrategyCurveTricrypto,
        vault,
        strategy_name,
    )
    strategy.setKeeper(keeper, {"from": gov})
    # set our management fee to zero so it doesn't mess with our profit checking
    vault.setManagementFee(0, {"from": gov})
    # add our new strategy
    vault.addStrategy(strategy, 10_000, 0, 2 ** 256 - 1, 1_000, {"from": gov})
    strategy.setHealthCheck(healthCheck, {"from": gov})
    strategy.setDoHealthCheck(True, {"from": gov})
    chain.sleep(1)
    strategy.harvest({"from": gov})
    chain.sleep(1)
    yield strategy


# use this if your strategy is already deployed
# @pytest.fixture(scope="function")
# def strategy():
#     # parameters for this are: strategy, vault, max deposit, minTimePerInvest, slippage protection (10000 = 100% slippage allowed),
#     strategy = Contract("0xC1810aa7F733269C39D640f240555d0A4ebF4264")
#     yield strategy
