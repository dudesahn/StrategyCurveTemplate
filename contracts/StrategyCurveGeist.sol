// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.6.12;
pragma experimental ABIEncoderV2;

// These are the core Yearn libraries
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/math/Math.sol";

import {IGauge, IGaugeFactory, ICurveFi} from "./interfaces/curve.sol";
import {IUniswapV2Router02} from "./interfaces/uniswap.sol";
import {BaseStrategy, StrategyParams} from "@yearnvaults/contracts/BaseStrategy.sol";

abstract contract StrategyCurveBase is BaseStrategy {
    using SafeERC20 for IERC20;
    using Address for address;
    using SafeMath for uint256;

    /* ========== STATE VARIABLES ========== */
    // these should stay the same across different wants.

    // Curve stuff
    IGauge public constant gauge =
        IGauge(0xF7b9c402c4D6c2eDbA04a7a515b53D11B1E9b2cc); // Curve gauge contract, most are tokenized, held by strategy

    IGaugeFactory public constant gaugeFactory =
        IGaugeFactory(0xabC000d88f23Bb45525E447528DBF656A9D55bf5);

    // keepCRV stuff
    uint256 public keepCRV; // the percentage of CRV we re-lock for boost (in basis points)
    uint256 internal constant FEE_DENOMINATOR = 10000; // this means all of our fee values are in basis points

    IERC20 public constant crv =
        IERC20(0x1E4F97b9f9F913c46F1632781732927B9019C68b);
    IERC20 public constant wftm =
        IERC20(0x21be370D5312f44cB42ce377BC9b8a0cEF1A4C83);

    bool internal forceHarvestTriggerOnce; // only set this to true externally when we want to trigger our keepers to harvest for us

    string internal stratName; // set our strategy name here

    /* ========== CONSTRUCTOR ========== */

    constructor(address _vault) public BaseStrategy(_vault) {}

    /* ========== VIEWS ========== */

    function name() external view override returns (string memory) {
        return stratName;
    }

    function stakedBalance() public view returns (uint256) {
        return gauge.balanceOf(address(this));
    }

    function balanceOfWant() public view returns (uint256) {
        return want.balanceOf(address(this));
    }

    function estimatedTotalAssets() public view override returns (uint256) {
        return balanceOfWant().add(stakedBalance());
    }

    /* ========== MUTATIVE FUNCTIONS ========== */
    // these should stay the same across different wants.

    function adjustPosition(uint256 _debtOutstanding) internal override {
        if (emergencyExit) {
            return;
        }
        // Send all of our LP tokens to deposit to the gauge if we have any
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
                    Math.min(_stakedBal, _amountNeeded.sub(_wantBal))
                );
            }
            uint256 _withdrawnBal = balanceOfWant();
            _liquidatedAmount = Math.min(_amountNeeded, _withdrawnBal);
            _loss = _amountNeeded.sub(_liquidatedAmount);
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

    function _claimRewards() internal {
        // Claims any pending CRV
        //
        // Mints claimable CRV from the factory gauge. Reward tokens are sent to `msg.sender`
        gaugeFactory.mint(address(gauge));

        // harvest third-party rewards from the gauge, if any
        gauge.claim_rewards();
    }

    function claimRewards() external onlyVaultManagers {
        _claimRewards();
    }

    function prepareMigration(address _newStrategy) internal override {
        // Withdraw LP tokens from the gauge. The transfer to the new strategy is done
        // by migrate() in BaseStrategy.sol
        uint256 _stakedBal = stakedBalance();
        if (_stakedBal > 0) {
            gauge.withdraw(_stakedBal);
        }
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
    function setKeepCRV(uint256 _keepCRV) external onlyAuthorized {
        require(_keepCRV <= 10_000);
        keepCRV = _keepCRV;
    }

    // This allows us to manually harvest with our keeper as needed
    function setForceHarvestTriggerOnce(bool _forceHarvestTriggerOnce)
        external
        onlyAuthorized
    {
        forceHarvestTriggerOnce = _forceHarvestTriggerOnce;
    }
}

