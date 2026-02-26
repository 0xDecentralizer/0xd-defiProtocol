// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test, console} from "forge-std/Test.sol";
import {DeployDSC} from "../../script/DeployDSC.s.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import {MockV3Aggregator} from "../mocks/MockV3Aggregator.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {ERC20MockRevertable} from "../mocks/ERC20MockRevertable.sol";

contract DSCEngineTest is Test {
    uint256 private constant LIQUIDATION_THRESHOLD = 50; // 200%
    uint256 private constant LIQUIDATION_PRECISION = 100;
    uint256 private constant ADDITIONAL_FEED_PRECISION = 1e10;
    uint256 private constant PRECISION = 1e18;

    address immutable USER = makeAddr("user 1");
    uint256 constant AMOUNT_COLLATERAL = 10 ether;
    uint256 constant AMOUNT_DSC = 100 ether;

    DeployDSC deployer;
    DSCEngine dscEngine;
    DecentralizedStableCoin dscToken;
    HelperConfig config;
    address wethUsdPriceFeed;
    address wbtcUsdPriceFeed;
    address weth;
    address wbtc;

    modifier userDeposited10Weth() {
        ERC20Mock(weth).mint(USER, AMOUNT_COLLATERAL);
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dscEngine), AMOUNT_COLLATERAL);
        dscEngine.depositCollateral(weth, AMOUNT_COLLATERAL);
        vm.stopPrank();

        _;
    }

    modifier userMint100DscToken() {
        vm.prank(USER);
        dscEngine.mintDsc(AMOUNT_DSC);
        _;
    }

    function setUp() public {
        deployer = new DeployDSC();
        (dscToken, dscEngine, config) = deployer.run();
        (wethUsdPriceFeed, wbtcUsdPriceFeed, weth, wbtc,) = config.activeNetworkConfig();
    }

    /**
     * @dev Check the initial state of contract after deploy.
     */
    function testCheckInitialState() public view {
        address priceFeedAddress0 = wethUsdPriceFeed;
        address priceFeedAddress1 = wbtcUsdPriceFeed;
        address dscTokenAddress = address(dscToken);

        assertEq(dscEngine.getPriceFeed(weth), priceFeedAddress0);
        assertEq(dscEngine.getPriceFeed(wbtc), priceFeedAddress1);
        assertEq(dscEngine.getDscTokenAddress(), dscTokenAddress);
    }

    /**
     * @dev Get the USD value of a token and check the correctness.
     */
    function testGetUsdValue() public {
        uint256 amount = 3;
        uint256 expectedUsd = 9_000;
        uint256 actualUsd = dscEngine.getUsdValue(weth, amount);

        assertEq(expectedUsd, actualUsd, "Invalid USD calculation!");
    }

    ///////////////////////////////////
    //////     Health Factor     //////
    ///////////////////////////////////

    /**
     * @dev Test health factor for a user that deposited 10 ether and
     *      dosen't have mint any dsc token yet.
     */
    function testGetHealthFactor() public userDeposited10Weth {
        uint256 expectedHealthFactor = type(uint256).max;
        uint256 actualHealthFacotr = dscEngine.getHealthFactor(USER);

        assertEq(expectedHealthFactor, actualHealthFacotr);
    }

    /**
     * @dev Verifies that the health factor is calculated correctly
     *      after a user deposits 10 WETH as collateral and mints 100 DSC,
     *      using the protocol's liquidation parameters and price feed precision.
     */
    function testGetHealthFactorAfterMintingDscToken() public userDeposited10Weth userMint100DscToken {
        uint256 ethPrice = uint256(config.ETH_USD_PRICE());
        uint256 totalCollateralAmount = AMOUNT_COLLATERAL;
        uint256 totalDscMinted = AMOUNT_DSC;
        uint256 totalCollateralValueInUsd =
            ((totalCollateralAmount * (ethPrice * ADDITIONAL_FEED_PRECISION)) / PRECISION);
        uint256 calculatedThreshold =
            (((totalCollateralValueInUsd * LIQUIDATION_THRESHOLD) / LIQUIDATION_PRECISION) * PRECISION);
        uint256 expectedHealthFactor = calculatedThreshold / totalDscMinted;
        uint256 actualHealthFacotr = dscEngine.getHealthFactor(USER);

        assertEq(expectedHealthFactor, actualHealthFacotr);
    }

    ///////////////////////////////////////
    /////     Deposit Collateral     //////
    ///////////////////////////////////////

    /**
     * @dev Verifies that the error handling for zero deposits works correctly
     */
    function testRevertIfDepositZeroAmountCollateral() public {
        uint256 zeroAmount = 0;

        vm.prank(USER);
        vm.expectRevert((DSCEngine.DSCEngine__NeedsMoreThanZero.selector));
        dscEngine.depositCollateral(weth, zeroAmount);
    }

    /**
     * @dev Verifies that the error handling for zero deposits works correctly
     */
    function testRevertIfDepositInvalidCollateral() public {
        address invalidCollateral = makeAddr("LMAO");

        vm.prank(USER);
        vm.expectRevert(DSCEngine.DSCEngine__CollateralNotValid.selector);
        dscEngine.depositCollateral(invalidCollateral, AMOUNT_COLLATERAL);
    }

    function testDepositCollateralDoneSuccessfuly() public userDeposited10Weth {
        uint256 expectedDeposit = AMOUNT_COLLATERAL;
        uint256 actualDeposit = dscEngine.getCollateralDeposited(USER, weth);
        uint256 expectedDscEngineBallanceAfterDeposit = AMOUNT_COLLATERAL;
        uint256 actualDscEngineBallanceAfterDeposit = ERC20Mock(weth).balanceOf(address(dscEngine));

        assertEq(expectedDeposit, actualDeposit);
        assertEq(expectedDscEngineBallanceAfterDeposit, actualDscEngineBallanceAfterDeposit);
    }

    function testDepositEmitTheEventSuccessfuly() public {
        ERC20Mock(weth).mint(USER, AMOUNT_COLLATERAL);
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dscEngine), AMOUNT_COLLATERAL);
        vm.expectEmit(true, true, true, false);
        emit DSCEngine.CollateralDeposited(USER, weth, AMOUNT_COLLATERAL);
        dscEngine.depositCollateral(weth, AMOUNT_COLLATERAL);
    }

    function testRevertWhenTransferFailsInDepositCollateralFunction() public {
        ERC20MockRevertable revertableWeth;
        DSCEngine dsce;
        address[] memory _collaterals = new address[](2);
        address[] memory _priceFeeds = new address[](2);

        revertableWeth = new ERC20MockRevertable();
        (_collaterals[0], _collaterals[1]) = (address(revertableWeth), wbtc);
        (_priceFeeds[0], _priceFeeds[1]) = ((wethUsdPriceFeed), wbtcUsdPriceFeed);
        
        dsce = new DSCEngine(_collaterals, _priceFeeds, address(dscToken));

        ERC20MockRevertable(revertableWeth).mint(USER, AMOUNT_COLLATERAL);
        ERC20MockRevertable(revertableWeth).setShouldRevertTrue();

        vm.startPrank(USER);
        ERC20MockRevertable(revertableWeth).approve(address(dsce), AMOUNT_COLLATERAL);
        vm.expectRevert(DSCEngine.DSCEngine__TransferFailed.selector);
        dsce.depositCollateral(address(revertableWeth), AMOUNT_COLLATERAL);

        ERC20MockRevertable(revertableWeth).setShouldRevertFalse();
    }

    function testDepositCollateralsAndMintDscAtOnce() public {
        ERC20Mock(weth).mint(USER, AMOUNT_COLLATERAL);
        uint256 collateralValueInUsd = dscEngine.getUsdValue(weth, AMOUNT_COLLATERAL) * PRECISION;
        uint256 collateralAdjustedThreshold = ((collateralValueInUsd * LIQUIDATION_THRESHOLD) / LIQUIDATION_PRECISION);
        uint256 expectedHealthFactor = collateralAdjustedThreshold / AMOUNT_DSC;
        uint256 expectedCollateralDeposited = AMOUNT_COLLATERAL;
        uint256 expectedDscMinted = AMOUNT_DSC;

        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dscEngine), AMOUNT_COLLATERAL);
        dscEngine.depositCollateralAndMintDsc(weth, AMOUNT_COLLATERAL, AMOUNT_DSC);
        vm.stopPrank();

        uint256 actualHealthFactor = dscEngine.getHealthFactor(USER);
        uint256 actualCollateralDeposited = dscEngine.getCollateralDeposited(USER, weth);
        uint256 actualDscMinted = dscEngine.getDscMinted(USER);

        assertEq(expectedHealthFactor, actualHealthFactor);
        assertEq(expectedCollateralDeposited, actualCollateralDeposited);
        assertEq(expectedDscMinted, actualDscMinted);
    }

    ///////////////////////////////////////
    /////          Mint DSC          //////
    ///////////////////////////////////////

    /**
     * @dev When a user doesn't deposit any collateral, any try for minting DSC will fail.
     */
    function testRevertToMintDscWhenHealthFactorIsBroken() public {
        vm.prank(USER);
        vm.expectRevert(abi.encodeWithSelector(DSCEngine.DSCEngine__HealthFactorIsBroken.selector, 0));
        dscEngine.mintDsc(AMOUNT_DSC);
    }

    /**
     * @dev Reverts when a user attempts to mint DSC exceeding the allowed collateralization threshold.
     *
     * Ensures that the protocol prevents minting if it would result in
     * a health factor below the minimum required threshold.
     */
    function testRevertIfMintingDscBreaksHealthFactor() public userDeposited10Weth {
        uint256 dscAmountToMint = 50_000e18; // 50,000 DSC (= $50,000) > 10 ETH (= $30,000)
        uint256 healthFactorBeforeMint = dscEngine.getHealthFactor(USER);
        
        uint256 collateralValueInUsd = (dscEngine.getUsdValue(weth, AMOUNT_COLLATERAL)) * PRECISION;
        uint256 collateralAdjustedThreshold = (collateralValueInUsd * LIQUIDATION_THRESHOLD) / LIQUIDATION_PRECISION;
        uint256 healthFactorAfterMint = collateralAdjustedThreshold / dscAmountToMint;

        assertGt(healthFactorBeforeMint, healthFactorAfterMint);

        vm.prank(USER);
        vm.expectRevert(abi.encodeWithSelector(DSCEngine.DSCEngine__HealthFactorIsBroken.selector, healthFactorAfterMint));
        dscEngine.mintDsc(dscAmountToMint);
    }

    function testRevertIfMintingZeroAmountOfDsc() public {
        uint256 dscAmountToMint = 0;
        
        vm.prank(USER);
        vm.expectRevert(DSCEngine.DSCEngine__NeedsMoreThanZero.selector);
        dscEngine.mintDsc(0);
    }

    function testRevertIfMintingFails() public {
        ERC20MockRevertable revertableDsc = new ERC20MockRevertable();
        DSCEngine dsce;
        address[] memory _collaterals = new address[](2);
        address[] memory _priceFeeds = new address[](2);

        (_collaterals[0], _collaterals[1]) = (weth, wbtc);
        (_priceFeeds[0], _priceFeeds[1]) = (wethUsdPriceFeed, wbtcUsdPriceFeed);
        dsce = new DSCEngine(_collaterals, _priceFeeds, address(revertableDsc));

        // Deposit collateral before minting DSC
        ERC20Mock(weth).mint(USER, AMOUNT_COLLATERAL);
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dsce), AMOUNT_COLLATERAL);
        dsce.depositCollateral(weth, AMOUNT_COLLATERAL);
        vm.stopPrank();

        ERC20MockRevertable(revertableDsc).setShouldRevertTrue();

        vm.prank(USER);
        vm.expectRevert(DSCEngine.DSCEngine__MintFalied.selector);
        dsce.mintDsc(AMOUNT_DSC);

        ERC20MockRevertable(revertableDsc).setShouldRevertTrue();
    }

    function testMintDsc() public userDeposited10Weth userMint100DscToken {
        uint256 expectedDscMinted = AMOUNT_DSC;
        (uint256 actualDscMinted,) = dscEngine.getAccountInformation(USER);

        assertEq(expectedDscMinted, actualDscMinted);
    }

    ///////////////////////////////////////
    /////          Burn DSC          //////
    ///////////////////////////////////////

    function testBurnDscCorrectly() public userDeposited10Weth userMint100DscToken {
        vm.startPrank(USER);
        IERC20(address(dscToken)).approve(address(dscEngine), 10 ether);
        dscEngine.burnDsc(10 ether);
        vm.stopPrank();
    }

    ///////////////////////////////////
    //////       Liquidate       //////
    ///////////////////////////////////

    /**
     * @dev When a liquidator want to liquid a user, with an invalid type of collateral.
     * For example:
     *   - User deposits 2 WETH
     *   - Liquidator want to liquidate user with WBTC as input
     */
    function testRevertIfLiquidatorTryToLiquidUserWithInvalidCollateral() public userDeposited10Weth {
        vm.prank(USER);
        dscEngine.mintDsc(15000e18);

        address liquidator = address(0x1);
        ERC20Mock(weth).mint(liquidator, AMOUNT_COLLATERAL);
        vm.startPrank(liquidator);
        ERC20Mock(weth).approve(address(dscEngine), AMOUNT_COLLATERAL);
        dscEngine.depositCollateral(weth, AMOUNT_COLLATERAL);
        dscEngine.mintDsc(10000e18);
        vm.stopPrank();

        MockV3Aggregator wethPriceFeed = MockV3Aggregator(wethUsdPriceFeed);
        wethPriceFeed.updateAnswer(2500e8);

        vm.startPrank(liquidator);
        IERC20(address(dscToken)).approve(address(dscEngine), 1000e18);
        vm.expectRevert(DSCEngine.DSCEngine__UserDontHaveThisCollateral.selector);
        dscEngine.liquidate(wbtc, USER, 1000e18);
        vm.stopPrank();
    }
}
