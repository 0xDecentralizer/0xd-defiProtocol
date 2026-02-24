// SPDX-License-Identifier: MIT

// This is considered an Exogenous, Decentralized, Anchored (pegged), Crypto Collateralized low volitility coin

// Layout of Contract:
// version
// imports
// interfaces, libraries, contracts
// errors
// Type declarations
// State variables
// Events
// Modifiers
// Functions

// Layout of Functions:
// constructor
// receive function (if exists)
// fallback function (if exists)
// external
// public
// internal
// private
// view & pure functions

pragma solidity ^0.8.30;

import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {DecentralizedStableCoin} from "./DecentralizedStableCoin.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";

/**
 * @title DSCEngine
 * @author Patrick Collins
 *
 * The system is designed to be as minimal as possible, and have the tokens maintain a 1 token == $1 peg at all times.
 * This is a stablecoin with the properties:
 * - Exogenously Collateralized
 * - Dollar Pegged
 * - Algorithmically Stable
 *
 * It is similar to DAI if DAI had no governance, no fees, and was backed by only WETH and WBTC.
 *
 * Our DSC system should always be "overcollateralized". At no point, should the value of
 * all collateral < the $ backed value of all the DSC.
 *
 * @notice This contract is the core of the Decentralized Stablecoin system. It handles all the logic
 * for minting and redeeming DSC, as well as depositing and withdrawing collateral.
 * @notice This contract is based on the MakerDAO DSS system
 */
