# May, 2022
# The script compares gas cost of uniswap's V3 swap implementations in mainnet and arbitrum.
# We found out that SwapRouter is significantly more gas-efficient.

from brownie import accounts, chain, convert, interface
from eth_abi.packed import encode_abi_packed

# arbitrum
crv_whale = accounts.at("0x4A65e76bE1b4e8dd6eF618277Fa55200e3F8F20a", True)
# mainnet
# crv_whale = accounts.at("0x7a16fF8270133F063aAb6C9977183D9e72835428", True)

crv_amount = 10_000 * 10**18

# arbitrum
crv = interface.ERC20("0x11cDb42B0EB46D95f990BeDD4695A6e3fA034978")
# mainnet
# crv = interface.ERC20("0xD533a949740bb3306d119CC777fa900bA034cd52")

assert crv.balanceOf(crv_whale) >= crv_amount * 2  # we'll do the same swap twice

router = interface.ISwapRouter("0xE592427A0AEce92De3Edee1F18E0157C05861564")
routerV2 = interface.ISwapRouterV2("0x68b3465833fb72A70ecDF485E0e4C7bD8665Fc45")

crv.approve(router, 2**256 - 1, {"from": crv_whale})
crv.approve(routerV2, 2**256 - 1, {"from": crv_whale})

# arbitrum 'path'
path = encode_abi_packed(
    ["address", "uint24", "address", "uint24", "address"],
    [
        crv.address,
        3000,
        "0x82aF49447D8a07e3bd95BD0d56f35241523fBab1",  # weth
        500,
        "0xFd086bC7CD5C481DCC9C85ebE478A1C0b69FCbb9",  # usdt
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
