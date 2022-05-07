// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.6.12;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";

interface I2crvGauge is IERC20 {
  /// @notice Get the number of claimable reward tokens for a user
  /// @dev This call does not consider pending claimable amount in `reward_contract`.
  ///  Off-chain callers should instead use `claimable_rewards_write` as a
  ///  view method.
  /// @param _addr Account to get reward amount for
  /// @param _token Token to get reward amount for
  /// @return uint256 Claimable reward token amount
  function claimable_reward(address _addr, address _token)
    external
    view
    returns (uint256);

  /// @notice Claim available reward tokens for `msg.sender`
  function claim_rewards() external;

  /// @notice Deposit `_value` LP tokens for `msg.sender` without claiming pending rewards (if any)
  /// @param _value Number of LP tokens to deposit
  function deposit(uint256 _value) external;

  /// @notice Withdraw `_value` LP tokens without claiming pending rewards (if any)
  /// @param _value Number of LP tokens to withdraw
  function withdraw(uint256 _value) external;
}
