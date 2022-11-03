// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.15;
pragma experimental ABIEncoderV2;

// These are the core Yearn libraries
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";

import "./interfaces/curve.sol";
import "./interfaces/yearn.sol";
import {IUniswapV3Router01} from "./interfaces/uniswap.sol";
import "@yearnvaults/contracts/BaseStrategy.sol";

interface IWeth {
    function withdraw(uint256 wad) external;
}

abstract contract StrategyCurveBase is BaseStrategy {

    /* ========== STATE VARIABLES ========== */
    // these should stay the same across different wants.

    // curve infrastructure contracts
    IGauge public gauge; // Curve gauge contract, most are tokenized, held by Yearn's voter

    // keepCRV stuff
    uint256 public keepCRV; // the percentage of CRV we re-lock for boost (in basis points)
    address public constant voter = 0xea3a15df68fCdBE44Fdb0DB675B2b3A14a148b26; // Optimism SMS
    uint256 internal constant FEE_DENOMINATOR = 10000; // this means all of our fee values are in basis points

    // Swap stuff
    address internal constant uniswap =
        0xE592427A0AEce92De3Edee1F18E0157C05861564; // we use this to sell our bonus token

    IERC20 internal constant crv =
        IERC20(0x0994206dfE8De6Ec6920FF4D779B0d950605Fb53);
    IERC20 internal constant weth =
        IERC20(0x4200000000000000000000000000000000000006);
    IMinter public constant mintr = IMinter(0xabC000d88f23Bb45525E447528DBF656A9D55bf5);

    string internal stratName;

    /* ========== CONSTRUCTOR ========== */

    constructor(address _vault) BaseStrategy(_vault) {}

    /* ========== VIEWS ========== */

    function name() external view override returns (string memory) {
        return stratName;
    }

    ///@notice How much want we have staked in Curve's gauge
    function stakedBalance() public view returns (uint256) {
        return IERC20(address(gauge)).balanceOf(address(this));
    }

    ///@notice Balance of want sitting in our strategy
    function balanceOfWant() public view returns (uint256) {
        return want.balanceOf(address(this));
    }

    function estimatedTotalAssets() public view override returns (uint256) {
        return balanceOfWant() + stakedBalance();
    }

    /* ========== MUTATIVE FUNCTIONS ========== */

    function adjustPosition(uint256 _debtOutstanding) internal override {
        if (emergencyExit) {
            return;
        }
        // Deposit to the gauge if we have any
        uint256 _toInvest = balanceOfWant();
        if (_toInvest > 0) {
            gauge.deposit(_toInvest);
        }
    }

    function liquidatePosition(uint256 _amountNeeded)
        internal
        override
        returns (uint256 _liquidatedAmount, uint256 _loss)
    {
        uint256 _wantBal = balanceOfWant();
        if (_amountNeeded > _wantBal) {
            // check if we have enough free funds to cover the withdrawal
            uint256 _stakedBal = stakedBalance();
            if (_stakedBal > 0) {
                gauge.withdraw(
                    Math.min(_stakedBal, _amountNeeded - _wantBal)
                );
            }
            uint256 _withdrawnBal = balanceOfWant();
            _liquidatedAmount = Math.min(_amountNeeded, _withdrawnBal);
            _loss = _amountNeeded - _liquidatedAmount;
        } else {
            // we have enough balance to cover the liquidation available
            return (_amountNeeded, 0);
        }
    }

    // fire sale, get rid of it all!
    function liquidateAllPositions() internal override returns (uint256) {
        uint256 _stakedBal = stakedBalance();
        if (_stakedBal > 0) {
            // don't bother withdrawing zero
            gauge.withdraw(_stakedBal);
        }
        return balanceOfWant();
    }

    function protectedTokens()
        internal
        view
        override
        returns (address[] memory)
    {}

    /* ========== SETTERS ========== */

    // These functions are useful for setting parameters of the strategy that may need to be adjusted.

    // Set the amount of CRV to be locked in Yearn's veCRV voter from each harvest. Default is 10%.
    function setKeepCRV(uint256 _keepCRV) external onlyVaultManagers {
        require(_keepCRV <= 10_000);
        keepCRV = _keepCRV;
    }

}

