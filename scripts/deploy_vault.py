from brownie import Contract, accounts, convert, Wei, network
import click

activeNetwork = network.show_active()

assert "arb" in activeNetwork, f"Strategy meant to be deployed to Arbitrum only."


def main():

    click.echo(f"You are using the '{activeNetwork}' network")
    dev = accounts.load(click.prompt("Account", type=click.Choice(accounts.load())))
    click.echo(f"You are using: 'dev' [{dev.address}]")

    registry = Contract(
        convert.to_address("0x3199437193625DCcD6F9C9e98BDf93582200Eb1f"), owner=dev
    )

    # 2CRV pool in Arbitrum
    token = Contract(convert.to_address("0x7f90122BF0700F9E7e1F688fe926940E8839F353"))

    name = f"{token.symbol()} yVault"
    symbol = f"yv{token.symbol()}"

    releaseDelta = 0  # uses latest release of the vault template

    args = [
        token.address,
        dev.address,
        convert.to_address("0x6346282DB8323A54E840c6C772B4399C9c655C0d"),
        convert.to_address("0x1DEb47dCC9a35AD454Bf7f0fCDb03c09792C08c1"),
        name,
        symbol,
        releaseDelta,
    ]

    txnReceipt = registry.newExperimentalVault(*args)

    vaultAddress = txnReceipt.events["NewExperimentalVault"]["vault"]

    print(f"Experimental Vault deployed at {vaultAddress}")

    vault = Contract(vaultAddress, owner=dev)

    vault.setDepositLimit(Wei("50_000 ether"))
    vault.setManagement(
        convert.to_address("0x6346282DB8323A54E840c6C772B4399C9c655C0d")
    )
    vault.setPerformanceFee(2000)
    vault.setGovernance(
        convert.to_address("0xb6bc033D34733329971B938fEf32faD7e98E56aD")
    )
