// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.6.12;
pragma experimental ABIEncoderV2;

interface IGauge {
    function deposit(uint256) external;

    function balanceOf(address) external view returns (uint256);

    function claimable_tokens(address) external returns (uint256);

    function withdraw(uint256) external;
}

interface IGaugeFactory {
    function mint(address _gauge) external;
}

interface ICurveFi {
    function add_liquidity(uint256[3] calldata amounts, uint256 min_mint_amount)
        external
        payable;
}
