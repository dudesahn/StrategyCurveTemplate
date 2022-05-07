# May, 2022
# The script compares gas cost of uniswap's V3 swap implementations in mainnet and arbitrum.
# We found out that SwapRouter is significantly more gas-efficient.

from brownie import accounts, config, chain, convert, interface
from eth_abi.packed import encode_abi_packed

# arbitrum
crv_whale = accounts.at(convert.to_address(config["wallets"]["crv_whale"]), True)
# mainnet
# crv_whale = accounts.at("0x7a16fF8270133F063aAb6C9977183D9e72835428", True)

crv_amount = 10_000 * 10**18

# arbitrum
crv = interface.ERC20(convert.to_address(config["contracts"]["crv"]))
# mainnet
# crv = interface.ERC20("0xD533a949740bb3306d119CC777fa900bA034cd52")

assert crv.balanceOf(crv_whale) >= crv_amount * 2  # we'll do the same swap twice

router = interface.ISwapRouter(config["contracts"]["router"])
routerV2 = interface.ISwapRouterV2(config["contracts"]["routerV2"])

crv.approve(router, 2**256 - 1, {"from": crv_whale})
crv.approve(routerV2, 2**256 - 1, {"from": crv_whale})

# arbitrum 'path'
path = encode_abi_packed(
    ["address", "uint24", "address", "uint24", "address"],
    [
        crv.address,
        3000,
        convert.to_address(config["contracts"]["weth"]),
        500,
        convert.to_address(config["contracts"]["usdt"]),
    ],
).hex()

# mainnet 'path'
# path = encode_abi_packed(
#     ["address", "uint24", "address", "uint24", "address"],
#     [
#         crv.address,
#         3000,
#         convert.to_address("0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2"),
#         500,
#         convert.to_address("0xdAC17F958D2ee523a2206206994597C13D831ec7"),
#     ],
# ).hex()

tx_v1 = router.exactInput(
    (path, crv_whale, chain[len(chain) - 1].timestamp + 15, crv_amount, 0),
    {"from": crv_whale},
)

tx_v2 = routerV2.exactInput((path, crv_whale, crv_amount, 0), {"from": crv_whale})

print(
    f"Uniswap V3 router implementation 1 uses {tx_v1.gas_used} of gas, while implementation 2 uses {tx_v2.gas_used} of gas.",
    f"The second implementation is {(tx_v2.gas_used/tx_v1.gas_used-1)*100:,.1f}% more expensive.",
)
