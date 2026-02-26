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
    /*//////////////////////////////////////////////////////////////
                                ERRORS
    //////////////////////////////////////////////////////////////*/
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
    error DSCEngine__HealthFactorNotImproved(uint256 userStartingHF, uint256 userEndingHF);

    /*//////////////////////////////////////////////////////////////
                           STATE VARIABLES
    //////////////////////////////////////////////////////////////*/
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

    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/
    event CollateralDeposited(address indexed depositor, address indexed depositedCollateral, uint256 indexed amount);
    event CollateralRedeemed(
        address indexed from, address indexed to, address indexed collateralTokenaddress, uint256 amountCollateral
    );
    event DscBurned(address indexed onBehalfOf, address indexed dscFrom, uint256 indexed amountDsc);
    event CollateralLiquidated(
        address indexed liquidator,
        address indexed user,
        address collateralToken,
        uint256 debtCovered,
        uint256 collateralTaken
    );

    /*//////////////////////////////////////////////////////////////
                               MODIFIERS
    //////////////////////////////////////////////////////////////*/
    modifier needsMoreThanZero(uint256 amount) {
        _needsMoreThanZero(amount);
        _;
    }
    modifier isValidCollateral(address collateralToeknAddress) {
        _isValidCollateral(collateralToeknAddress);
        _;
    }

    /*//////////////////////////////////////////////////////////////
                              CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/
    /**
     * @notice Initializes the engine with supported collateral tokens, their Chainlink feeds, and the DSC token.
     * @param collateralAddresses List of ERC20 collateral token addresses accepted by the protocol.
     * @param priceFeedAddresses List of Chainlink USD price feed addresses mapped 1:1 with `collateralAddresses`.
     * @param dscTokenAddress Address of the `DecentralizedStableCoin` token contract.
     * @dev Reverts if `collateralAddresses.length != priceFeedAddresses.length`.
     */
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

    /*//////////////////////////////////////////////////////////////
                     EXTERNAL / PUBLIC (MUTATIVE)
    //////////////////////////////////////////////////////////////*/
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
     * @notice Deposits collateral and mints DSC in a single transaction.
     * @param collateralTokenAddress The collateral token to deposit.
     * @param amountCollateral Amount of collateral to deposit.
     * @param amountDsc Amount of DSC to mint.
     * @dev Equivalent to calling `depositCollateral` then `mintDsc`.
     */
    function depositCollateralAndMintDsc(address collateralTokenAddress, uint256 amountCollateral, uint256 amountDsc)
        external
    {
        depositCollateral(collateralTokenAddress, amountCollateral);
        mintDsc(amountDsc);
    }

    /**
     * @notice Burns DSC and redeems collateral in a single transaction.
     * @param collateralTokenAddress The collateral token to redeem.
     * @param amountCollateral Amount of collateral to redeem.
     * @param amountDscToBurn Amount of DSC to burn.
     * @dev Equivalent to calling `burnDsc` then `redeemCollateral`.
     */
    function redeemCollateralForDsc(address collateralTokenAddress, uint256 amountCollateral, uint256 amountDscToBurn)
        external
    {
        burnDsc(amountDscToBurn);
        redeemCollateral(collateralTokenAddress, amountCollateral);
    }

    /**
     * @notice Redeems previously deposited collateral.
     * @param collateralTokenAddress The collateral token to redeem.
     * @param amountCollateral Amount of collateral to redeem.
     * @dev Reverts if the action would leave caller below minimum health factor.
     */
    function redeemCollateral(address collateralTokenAddress, uint256 amountCollateral)
        public
        needsMoreThanZero(amountCollateral)
        isValidCollateral(collateralTokenAddress)
        nonReentrant
    {
        _redeemCollateral(msg.sender, msg.sender, collateralTokenAddress, amountCollateral);
        _revertIfHealthFactorIsBroken(msg.sender);
    }

    /**
     * @notice Mints DSC to a user - Follow CEI
     * @param amountDSC The amount of DSC to mint
     * @dev Reverts if minting causes caller health factor to drop below minimum.
     */
    function mintDsc(uint256 amountDSC) public needsMoreThanZero(amountDSC) {
        dscMinted[msg.sender] += amountDSC;
        _revertIfHealthFactorIsBroken(msg.sender);

        bool minted = DSC_TOKEN.mint(msg.sender, amountDSC);
        if (!minted) {
            revert DSCEngine__MintFalied();
        }
    }

    /**
     * @notice Burns caller-owned DSC and decreases caller debt.
     * @param amountDsc Amount of DSC to burn.
     * @dev Caller must approve this contract to transfer `amountDsc` DSC beforehand.
     */
    function burnDsc(uint256 amountDsc) public needsMoreThanZero(amountDsc) nonReentrant {
        _burnDsc(msg.sender, msg.sender, amountDsc);
    }

    /**
     * @notice Liquidates an undercollateralized user's position
     * @param collateral The address of the collateral token to seize from the user
     * @param user The address of the user to liquidate (must have HF < MIN_HEALTH_FACTOR)
     * @param debtToCover The amount of DSC to burn to cover user's debt
     * @return The user's health factor after liquidation.
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
        returns (uint256)
    {
        uint256 userStartingHF = getHealthFactor(user);
        if (userStartingHF >= MIN_HEALTH_FACTOR) {
            revert DSCEngine__HealthFactorIsSafe(userStartingHF);
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

        _redeemCollateral(user, msg.sender, collateral, totalCollateralToTransfer);
        _burnDsc(user, msg.sender, debtToCover);
        emit CollateralLiquidated(msg.sender, user, collateral, debtToCover, totalCollateralToTransfer);

        uint256 userEndingHF = getHealthFactor(user);
        if (userEndingHF <= userStartingHF) {
            revert DSCEngine__HealthFactorNotImproved(userStartingHF, userEndingHF);
        }
        _revertIfHealthFactorIsBroken(msg.sender);
        return userEndingHF;
    }

    /*//////////////////////////////////////////////////////////////
                           INTERNAL / PRIVATE
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Validates that an input amount is non-zero.
     * @param amount Amount to validate.
     */
    function _needsMoreThanZero(uint256 amount) internal pure {
        if (amount <= 0) {
            revert DSCEngine__NeedsMoreThanZero();
        }
    }

    /**
     * @notice Validates that token address is configured as accepted collateral.
     * @param collateralToeknAddress Collateral token address to validate.
     */
    function _isValidCollateral(address collateralToeknAddress) internal view {
        if (priceFeeds[collateralToeknAddress] == address(0)) {
            revert DSCEngine__CollateralNotValid();
        }
    }

    /**
     * @notice Returns the health factor of a user
     * @param user The address of the user
     * @return The user's health factor scaled by 1e18.
     * @dev Returns `type(uint256).max` if user has no minted DSC debt.
     */
    function _healtFactor(address user) private view returns (uint256) {
        (uint256 totalDscMinted, uint256 collateralValueInUsd) = getAccountInformation(user);
        uint256 collateralAdjustedForThreshold = (collateralValueInUsd * LIQUIDATION_THRESHOLD) / LIQUIDATION_PRECISION;
        if (totalDscMinted == 0) {
            return type(uint256).max; // Infinite
        }
        return (collateralAdjustedForThreshold * PRECISION) / totalDscMinted;
    }

    /**
     * @notice Reverts if user health factor is below protocol minimum.
     * @param user Account to validate.
     */
    function _revertIfHealthFactorIsBroken(address user) internal view {
        uint256 userHealthFactor = _healtFactor(user);
        if (userHealthFactor < MIN_HEALTH_FACTOR) {
            revert DSCEngine__HealthFactorIsBroken(userHealthFactor);
        }
    }

    /**
     * @notice Transfers collateral from one user balance to another address.
     * @param from Account whose recorded collateral balance is debited.
     * @param to Recipient of the collateral tokens.
     * @param collateralTokenAddress Collateral token address.
     * @param amountCollateral Amount of collateral to transfer.
     */
    function _redeemCollateral(address from, address to, address collateralTokenAddress, uint256 amountCollateral)
        private
    {
        collateralDeposited[from][collateralTokenAddress] -= amountCollateral;
        (bool success) = IERC20(collateralTokenAddress).transfer(to, amountCollateral);
        if (!success) {
            revert DSCEngine__TransferFailed();
        }
        emit CollateralRedeemed(from, to, collateralTokenAddress, amountCollateral);
    }

    /**
     * @notice Burns DSC against a user's debt position.
     * @param onBehalfOf User whose minted DSC debt is reduced.
     * @param dscFrom Address supplying DSC tokens to burn.
     * @param amountDscToBurn Amount of DSC to burn.
     * @dev Requires prior DSC allowance from `dscFrom` to this contract.
     */
    function _burnDsc(address onBehalfOf, address dscFrom, uint256 amountDscToBurn) private {
        dscMinted[onBehalfOf] -= amountDscToBurn;
        bool success = DSC_TOKEN.transferFrom(dscFrom, address(this), amountDscToBurn);
        if (!success) {
            revert DSCEngine__TransferFailed();
        }
        DSC_TOKEN.burn(amountDscToBurn);
        emit DscBurned(onBehalfOf, dscFrom, amountDscToBurn);
    }

    /*//////////////////////////////////////////////////////////////
                        EXTERNAL / PUBLIC (VIEW)
    //////////////////////////////////////////////////////////////*/
    /**
     * @notice Returns current health factor for a user.
     * @param user Account to evaluate.
     * @return Health factor scaled by 1e18; values below 1e18 are unsafe.
     */
    function getHealthFactor(address user) public view returns (uint256) {
        return _healtFactor(user);
    }

    /**
     * @notice Converts a USD-denominated debt amount (18 decimals) into collateral token amount.
     * @param collateral Collateral token address.
     * @param debtToCover USD debt amount, in 18-decimal precision.
     * @return Collateral token amount needed to cover `debtToCover` at current oracle price.
     * @dev Uses Chainlink feed price and assumes feed has 8 decimals.
     */
    function getCollateralAmountFromUsdValue(address collateral, uint256 debtToCover) public view returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(priceFeeds[collateral]);
        (, int256 price,,,) = priceFeed.latestRoundData();
        uint256 collateralAmount = (debtToCover * PRECISION) / (uint256(price) * ADDITIONAL_FEED_PRECISION);

        return collateralAmount;
    }

    /**
     * @notice Returns a user's total minted DSC and total collateral USD value.
     * @param user Account to query.
     * @return totalDscMinted Total DSC minted by `user`.
     * @return collateralValueInUsd Total collateral value of `user` in USD (18 decimals).
     */
    function getAccountInformation(address user)
        public
        view
        returns (uint256 totalDscMinted, uint256 collateralValueInUsd)
    {
        totalDscMinted = dscMinted[user];
        collateralValueInUsd = getAccountCollateralValue(user);
    }

    /**
     * @notice Returns Chainlink price feed address configured for a collateral token.
     * @param collateralTokenAddress Collateral token address.
     * @return Price feed contract address.
     */
    function getPriceFeed(address collateralTokenAddress) public view returns (address) {
        return priceFeeds[collateralTokenAddress];
    }

    /**
     * @notice Returns the DSC token contract address.
     * @return Address of the `DecentralizedStableCoin` token.
     */
    function getDscTokenAddress() public view returns (address) {
        return address(DSC_TOKEN);
    }

    /**
     * @notice Returns USD value for a token amount.
     * @param token Collateral token address.
     * @param amount Token amount in token decimals.
     * @return USD value in 18-decimal precision.
     * @dev Uses configured Chainlink price feed and assumes 8-decimal feed answer.
     */
    function getUsdValue(address token, uint256 amount) public view returns (uint256) {
        if (amount == 0) return 0;
        AggregatorV3Interface priceFeed = AggregatorV3Interface(priceFeeds[token]);
        (, int256 price,,,) = priceFeed.latestRoundData();
        return ((uint256(price) * ADDITIONAL_FEED_PRECISION) * amount) / PRECISION;
    }

    /**
     * @notice Returns total USD value of all collateral deposited by a user.
     * @param user Account to query.
     * @return Total collateral value in USD (18 decimals).
     */
    function getAccountCollateralValue(address user) public view returns (uint256) {
        uint256 totalCollateralValueInUsd;
        for (uint256 i = 0; i < collateralTokens.length; i++) {
            address token = collateralTokens[i];
            uint256 amount = collateralDeposited[user][token];
            totalCollateralValueInUsd += getUsdValue(token, amount);
        }
        return totalCollateralValueInUsd;
    }

    /**
     * @notice Returns collateral amount deposited by user for a specific token.
     * @param user Account to query.
     * @param collateral Collateral token address.
     * @return Amount of `collateral` deposited by `user`.
     */
    function getCollateralDeposited(address user, address collateral) public view returns (uint256) {
        return collateralDeposited[user][collateral];
    }

    function getDscMinted(address user) public view returns (uint256) {
        return dscMinted[user];
    }
}