contract StrategyCurveGeist is StrategyCurveBase {
    /* ========== STATE VARIABLES ========== */
    // these will likely change across different wants.

    // Curve stuff
    ICurveFi public constant curve =
        ICurveFi(0x0fa949783947Bf6c1b171DB13AEACBB488845B3f); // This is our pool specific to this vault.

    // we use these to deposit to our curve pool
    address public targetToken; // this is the token we sell into, DAI, USDC, or fUSDT
    IERC20 public constant usdc =
        IERC20(0x04068DA6C83AFCFA0e13ba15A6696662335D5B75);
    IERC20 public constant dai =
        IERC20(0x8D11eC38a3EB5E956B052f67Da8Bdc9bef8Abf3E);
    IERC20 public constant fusdt =
        IERC20(0x049d68029688eAbF473097a2fC38ef61633A3C7A);
    IERC20 public constant geist =
        IERC20(0xd8321AA83Fb0a4ECd6348D4577431310A6E0814d);
    IUniswapV2Router02 public router =
        IUniswapV2Router02(0xF491e7B69E4244ad4002BC14e878a34207E38c29); // this is the router we swap with, start with spookyswap

    address public constant voter = 0x72a34AbafAB09b15E7191822A679f28E067C4a16; // sms

    /* ========== CONSTRUCTOR ========== */

    constructor(address _vault, string memory _name)
        public
        StrategyCurveBase(_vault)
    {
        // You can set these parameters on deployment to whatever you want
        maxReportDelay = 2 days; // 2 days in seconds
        healthCheck = 0xf13Cd6887C62B5beC145e30c38c4938c5E627fe0; // health.ychad.eth

        // these are our standard approvals. want = Curve LP token
        address spooky = 0xF491e7B69E4244ad4002BC14e878a34207E38c29;
        address spirit = 0x16327E3FbDaCA3bcF7E38F5Af2599D2DDc33aE52;
        want.approve(address(gauge), type(uint256).max);
        crv.approve(spooky, type(uint256).max);
        wftm.approve(spooky, type(uint256).max);
        geist.approve(spooky, type(uint256).max);
        crv.approve(spirit, type(uint256).max);
        wftm.approve(spirit, type(uint256).max);
        geist.approve(spirit, type(uint256).max);

        // set our strategy's name
        stratName = _name;

        // these are our approvals and path specific to this contract
        dai.approve(address(curve), type(uint256).max);
        usdc.approve(address(curve), type(uint256).max);
        fusdt.safeApprove(address(curve), type(uint256).max);

        //'targetToken' is the token with the least impact on the curve pool at the time of deposit
        // or the one with the biggest bonus. 'targetToken' is updated by yearn when granted by
        // market conditions. We start off with usdc.
        targetToken = address(usdc);
    }

    /* ========== MUTATIVE FUNCTIONS ========== */
    // these will likely change across different wants.

    function prepareReturn(uint256 _debtOutstanding)
        internal
        override
        returns (
            uint256 _profit,
            uint256 _loss,
            uint256 _debtPayment
        )
    {
        // Claim and get a fresh snapshot of the strategy's CRV and GEIST balance
        _claimRewards();

        uint256 crvBalance = crv.balanceOf(address(this));
        uint256 wftmBalance = wftm.balanceOf(address(this));
        uint256 geistBalance = geist.balanceOf(address(this));

        // Sell CRV if we have any
        if (crvBalance > 0) {
            // keep some of our CRV to increase our boost
            uint256 sendToVoter = crvBalance.mul(keepCRV).div(FEE_DENOMINATOR);
            if (keepCRV > 0) {
                crv.safeTransfer(voter, sendToVoter);
            }

            // check our balance again after transferring some crv to our voter
            crvBalance = crv.balanceOf(address(this));

            // sell the rest of our CRV
            if (crvBalance > 0) {
                _sellToken(address(crv), crvBalance);
            }
        }
        // sell WFTM if we have any
        if (wftmBalance > 0) {
            _sellToken(address(wftm), wftmBalance);
        }

        // Sell GEIST if we have any
        if (geistBalance > 0) {
            _sellToken(address(geist), geistBalance);
        }

        uint256 daiBalance = dai.balanceOf(address(this));
        uint256 usdcBalance = usdc.balanceOf(address(this));
        uint256 fusdtBalance = fusdt.balanceOf(address(this));

        // deposit our balance to Curve if we have any
        if (daiBalance > 0 || usdcBalance > 0 || fusdtBalance > 0) {
            curve.add_liquidity(
                [daiBalance, usdcBalance, fusdtBalance],
                0,
                true
            );
        }

        // debtOustanding will only be > 0 in the event of revoking or if we need to rebalance from a withdrawal or lowering the debtRatio
        uint256 stakedBal = stakedBalance();
        if (_debtOutstanding > 0) {
            if (stakedBal > 0) {
                // don't bother withdrawing if we don't have staked funds
                gauge.withdraw(Math.min(stakedBal, _debtOutstanding));
            }
            uint256 _withdrawnBal = balanceOfWant();
            _debtPayment = Math.min(_debtOutstanding, _withdrawnBal);
        }

        // serious loss should never happen, but if it does (for instance, if Curve is hacked), let's record it accurately
        uint256 assets = estimatedTotalAssets();
        uint256 debt = vault.strategies(address(this)).totalDebt;

        // if assets are greater than debt, things are working great!
        if (assets > debt) {
            _profit = assets.sub(debt);
            uint256 _wantBal = balanceOfWant();
            if (_profit.add(_debtPayment) > _wantBal) {
                // this should only be hit following donations to strategy followed by a withdrawal
                liquidateAllPositions();
            }
        }
        // if assets are less than debt, we are in trouble
        else {
            _loss = debt.sub(assets);
        }

        // we're done harvesting, so reset our trigger if we used it
        forceHarvestTriggerOnce = false;
    }

    // Sells our CRV, WFTM, or GEIST for our target token
    function _sellToken(address token, uint256 _amount) internal {
        if (token == address(wftm)) {
            address[] memory tokenPath = new address[](2);
            tokenPath[0] = address(wftm);
            tokenPath[1] = address(targetToken);
            IUniswapV2Router02(router).swapExactTokensForTokens(
                _amount,
                uint256(0),
                tokenPath,
                address(this),
                block.timestamp
            );
        } else {
            address[] memory tokenPath = new address[](3);
            tokenPath[0] = address(token);
            tokenPath[1] = address(wftm);
            tokenPath[2] = address(targetToken);
            IUniswapV2Router02(router).swapExactTokensForTokens(
                _amount,
                uint256(0),
                tokenPath,
                address(this),
                block.timestamp
            );
        }
    }

    /* ========== KEEP3RS ========== */

    function harvestTrigger(uint256 callCostinEth)
        public
        view
        override
        returns (bool)
    {
        StrategyParams memory params = vault.strategies(address(this));

        // harvest no matter what once we reach our maxDelay
        if (block.timestamp.sub(params.lastReport) > maxReportDelay) {
            return true;
        }

        // trigger if we want to manually harvest
        if (forceHarvestTriggerOnce) {
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
    {
        return _ethAmount;
    }

    /* ========== SETTERS ========== */

    // These functions are useful for setting parameters of the strategy that may need to be adjusted.
    // Set optimal token to sell harvested funds for depositing to Curve.
    // Default is USDC, but can be set to fUSDT or DAI as needed by strategist or governance.
    function setOptimal(uint256 _optimal) external onlyAuthorized {
        if (_optimal == 0) {
            targetToken = address(dai);
        } else if (_optimal == 1) {
            targetToken = address(usdc);
        } else if (_optimal == 2) {
            targetToken = address(fusdt);
        } else {
            revert("incorrect token");
        }
    }

    // spookyswap generally has better liquidity. if this changes, we can use spiritswap.
    function setUseSpooky(bool useSpooky) external onlyAuthorized {
        if (useSpooky) {
            router = IUniswapV2Router02(
                0xF491e7B69E4244ad4002BC14e878a34207E38c29
            ); // spookyswap's router
        } else {
            router = IUniswapV2Router02(
                0x16327E3FbDaCA3bcF7E38F5Af2599D2DDc33aE52
            ); // spiritswap router
        }
    }
}
