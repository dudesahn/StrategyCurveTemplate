def test_vault_deposit(
    token,
    vault,
    whale,
    amount,
):
    ## deposit to the vault after approving
    whaleBalance = token.balanceOf(whale)

    assert (
        whaleBalance > amount
    ), f"Whale might no longer hold a large position in {token.symbol()}"

    print(
        f"Whale depositing {amount / (10 ** token.decimals()):,.2f} {token.symbol} into the vault..."
    )

    token.approve(vault, 2**256 - 1, {"from": whale})
    tx = vault.deposit(amount, {"from": whale})

    # The next asserts are only true if this is the very first deposit into the vault
    assert vault.balanceOf(whale) == amount
    assert vault.totalAssets() == amount

    # number of vault shares supplied
    assert vault.totalSupply() == amount
    assert vault.totalSupply() == tx.return_value, "The total number of shares issued by the vault is not equal to the number of shares issued to the whale"

    print("Done!")
