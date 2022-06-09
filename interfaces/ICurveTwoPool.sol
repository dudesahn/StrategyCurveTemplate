// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.6.12;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";

interface ICurveGauge is IERC20 {
    /// @notice Deposit `_value` LP tokens for `msg.sender` without claiming pending rewards (if any)
    /// @param _value Number of LP tokens to deposit
    function deposit(uint256 _value) external;

    /// @notice Withdraw `_value` LP tokens without claiming pending rewards (if any)
    /// @param _value Number of LP tokens to withdraw
    function withdraw(uint256 _value) external;

    /// @notice Get the number of claimable tokens per user
    /// @dev This function should be manually changed to "view" in the ABI
    /// @return uint256 number of claimable tokens per user
    function claimable_tokens(address addr) external returns (uint256);

    function factory() external view returns (address);

    function inflation_rate(uint256) external view returns (uint256);

    function reward_count() external view returns (uint256);
}

interface ICurveGaugeFactory {
    function mint(address _gauge) external;
}

interface ICurvePool is IERC20 {
    // 2CRV pool relies on 2 tokens. Vyper does not yet support dynamic arrays so that we need to
    // hard-code '2' for all the relevant functions in this interface.

    /// @notice Deposit coins into the pool
    /// @param _amounts List of amounts of coins to deposit
    /// @param _min_mint_amount Minimum amount of LP tokens to mint from the deposit
    /// @return Amount of LP tokens received by depositing
    function add_liquidity(
        uint256[2] calldata _amounts,
        uint256 _min_mint_amount
    ) external returns (uint256);
}
