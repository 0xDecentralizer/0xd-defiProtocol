// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";
import {DeployDSC} from "../../script/DeployDSC.s.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import {MockV3Aggregator} from "../mocks/MockV3Aggregator.sol";
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

    // ----------- Modifiers -----------
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

    // ----------- Helpers -----------
    function _deployEngineWithDsc(address dscAddress) internal returns (DSCEngine) {
        address[] memory collaterals = new address[](2);
        address[] memory priceFeeds = new address[](2);
        (collaterals[0], collaterals[1]) = (weth, wbtc);
        (priceFeeds[0], priceFeeds[1]) = (wethUsdPriceFeed, wbtcUsdPriceFeed);
        return new DSCEngine(collaterals, priceFeeds, dscAddress);
    }

    function _depositWethForUser(DSCEngine engine, uint256 amount) internal {
        ERC20Mock(weth).mint(USER, amount);
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(engine), amount);
        engine.depositCollateral(weth, amount);
        vm.stopPrank();
    }

    // ----------- Constructor -----------
    function test_Constructor_InitialStateIsConfigured() public view {
        address priceFeedAddress0 = wethUsdPriceFeed;
        address priceFeedAddress1 = wbtcUsdPriceFeed;
        address dscTokenAddress = address(dscToken);

        assertEq(dscEngine.getPriceFeed(weth), priceFeedAddress0);
        assertEq(dscEngine.getPriceFeed(wbtc), priceFeedAddress1);
        assertEq(dscEngine.getDscTokenAddress(), dscTokenAddress);
    }

    // ----------- View Functions -----------
    function test_GetUsdValue_ReturnsExpectedUsd() public {
        uint256 amount = 3;
        uint256 expectedUsd = 9_000;
        uint256 actualUsd = dscEngine.getUsdValue(weth, amount);

        assertEq(expectedUsd, actualUsd);
    }

    // ----------- Health Factor -----------
    function test_GetHealthFactor_NoDebt_ReturnsMax() public userDeposited10Weth {
        uint256 expectedHealthFactor = type(uint256).max;
        uint256 actualHealthFactor = dscEngine.getHealthFactor(USER);

        assertEq(expectedHealthFactor, actualHealthFactor);
    }

    function test_GetHealthFactor_AfterMinting_ReturnsExpectedValue() public userDeposited10Weth userMint100DscToken {
        uint256 ethPrice = uint256(config.ETH_USD_PRICE());
        uint256 totalCollateralAmount = AMOUNT_COLLATERAL;
        uint256 totalDscMinted = AMOUNT_DSC;
        uint256 totalCollateralValueInUsd =
            ((totalCollateralAmount * (ethPrice * ADDITIONAL_FEED_PRECISION)) / PRECISION);
        uint256 calculatedThreshold =
            (((totalCollateralValueInUsd * LIQUIDATION_THRESHOLD) / LIQUIDATION_PRECISION) * PRECISION);
        uint256 expectedHealthFactor = calculatedThreshold / totalDscMinted;
        uint256 actualHealthFactor = dscEngine.getHealthFactor(USER);

        assertEq(expectedHealthFactor, actualHealthFactor);
    }

    // ----------- Deposit Collateral -----------
    function test_DepositCollateral_RevertsOnZeroAmount() public {
        vm.prank(USER);
        vm.expectRevert((DSCEngine.DSCEngine__NeedsMoreThanZero.selector));
        dscEngine.depositCollateral(weth, 0);
    }

    function test_DepositCollateral_RevertsOnInvalidCollateral() public {
        address invalidCollateral = makeAddr("LMAO");

        vm.prank(USER);
        vm.expectRevert(DSCEngine.DSCEngine__CollateralNotValid.selector);
        dscEngine.depositCollateral(invalidCollateral, AMOUNT_COLLATERAL);
    }

    function test_DepositCollateral_UpdatesUserAndEngineBalances() public userDeposited10Weth {
        uint256 expectedDeposit = AMOUNT_COLLATERAL;
        uint256 actualDeposit = dscEngine.getCollateralDeposited(USER, weth);
        uint256 expectedEngineBalanceAfterDeposit = AMOUNT_COLLATERAL;
        uint256 actualEngineBalanceAfterDeposit = ERC20Mock(weth).balanceOf(address(dscEngine));

        assertEq(expectedDeposit, actualDeposit);
        assertEq(expectedEngineBalanceAfterDeposit, actualEngineBalanceAfterDeposit);
    }

    function test_DepositCollateral_EmitsEvent() public {
        ERC20Mock(weth).mint(USER, AMOUNT_COLLATERAL);
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dscEngine), AMOUNT_COLLATERAL);
        vm.expectEmit(true, true, true, false);
        emit DSCEngine.CollateralDeposited(USER, weth, AMOUNT_COLLATERAL);
        dscEngine.depositCollateral(weth, AMOUNT_COLLATERAL);
        vm.stopPrank();
    }

    function test_DepositCollateral_RevertsWhenTransferFails() public {
        ERC20MockRevertable revertableWeth = new ERC20MockRevertable();
        address[] memory collaterals = new address[](2);
        address[] memory priceFeeds = new address[](2);
        (collaterals[0], collaterals[1]) = (address(revertableWeth), wbtc);
        (priceFeeds[0], priceFeeds[1]) = (wethUsdPriceFeed, wbtcUsdPriceFeed);
        DSCEngine engine = new DSCEngine(collaterals, priceFeeds, address(dscToken));

        revertableWeth.mint(USER, AMOUNT_COLLATERAL);
        revertableWeth.setShouldRevertTrue();

        vm.startPrank(USER);
        revertableWeth.approve(address(engine), AMOUNT_COLLATERAL);
        vm.expectRevert(DSCEngine.DSCEngine__TransferFailed.selector);
        engine.depositCollateral(address(revertableWeth), AMOUNT_COLLATERAL);
        vm.stopPrank();
    }

    function test_DepositCollateralAndMintDsc_UpdatesState() public {
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

    // ----------- Mint DSC -----------
    function test_MintDsc_RevertsWhenUserHasNoCollateral() public {
        vm.prank(USER);
        vm.expectRevert(abi.encodeWithSelector(DSCEngine.DSCEngine__HealthFactorIsBroken.selector, 0));
        dscEngine.mintDsc(AMOUNT_DSC);
    }

    function test_MintDsc_RevertsWhenHealthFactorBreaks() public userDeposited10Weth {
        uint256 dscAmountToMint = 50_000e18; // 50,000 DSC (= $50,000) > 10 ETH (= $30,000)
        uint256 healthFactorBeforeMint = dscEngine.getHealthFactor(USER);

        uint256 collateralValueInUsd = (dscEngine.getUsdValue(weth, AMOUNT_COLLATERAL)) * PRECISION;
        uint256 collateralAdjustedThreshold = (collateralValueInUsd * LIQUIDATION_THRESHOLD) / LIQUIDATION_PRECISION;
        uint256 healthFactorAfterMint = collateralAdjustedThreshold / dscAmountToMint;

        assertGt(healthFactorBeforeMint, healthFactorAfterMint);

        vm.prank(USER);
        vm.expectRevert(
            abi.encodeWithSelector(DSCEngine.DSCEngine__HealthFactorIsBroken.selector, healthFactorAfterMint)
        );
        dscEngine.mintDsc(dscAmountToMint);
    }

    function test_MintDsc_RevertsOnZeroAmount() public {
        vm.prank(USER);
        vm.expectRevert(DSCEngine.DSCEngine__NeedsMoreThanZero.selector);
        dscEngine.mintDsc(0);
    }

    function test_MintDsc_RevertsWhenTokenMintFails() public {
        ERC20MockRevertable revertableDsc = new ERC20MockRevertable();
        DSCEngine engine = _deployEngineWithDsc(address(revertableDsc));
        _depositWethForUser(engine, AMOUNT_COLLATERAL);

        revertableDsc.setShouldRevertTrue();

        vm.prank(USER);
        vm.expectRevert(DSCEngine.DSCEngine__MintFalied.selector);
        engine.mintDsc(AMOUNT_DSC);
    }

    function test_MintDsc_UpdatesDebtAndHealthFactor() public userDeposited10Weth userMint100DscToken {
        uint256 expectedDscMinted = AMOUNT_DSC;
        uint256 collateralValueInUsd = dscEngine.getAccountCollateralValue(USER) * PRECISION;
        uint256 expectedHealthFactor =
            ((collateralValueInUsd * LIQUIDATION_THRESHOLD) / LIQUIDATION_PRECISION) / AMOUNT_DSC;

        uint256 actualDscMinted = dscEngine.getDscMinted(USER);
        uint256 actualHealthFactor = dscEngine.getHealthFactor(USER);

        assertEq(expectedDscMinted, actualDscMinted);
        assertEq(expectedHealthFactor, actualHealthFactor);
    }

    // ----------- Burn DSC -----------
    function test_BurnDsc_BurnsAndEmitsEvent() public userDeposited10Weth userMint100DscToken {
        uint256 amountToBurn = 10e18;
        uint256 userBalanceBeforeBurn = ERC20Mock(address(dscToken)).balanceOf(USER);

        vm.startPrank(USER);
        ERC20Mock(address(dscToken)).approve(address(dscEngine), amountToBurn);
        vm.expectEmit(true, true, true, false);
        emit DSCEngine.DscBurned(USER, USER, amountToBurn);
        dscEngine.burnDsc(amountToBurn);
        vm.stopPrank();

        uint256 userBalanceAfterBurn = ERC20Mock(address(dscToken)).balanceOf(USER);

        assertEq(userBalanceBeforeBurn, userBalanceAfterBurn + amountToBurn);
    }

    function test_BurnDsc_RevertsWhenTransferFromFails() public {
        uint256 amountDscToBurn = 1e18;
        ERC20MockRevertable revertableDsc = new ERC20MockRevertable();
        DSCEngine engine = _deployEngineWithDsc(address(revertableDsc));

        _depositWethForUser(engine, AMOUNT_COLLATERAL);
        vm.prank(USER);
        engine.mintDsc(AMOUNT_DSC);

        revertableDsc.setShouldRevertTrue();
        vm.prank(USER);
        vm.expectRevert(DSCEngine.DSCEngine__TransferFailed.selector);
        engine.burnDsc(amountDscToBurn);
    }

    // ----------- Redeem Collateral -----------
    function test_RedeemCollateral_RevertsOnZeroAmount() public {
        vm.prank(USER);
        vm.expectRevert(DSCEngine.DSCEngine__NeedsMoreThanZero.selector);
        dscEngine.redeemCollateral(weth, 0);
    }

    function test_RedeemCollateral_RevertsOnInvalidCollateral() public {
        address invalidCollatreral = makeAddr('haha');
        vm.prank(USER);
        vm.expectRevert(DSCEngine.DSCEngine__CollateralNotValid.selector);
        dscEngine.redeemCollateral(invalidCollatreral, 5);
    }

    function test_RedeemCollateral_RevertsOnZeroBalanceToRedeem() public {
        vm.prank(USER);
        vm.expectRevert(DSCEngine.DSCEngine__ThereIsNoCollateralToRedeem.selector);
        dscEngine.redeemCollateral(weth, 10);
    }

    // ----------- Liquidate -----------
    function test_Liquidate_RevertsWhenTargetCollateralDoesNotExist() public userDeposited10Weth {
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
        ERC20Mock(address(dscToken)).approve(address(dscEngine), 1000e18);
        vm.expectRevert(DSCEngine.DSCEngine__UserDontHaveThisCollateral.selector);
        dscEngine.liquidate(wbtc, USER, 1000e18);
        vm.stopPrank();
    }
}
