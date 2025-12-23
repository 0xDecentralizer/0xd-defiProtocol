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
    error DSCEngine__TransferFaild();
    error DSCEngine__TokenAddressesAndPriceFeedsDontMatch();
    error DSCEngine__BreaksHealthFactor(uint256 userHealthFactor);
    error DSCEngine__MintFalied();

    // State Variables
    uint256 private constant ADDITIONAL_FEED_PRECISION = 1e8;
    uint256 private constant PRECISION = 1e18;
    uint256 private constant LIQUIDATION_THRESHOLD = 50; // 200%
    uint256 private constant LIQUIDATION_PRECISION = 100;
    uint256 private constant MIN_HEALTH_FACTOR = 1;

    DecentralizedStableCoin private immutable DSC_TOKEN;
    mapping(address token => address priceFeed) private priceFeeds;
    mapping(address user => mapping(address token => uint256 amount)) private collateralDeposited;
    mapping(address user => uint256 amountDSCMinted) private DSCMinted;
    address[] private collateralTokens;

    // Events
    event CollateralDeposited(address indexed depositor, address indexed depositedCollateral, uint256 indexed amount);

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
     * @param collateralToeknAddress The address of the collateral token to deposit
     * @param amount The amount of collateral to deposit
     */
    function depositCollateral(address collateralToeknAddress, uint256 amount)
        external
        needsMoreThanZero(amount)
        isValidCollateral(collateralToeknAddress)
        nonReentrant
    {
        // TODO: implement deposit collateral logic
        collateralDeposited[msg.sender][collateralToeknAddress] += amount;
        emit CollateralDeposited(msg.sender, collateralToeknAddress, amount);
        (bool success) = IERC20(collateralToeknAddress).transferFrom(msg.sender, address(this), amount);
        if (!success) {
            revert DSCEngine__TransferFaild();
        }
    }

    function depositCollateralAndMintIt() external {}

    function redeemCollateralForDsc() external {}

    function redeemCollateral() external {}


    /**
     * @notice Mints DSC to a user - Follow CEI
     * @param amountDSC The amount of DSC to mint
     * @dev Needs more than zero amount to mint
     */
    function mintDsc(uint256 amountDSC) external needsMoreThanZero(amountDSC) {
        DSCMinted[msg.sender] += amountDSC;
        _revertIfHealthFactorIsBroken(msg.sender);

        bool minted = DSC_TOKEN.mint(msg.sender, amountDSC);
        if (!minted) {
            revert DSCEngine__MintFalied();
        }
    }

    function burnDsc() external {}

    function liquidate() external {}

    function getHealthFactor(address user) external returns (uint256) {
        return _healtFactor(user);
    }

    // Private & Internal Functions
    function _getAccountInformation(address user) private returns (uint256 totalDscMinted, uint256 collateralValueInUsd) {
        totalDscMinted = DSCMinted[msg.sender];
        collateralValueInUsd = getAccountCollateralValue(user);
    }

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
    function _healtFactor(address user) private  returns (uint256) {
        (uint256 totalDscMinted, uint256 collateralValueInUsd) = _getAccountInformation(user);
        uint256 collateralAdjustedForThreshold = (collateralValueInUsd * LIQUIDATION_THRESHOLD) / LIQUIDATION_PRECISION;
        if (totalDscMinted == 0) {
            return type(uint256).max;
        }
        return (collateralAdjustedForThreshold * PRECISION) / totalDscMinted;
    }

    function _revertIfHealthFactorIsBroken(address user) internal {
        uint256 userHealthFactor = _healtFactor(user);
        if (userHealthFactor < MIN_HEALTH_FACTOR) {
            revert DSCEngine__BreaksHealthFactor(userHealthFactor);
        }
    }

    // Public & External View Function
    function getPriceFeed(address collateralTokenAddress) public view returns (address) {
        return priceFeeds[collateralTokenAddress];
    }

    function getDscTokenAddress() public view returns (address) {
        return address(DSC_TOKEN);
    }

    function getUsdValue(address token, uint256 amount) public returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(priceFeeds[token]);
        (, int256 price ,,,) = priceFeed.latestRoundData();
        return ((uint256(price) * ADDITIONAL_FEED_PRECISION) * amount) / PRECISION;
    }

    function getAccountCollateralValue(address user) public returns (uint256) {
        uint256 totalCollateralValueInUsd;
        for (uint i = 0; i < collateralTokens.length; i++) {
            address token = collateralTokens[i];
            uint256 amount = collateralDeposited[user][token];
            totalCollateralValueInUsd += getUsdValue(token, amount);
        }
    }
}