contract DSCEngine is ReentrancyGuard {
    // Errors
    error DSCEngine__NeedsMoreThanZero();
    error DSCEngine__CollateralNotValid();
    error DSCEngine__TransferFailed();
    error DSCEngine__TokenAddressesAndPriceFeedsDontMatch();
    error DSCEngine__HealthFactorIsBroken(uint256 userHealthFactor);
    error DSCEngine__MintFalied();
    error DSCEngine__HealthFactorIsSafe(uint256 userHealthFactor);
    error DSCEngine__DebtExeedsUserDebt();
    error DSCEngine__InsufficientCollateralForLiquidation();
    error DSCEngine__UserDontHaveThisCollateral();

    // State Variables
    uint256 private constant ADDITIONAL_FEED_PRECISION = 1e10;
    uint256 private constant PRECISION = 1e18;
    uint256 private constant LIQUIDATION_THRESHOLD = 50; // 200%
    uint256 private constant LIQUIDATION_PRECISION = 100;
    uint256 private constant LIQUIDATION_BONUS = 10;
    uint256 private constant MIN_HEALTH_FACTOR = 1e18;

    DecentralizedStableCoin private immutable DSC_TOKEN;
    mapping(address token => address priceFeed) private priceFeeds;
    mapping(address user => mapping(address token => uint256 amount)) private collateralDeposited;
    mapping(address user => uint256 amountDSCMinted) private dscMinted;
    address[] private collateralTokens;

    // Events
    event CollateralDeposited(address indexed depositor, address indexed depositedCollateral, uint256 indexed amount);
    event CollateralRedeemed(
        address indexed user, address indexed collateralTokenaddress, uint256 indexed amountCollateral
    );
    event DscBurned(address indexed user, uint256 indexed amountDsc);
    event CollateralLiquidated(address indexed liquidator, address indexed user, address collateralToken, uint256 debtCovered, uint256 collateralTaken);

    // Modifiers
    modifier needsMoreThanZero(uint256 amount) {
        _needsMoreThanZero(amount);
        _;
    }
    modifier isValidCollateral(address collateralToeknAddress) {
        _isValidCollateral(collateralToeknAddress);
        _;
    }

    // Constructor
    constructor(address[] memory collateralAddresses, address[] memory priceFeedAddresses, address dscTokenAddress) {
        if (collateralAddresses.length != priceFeedAddresses.length) {
            revert DSCEngine__TokenAddressesAndPriceFeedsDontMatch();
        }

        DSC_TOKEN = DecentralizedStableCoin(dscTokenAddress);

        for (uint256 i = 0; i < collateralAddresses.length; i++) {
            priceFeeds[collateralAddresses[i]] = priceFeedAddresses[i];
            collateralTokens.push(collateralAddresses[i]);
        }
    }

    // External Functions
    /**
     * @notice Deposits collateral into the DSC system
     * @param collateralTokenAddress The address of the collateral token to deposit
     * @param amount The amount of collateral to deposit
     */
    function depositCollateral(address collateralTokenAddress, uint256 amount)
        public
        needsMoreThanZero(amount)
        isValidCollateral(collateralTokenAddress)
        nonReentrant
    {
        collateralDeposited[msg.sender][collateralTokenAddress] += amount;
        emit CollateralDeposited(msg.sender, collateralTokenAddress, amount);
        (bool success) = IERC20(collateralTokenAddress).transferFrom(msg.sender, address(this), amount);
        if (!success) {
            revert DSCEngine__TransferFailed();
        }
    }

    /**
     *
     * @param collateralTokenAddress The address of the collateral token to deposit
     * @param amountCollateral The amount of collateral to deposit
     * @param amountDsc The amount of DSC to mint
     * @notice This function deposits collateral and mint DSC token in one transaction
     */
    function depositCollateralAndMintDsc(address collateralTokenAddress, uint256 amountCollateral, uint256 amountDsc)
        external
    {
        depositCollateral(collateralTokenAddress, amountCollateral);
        mintDsc(amountDsc);
    }

    /**
     * @param collateralTokenAddress The address of the collateral token to redeem
     * @param amountCollateral The amount of collateral to redeem
     * @param amountDscToBurn The amount of DSC to burn
     * @notice This function burns DSC token and redeem collateral at once (in one transacation)
     */
    function redeemCollateralForDsc(address collateralTokenAddress, uint256 amountCollateral, uint256 amountDscToBurn)
        external
    {
        burnDsc(amountDscToBurn);
        redeemCollateral(collateralTokenAddress, amountCollateral);
    }

    function redeemCollateral(address collateralTokenAddress, uint256 amountCollateral)
        public
        needsMoreThanZero(amountCollateral)
        isValidCollateral(collateralTokenAddress)
        nonReentrant
    {
        collateralDeposited[msg.sender][collateralTokenAddress] -= amountCollateral;
        _revertIfHealthFactorIsBroken(msg.sender);
        (bool success) = IERC20(collateralTokenAddress).transfer(msg.sender, amountCollateral);
        if (!success) {
            revert DSCEngine__TransferFailed();
        }
        emit CollateralRedeemed(msg.sender, collateralTokenAddress, amountCollateral);
    }

    /**
     * @notice Mints DSC to a user - Follow CEI
     * @param amountDSC The amount of DSC to mint
     * @dev Needs more than zero amount to mint
     */
    function mintDsc(uint256 amountDSC) public needsMoreThanZero(amountDSC) {
        dscMinted[msg.sender] += amountDSC;
        _revertIfHealthFactorIsBroken(msg.sender);

        bool minted = DSC_TOKEN.mint(msg.sender, amountDSC);
        if (!minted) {
            revert DSCEngine__MintFalied();
        }
    }

    function burnDsc(uint256 amountDsc) public needsMoreThanZero(amountDsc) nonReentrant {
        dscMinted[msg.sender] -= amountDsc;
        bool success = DSC_TOKEN.transferFrom(msg.sender, address(this), amountDsc);
        if (!success) {
            revert DSCEngine__TransferFailed();
        }
        DSC_TOKEN.burn(amountDsc);
        emit DscBurned(msg.sender, amountDsc);
    }

    /**
     * @notice Liquidates an undercollateralized user's position
     * @param collateral The address of the collateral token to seize from the user
     * @param user The address of the user to liquidate (must have HF < MIN_HEALTH_FACTOR)
     * @param debtToCover The amount of DSC to burn to cover user's debt
     * @return newHealthFactor The user's health factor after liquidation
     * @dev The liquidator receives the collateral + 10% bonus for liquidating
     * @dev Requirements:
     *   - User must be liquidatable (HF < 1e18)
     *   - debtToCover must not exceed user's total debt
     *   - User must have sufficient collateral of the specified type
     */
    function liquidate(address collateral, address user, uint256 debtToCover)
        external
        needsMoreThanZero(debtToCover)
        isValidCollateral(collateral)
        nonReentrant
        returns (uint256 newHealthFactor)
    {
        uint256 userHF = getHealthFactor(user);
        if (userHF >= MIN_HEALTH_FACTOR) {
            revert DSCEngine__HealthFactorIsSafe(userHF);
        }
        if (debtToCover > dscMinted[user]) {
            revert DSCEngine__DebtExeedsUserDebt();
        }
        if (collateralDeposited[user][collateral] == 0) {
            revert DSCEngine__UserDontHaveThisCollateral();
        }

        uint256 collateralAmount = getCollateralAmountFromUsdValue(collateral, debtToCover);
        uint256 bonusCollateral = (collateralAmount * LIQUIDATION_BONUS) / LIQUIDATION_PRECISION;
        uint256 totalCollateralToTransfer = collateralAmount + bonusCollateral;
        if (totalCollateralToTransfer > collateralDeposited[user][collateral]) {
            revert DSCEngine__InsufficientCollateralForLiquidation();
        }

        collateralDeposited[user][collateral] -= totalCollateralToTransfer;
        dscMinted[user] -= debtToCover;
        bool success = DSC_TOKEN.transferFrom(msg.sender ,address(this), debtToCover);
        if (!success) {
            revert DSCEngine__TransferFailed();
        }
        DSC_TOKEN.burn(debtToCover);
        success = IERC20(collateral).transfer(msg.sender, totalCollateralToTransfer);
        if (!success) {
            revert DSCEngine__TransferFailed();
        }
        emit CollateralLiquidated (msg.sender, user, collateral, debtToCover, totalCollateralToTransfer);

        newHealthFactor = getHealthFactor(user);
    }

    function getHealthFactor(address user) public view returns (uint256) {
        return _healtFactor(user);
    }

    function getCollateralAmountFromUsdValue(address collateral, uint256 debtToCover) public view returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(priceFeeds[collateral]);
        (, int256 price ,,,) = priceFeed.latestRoundData();
        uint256 collateralAmount = (debtToCover * PRECISION) / (uint256(price) * ADDITIONAL_FEED_PRECISION);

        return collateralAmount;
    }

    // Private & Internal Functions

    function _needsMoreThanZero(uint256 amount) internal pure {
        if (amount <= 0) {
            revert DSCEngine__NeedsMoreThanZero();
        }
    }

    function _isValidCollateral(address collateralToeknAddress) internal view {
        if (priceFeeds[collateralToeknAddress] == address(0)) {
            revert DSCEngine__CollateralNotValid();
        }
    }

    /**
     * @notice Returns the health factor of a user
     * @param user The address of the user
     * @return The health factor of the user
     */
    function _healtFactor(address user) private view returns (uint256) {
        (uint256 totalDscMinted, uint256 collateralValueInUsd) = getAccountInformation(user);
        uint256 collateralAdjustedForThreshold = (collateralValueInUsd * LIQUIDATION_THRESHOLD) / LIQUIDATION_PRECISION;
        if (totalDscMinted == 0) {
            return type(uint256).max; // Infinite
        }
        return (collateralAdjustedForThreshold * PRECISION) / totalDscMinted;
    }

    function _revertIfHealthFactorIsBroken(address user) internal view {
        uint256 userHealthFactor = _healtFactor(user);
        if (userHealthFactor < MIN_HEALTH_FACTOR) {
            revert DSCEngine__HealthFactorIsBroken(userHealthFactor);
        }
    }

    // Public & External View Function
    function getAccountInformation(address user)
        public
        view
        returns (uint256 totalDscMinted, uint256 collateralValueInUsd)
    {
        totalDscMinted = dscMinted[user];
        collateralValueInUsd = getAccountCollateralValue(user);
    }

    function getPriceFeed(address collateralTokenAddress) public view returns (address) {
        return priceFeeds[collateralTokenAddress];
    }

    function getDscTokenAddress() public view returns (address) {
        return address(DSC_TOKEN);
    }

    function getUsdValue(address token, uint256 amount) public view returns (uint256) {
        if (amount == 0) return 0;
        AggregatorV3Interface priceFeed = AggregatorV3Interface(priceFeeds[token]);
        (, int256 price,,,) = priceFeed.latestRoundData();
        return ((uint256(price) * ADDITIONAL_FEED_PRECISION) * amount) / PRECISION;
    }

    function getAccountCollateralValue(address user) public view returns (uint256) {
        uint256 totalCollateralValueInUsd;
        for (uint256 i = 0; i < collateralTokens.length; i++) {
            address token = collateralTokens[i];
            uint256 amount = collateralDeposited[user][token];
            totalCollateralValueInUsd += getUsdValue(token, amount);
        }
        return totalCollateralValueInUsd;
    }

    function getCollateralDeposited(address user, address collateral) public view returns (uint256) {
        return collateralDeposited[user][collateral];
    }
}
