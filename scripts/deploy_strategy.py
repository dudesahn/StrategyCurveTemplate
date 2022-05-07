from brownie import StrategyCurveTwoPool, accounts, config, Contract, convert
from scripts import activeNetwork
import click


def main():

    vaultAddress = convert.to_address(config["contracts"]["vault"])

    print(f"You are deploying the strategy to the '{activeNetwork}' network")
    dev = accounts.load(click.prompt("Account", type=click.Choice(accounts.load())))
    print(f"You are using: 'dev' [{dev.address}]")

    apiVersion = config["dependencies"][0].split("@")[-1]

    # Vault contract created with './deploy_vault.py'
    vault = Contract(vaultAddress, owner=dev)

    # strategy API version must align with vault version
    assert vault.apiVersion() == apiVersion

    print(
        f"""
    Strategy Parameters

       api: {apiVersion}
     token: {vault.token()}
      name: '{vault.name()}'
    symbol: '{vault.symbol()}'
    """
    )

    publish_source = click.confirm("Verify source on arbiscan?")

    args = [
        vault.address,
        config["strategy"]["name"],
        convert.to_address(config["contracts"]["usdt"]),
        convert.to_address(config["contracts"]["usdc"]),
        convert.to_address(config["contracts"]["healthCheck"]),
        convert.to_address(config["contracts"]["gauge"]),
        convert.to_address(config["contracts"]["pool"]),
        convert.to_address(config["contracts"]["weth"]),
        convert.to_address(config["contracts"]["crv"]),
        convert.to_address(config["contracts"]["router"]),
    ]

    strategy = StrategyCurveTwoPool.deploy(
        *args, {"from": dev}, publish_source=publish_source
    )

    # By default, the `strategist`, `rewards` and `keeper` addresses are initialized to `dev`
    # We update `keeper` and `rewards`. Only the strategist or governance can make this change.
    strategy.setKeeper(convert.to_address(config["wallets"]["keeper"]), {"from": dev})

    # Only the strategist can make this change.
    strategy.setRewards(convert.to_address(config["wallets"]["rewards"]), {"from": dev})

    print(f"Strategy created at {strategy.address}")
