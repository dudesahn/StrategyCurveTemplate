from brownie import accounts, config, chain, convert, interface
from eth_abi.packed import encode_abi_packed

strategist = accounts.at(convert.to_address(config["wallets"]["strategist"]), True)

weth_whale = accounts.at("0x905dfCD5649217c42684f23958568e533C711Aa3", True)

weth_amount = 10 * 10**18

weth = interface.ERC20(config["contracts"]["weth"])

weth.transfer(strategist, weth_amount, {"from": weth_whale})

assert weth.balanceOf(strategist) == weth_amount

router = interface.ISwapRouter(config["contracts"]["router"])

weth.approve(router, 2**256 - 1, {"from": strategist})

path = encode_abi_packed(
    ["address", "uint24", "address"],
    [
        convert.to_address(config["contracts"]["weth"]),
        500,
        convert.to_address(config["contracts"]["usdt"]),
    ],
).hex()

tx = router.exactInput((path, strategist.address, weth_amount, 0), {"from": strategist})

tx.info()
tx.call_trace(True)
tx.events
tx.revert_msg
