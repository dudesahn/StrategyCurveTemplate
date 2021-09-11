import pytest
from brownie import config, Wei, Contract

# Snapshots the chain before each test and reverts after test completion.
@pytest.fixture(autouse=True)
def isolation(fn_isolation):
    pass


@pytest.fixture(scope="module")
def whale(accounts):
    # Totally in it for the tech
    # Update this with a large holder of your want token (the largest EOA holder of LP)
    yield accounts.at("0x0ccc815d354860dcC9723B61Ec068190f4aef1a2", force=True)


# this is the amount of funds we have our whale deposit. adjust this as needed based on their wallet balance
@pytest.fixture(scope="module")
def amount():
    amount = 2_000e18
    yield amount


# we need these next two fixtures for deploying our curve strategy, but not for convex. for convex we can pull them programmatically.
# this is the address of our rewards token
@pytest.fixture(scope="module")
def rewards_token():
    yield Contract("0x21be370D5312f44cB42ce377BC9b8a0cEF1A4C83")  # wftm


# Only worry about changing things above this line, unless you want to make changes to the vault or strategy.
# ----------------------------------------------------------------------- #


@pytest.fixture
def trade_factory():
    yield Contract("0x382ec4342775607ad64949bC26402b5F8CD651fe")


@pytest.fixture
def yswapper_safe():
    yield Contract("0x9f2A061d6fEF20ad3A656e23fd9C814b75fd5803")


@pytest.fixture
def async_spookyswap():
    yield Contract("0x974eaa0D52ef53AE89B7f0b7A554ADAB2446b389")


# Define relevant tokens and contracts in this section
@pytest.fixture(scope="module")
def token():
    yield Contract("0x27E611FD27b276ACbd5Ffd632E5eAEBEC9761E40")


# gauge for the curve pool
@pytest.fixture(scope="module")
def gauge():
    yield Contract("0x8866414733F22295b7563f9C5299715D2D76CAf4")


# curve deposit pool
@pytest.fixture(scope="module")
def pool():
    yield Contract("0x27E611FD27b276ACbd5Ffd632E5eAEBEC9761E40")


# Define any accounts in this section
# for live testing, governance is the strategist MS; we will update this before we endorse
# normal gov is ychad, 0xFEB4acf3df3cDEA7399794D0869ef76A6EfAff52
@pytest.fixture(scope="module")
def gov(accounts):
    yield accounts.at("0xFEB4acf3df3cDEA7399794D0869ef76A6EfAff52", force=True)


@pytest.fixture(scope="module")
def strategist_ms(accounts):
    # like governance, but better
    yield accounts.at("0x16388463d60FFE0661Cf7F1f31a7D658aC790ff7", force=True)


@pytest.fixture(scope="module")
def keeper(accounts):
    yield accounts.at("0xBedf3Cf16ba1FcE6c3B751903Cf77E51d51E05b8", force=True)


@pytest.fixture(scope="module")
def rewards(accounts):
    yield accounts.at("0x8Ef63b525fceF7f8662D98F77f5C9A86ae7dFE09", force=True)


@pytest.fixture(scope="module")
def guardian(accounts):
    yield accounts[2]


@pytest.fixture(scope="module")
def management(accounts):
    yield accounts[3]


@pytest.fixture(scope="module")
def strategist(accounts):
    yield accounts.at("0xBedf3Cf16ba1FcE6c3B751903Cf77E51d51E05b8", force=True)


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


# replace the first value with the name of your strategy
@pytest.fixture(scope="function")
def strategy(
    StrategyCurve2Crv,
    vault,
    trade_factory,
    strategist,
    keeper,
    gov,
    pool,
    gauge,
    rewards_token,
    yswapper_safe,
    async_spookyswap,
):
    # make sure to include all constructor parameters needed here
    strategy = strategist.deploy(
        StrategyCurve2Crv,
        vault,
        trade_factory,
        pool,
        gauge,
        True,
        rewards_token,
        "2crv",
    )
    strategy.setKeeper(keeper, {"from": gov})
    # set our management fee to zero so it doesn't mess with our profit checking
    vault.setManagementFee(0, {"from": gov})
    vault.addStrategy(strategy, 10_000, 0, 2 ** 256 - 1, 1_000, {"from": gov})

    # yswap first setup
    trade_factory.grantRole(trade_factory.STRATEGY(), strategy, {"from": yswapper_safe})
    trade_factory.setStrategyAsyncSwapper(
        strategy, async_spookyswap, {"from": yswapper_safe}
    )

    yield strategy


@pytest.fixture(scope="module")
def ymechanic(accounts):
    yield accounts.at("0xB82193725471dC7bfaAB1a3AB93c7b42963F3265", True)
