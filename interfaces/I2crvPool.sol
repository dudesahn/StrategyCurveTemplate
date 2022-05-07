// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.6.12;
pragma experimental ABIEncoderV2;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";

interface I2crvPool is IERC20 {
  // 2CRV pool relies on 2 tokens. Vyper does not yet support dynamic arrays so that we need to
  // hard-code '2' for all the relevant functions in this interface.

  /// @notice The current virtual price of the pool LP token
  /// @dev Useful for calculating profits
  /// @return LP token virtual price normalized to 1e18
  function get_virtual_price() external view returns (uint256);

  /// @notice Calculate addition or reduction in token supply from a deposit or withdrawal
  /// @dev This calculation accounts for slippage, but not fees. Needed to prevent front-running, not for precise calculations!
  /// @param _amounts Amount of each coin being deposited
  /// @param _is_deposit set True for deposits, False for withdrawals
  /// @return Expected amount of LP tokens received
  function calc_token_amount(uint256[2] calldata _amounts, bool _is_deposit)
    external
    view
    returns (uint256);

  /// @notice Deposit coins into the pool
  /// @param _amounts List of amounts of coins to deposit
  /// @param _min_mint_amount Minimum amount of LP tokens to mint from the deposit
  /// @return Amount of LP tokens received by depositing
  function add_liquidity(uint256[2] calldata _amounts, uint256 _min_mint_amount)
    external
    returns (uint256);

  /// @notice Withdraw coins from the pool
  /// @dev Withdrawal amounts are based on current deposit ratios
  /// @param _burn_amount Quantity of LP tokens to burn in the withdrawal
  /// @param _min_amounts Minimum amounts of underlying coins to receive
  /// @param _receiver Address that receives the withdrawn coins
  /// @return List of amounts of coins that were withdrawn
  function remove_liquidity(
    uint256 _burn_amount,
    uint256[2] calldata _min_amounts,
    address _receiver
  ) external returns (uint256[2] calldata);

  /// @notice Withdraw coins from the pool in an imbalanced amount
  /// @param _amounts List of amounts of underlying coins to withdraw
  /// @param _max_burn_amount Maximum amount of LP token to burn in the withdrawal
  /// @param _receiver Address that receives the withdrawn coins
  /// @return Actual amount of the LP token burned in the withdrawal
  function remove_liquidity_imbalance(
    uint256[2] calldata _amounts,
    uint256 _max_burn_amount,
    address _receiver
  ) external returns (uint256);

  /// @notice Calculate the amount received when withdrawing a single coin
  /// @param _burn_amount Amount of LP tokens to burn in the withdrawal
  /// @param i Index value of the coin to withdraw
  /// @return Amount of coin received
  function calc_withdraw_one_coin(uint256 _burn_amount, int128 i)
    external
    view
    returns (uint256);

  /// @notice Withdraw a single coin from the pool
  /// @param _burn_amount Amount of LP tokens to burn in the withdrawal
  /// @param i Index value of the coin to withdraw
  /// @param _min_received Minimum amount of coin to receive
  /// @param _receiver Address that receives the withdrawn coins
  /// @return Amount of coin received
  function remove_liquidity_one_coin(
    uint256 _burn_amount,
    int128 i,
    uint256 _min_received,
    address _receiver
  ) external returns (uint256);
}