contract StrategyCurveEthPoolsClonable is StrategyCurveBase {
    using SafeERC20 for IERC20;
    /* ========== STATE VARIABLES ========== */
    // these will likely change across different wants.

    // Curve stuff
    ICurveFi public curve; ///@notice This is our curve pool specific to this vault
    uint24 public feeCRVETH;
    uint24 public feeOPETH;

    // rewards token info. we can have more than 1 reward token but this is rare, so we don't include this in the template
    IERC20 public rewardsToken;
    bool public hasRewards;

    // check for cloning
    bool internal isOriginal = true;

    /* ========== CONSTRUCTOR ========== */

    constructor(
        address _vault,
        address _gauge,
        address _curvePool,
        string memory _name
    ) StrategyCurveBase(_vault) {
        _initializeStrat(_gauge, _curvePool, _name);
    }

    /* ========== CLONING ========== */

    event Cloned(address indexed clone);

    // we use this to clone our original strategy to other vaults
    function cloneCurveOldEth(
        address _vault,
        address _strategist,
        address _rewards,
        address _keeper,
        address _gauge,
        address _curvePool,
        string memory _name
    ) external returns (address payable newStrategy) {
        require(isOriginal);
        // Copied from https://github.com/optionality/clone-factory/blob/master/contracts/CloneFactory.sol
        bytes20 addressBytes = bytes20(address(this));
        assembly {
            // EIP-1167 bytecode
            let clone_code := mload(0x40)
            mstore(
                clone_code,
                0x3d602d80600a3d3981f3363d3d373d3d3d363d73000000000000000000000000
            )
            mstore(add(clone_code, 0x14), addressBytes)
            mstore(
                add(clone_code, 0x28),
                0x5af43d82803e903d91602b57fd5bf30000000000000000000000000000000000
            )
            newStrategy := create(0, clone_code, 0x37)
        }

        StrategyCurveEthPoolsClonable(newStrategy).initialize(
            _vault,
            _strategist,
            _rewards,
            _keeper,
            _gauge,
            _curvePool,
            _name
        );

        emit Cloned(newStrategy);
    }

    // this will only be called by the clone function above
    function initialize(
        address _vault,
        address _strategist,
        address _rewards,
        address _keeper,
        address _gauge,
        address _curvePool,
        string memory _name
    ) public {
        _initialize(_vault, _strategist, _rewards, _keeper);
        _initializeStrat(_gauge, _curvePool, _name);
    }

    // this is called by our original strategy, as well as any clones
    function _initializeStrat(
        address _gauge,
        address _curvePool,
        string memory _name
    ) internal {
        // make sure that we haven't initialized this before
        require(address(curve) == address(0)); // already initialized.

        // You can set these parameters on deployment to whatever you want
        maxReportDelay = 100 days; // 100 days in seconds
        minReportDelay = 21 days; // 21 days in seconds
        healthCheck = 0x3d8F58774611676fd196D26149C71a9142C45296; // health.ychad.eth
        creditThreshold = 500 * 1e18;
        keepCRV = 0; // default of 0%

        // these are our standard approvals. want = Curve LP token
        want.approve(address(_gauge), type(uint256).max);
        crv.approve(address(uniswap), type(uint256).max);

        // this is the pool specific to this vault
        curve = ICurveFi(_curvePool);

        // set our curve gauge contract
        gauge = IGauge(_gauge);

        // set our strategy's name
        stratName = _name;
    }

    /* ========== MUTATIVE FUNCTIONS ========== */

    function setFeeCRVETH(uint24 _newFeeCRVETH) external onlyVaultManagers {
        feeCRVETH = _newFeeCRVETH;
    }

    function setFeeOPETH(uint24 _newFeeOPETH) external onlyVaultManagers {
        feeOPETH = _newFeeOPETH;
    }

    function prepareReturn(uint256 _debtOutstanding)
        internal
        override
        returns (
            uint256 _profit,
            uint256 _loss,
            uint256 _debtPayment
        )
    {
        // if we have anything in the gauge, then harvest CRV from the gauge
        uint256 _stakedBal = stakedBalance();
        uint256 _crvBalance = crv.balanceOf(address(this));
        if (_stakedBal > 0) {
            // Mintr CRV emissions
            mintr.mint(address(gauge));
            _crvBalance = crv.balanceOf(address(this));
            // if we claimed any CRV, then sell it
            if (_crvBalance > 0) {
                // keep some of our CRV to increase our boost
                uint256 _sendToVoter =
                    _crvBalance * keepCRV / FEE_DENOMINATOR;
                if (_sendToVoter > 0) {
                    crv.safeTransfer(voter, _sendToVoter);
                }
                _crvBalance -= _sendToVoter;
            }
        }

        // claim and sell our rewards if we have them
        if (hasRewards) {
            gauge.claim_rewards();
            uint256 _rewardsBalance = rewardsToken.balanceOf(address(this));
            if (_rewardsBalance > 0) {
                _sellTokenToWethUniV3(address(rewardsToken), feeOPETH, _rewardsBalance);
            }
        }

        // do this even if we don't have any CRV, in case we have WETH
        _sell(_crvBalance);

        // deposit our ETH to the pool
        uint256 ethBalance = address(this).balance;
        if (ethBalance > 0) {
            curve.add_liquidity{value: ethBalance}([ethBalance, 0], 0);
        }

        // debtOustanding will only be > 0 in the event of revoking or if we need to rebalance from a withdrawal or lowering the debtRatio
        if (_debtOutstanding > 0) {
            if (_stakedBal > 0) {
                // don't bother withdrawing if we don't have staked funds
                gauge.withdraw(Math.min(_stakedBal, _debtOutstanding));
            }
            uint256 _withdrawnBal = balanceOfWant();
            _debtPayment = Math.min(_debtOutstanding, _withdrawnBal);
        }

        // serious loss should never happen, but if it does (for instance, if Curve is hacked), let's record it accurately
        uint256 assets = estimatedTotalAssets();
        uint256 debt = vault.strategies(address(this)).totalDebt;

        // if assets are greater than debt, things are working great!
        if (assets > debt) {
            _profit = assets - debt;
            uint256 _wantBal = balanceOfWant();
            if (_profit + _debtPayment > _wantBal) {
                // this should only be hit following donations to strategy
                liquidateAllPositions();
            }
        }
        // if assets are less than debt, we are in trouble
        else {
            _loss = debt - assets;
        }

        // we're done harvesting, so reset our trigger if we used it
        forceHarvestTriggerOnce = false;
    }

    function prepareMigration(address _newStrategy) internal override {
        uint256 _stakedBal = stakedBalance();
        if (_stakedBal > 0) {
            gauge.withdraw(_stakedBal);
        }
        crv.safeTransfer(_newStrategy, crv.balanceOf(address(this)));
    }

    // Sells our harvested CRV into the selected output, then unwrap WETH
    function _sell(uint256 _crvAmount) internal {
        if (_crvAmount > 1e17) {
            // don't want to swap dust or we might revert
            _sellTokenToWethUniV3(address(crv), feeCRVETH, _crvAmount);
        }

        uint256 wethBalance = weth.balanceOf(address(this));
        if (wethBalance > 0) {
            IWeth(address(weth)).withdraw(wethBalance);
        }
    }

    // Sells our harvested reward token into the selected output.
    function _sellTokenToWethUniV3(address _tokenIn, uint24 _fee, uint256 _amount) internal {
        IUniswapV3Router01(uniswap).exactInputSingle(
            IUniswapV3Router01.ExactInputSingleParams(
                address(_tokenIn),
                address(weth),
                _fee,
                address(this),
                block.timestamp,
                _amount,
                0,
                0
            )
        );
    }

    /* ========== KEEP3RS ========== */
    // use this to determine when to harvest
    function harvestTrigger(uint256 callCostinEth)
        public
        view
        override
        returns (bool)
    {
        // Should not trigger if strategy is not active (no assets and no debtRatio). This means we don't need to adjust keeper job.
        if (!isActive()) {
            return false;
        }

        StrategyParams memory params = vault.strategies(address(this));
        // harvest no matter what once we reach our maxDelay
        if (block.timestamp - params.lastReport > maxReportDelay) {
            return true;
        }

        // check if the base fee gas price is higher than we allow. if it is, block harvests.
        if (!isBaseFeeAcceptable()) {
            return false;
        }

        // trigger if we want to manually harvest, but only if our gas price is acceptable
        if (forceHarvestTriggerOnce) {
            return true;
        }

        // harvest if we hit our minDelay, but only if our gas price is acceptable
        if (block.timestamp - params.lastReport > minReportDelay) {
            return true;
        }

        // harvest our credit if it's above our threshold
        if (vault.creditAvailable() > creditThreshold) {
            return true;
        }

        // otherwise, we don't harvest
        return false;
    }

    // convert our keeper's eth cost into want, we don't need this anymore since we don't use baseStrategy harvestTrigger
    function ethToWant(uint256 _ethAmount)
        public
        view
        override
        returns (uint256)
    {}

    // include so our contract plays nicely with ether
    receive() external payable {}

    /* ========== SETTERS ========== */

    // These functions are useful for setting parameters of the strategy that may need to be adjusted.

    ///@notice Use to add, update or remove reward token
    // OP token: 0x4200000000000000000000000000000000000042
    function updateRewards(bool _hasRewards, address _rewardsToken)
        external
        onlyGovernance
    {
        // if we already have a rewards token, get rid of it
        if (address(rewardsToken) != address(0)) {
            rewardsToken.approve(uniswap, uint256(0));
        }
        if (_hasRewards == false) {
            hasRewards = false;
            rewardsToken = IERC20(address(0));
        } else {
            // approve, setup our path, and turn on rewards
            rewardsToken = IERC20(_rewardsToken);
            rewardsToken.approve(uniswap, type(uint256).max);
            hasRewards = true;
        }
    }
}
