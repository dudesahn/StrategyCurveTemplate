from brownie import Contract, accounts, config, convert, Wei, network
import click

activeNetwork = network.show_active()

assert "arb" in activeNetwork, f"Strategy meant to be deployed to Arbitrum only."


def main():

    click.echo(f"You are using the '{activeNetwork}' network")
    dev = accounts.load(click.prompt("Account", type=click.Choice(accounts.load())))
    click.echo(f"You are using: 'dev' [{dev.address}]")

    registry = Contract(convert.to_address(config["contracts"]["registry"]), owner=dev)

    # 2CRV pool in Arbitrum
    token = Contract(convert.to_address(config["contracts"]["token"]))

    name = f"{token.symbol()} yVault"
    symbol = f"yv{token.symbol()}"

    releaseDelta = 0  # uses latest release of the vault template

    args = [
        token.address,
        dev.address,
        convert.to_address(config["wallets"]["guardian"]),
        convert.to_address(config["wallets"]["rewards"]),
        name,
        symbol,
        releaseDelta,
    ]

    txnReceipt = registry.newExperimentalVault(*args)

    vaultAddress = txnReceipt.events["NewExperimentalVault"]["vault"]

    print(f"Experimental Vault deployed at {vaultAddress}")

    vault = Contract(vaultAddress, owner=dev)

    vault.setDepositLimit(Wei("50_000 ether"))
    vault.setManagement(convert.to_address(config["wallets"]["strategy_ms"]))
    vault.setPerformanceFee(2000)
    vault.setGovernance(convert.to_address(config["wallets"]["governance"]))
