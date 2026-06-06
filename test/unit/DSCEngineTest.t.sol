// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import {DeployDSC} from "../../script/DeployDSC.s.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {ERC20MockRevertable} from "../mocks/ERC20MockRevertable.sol";
import {MockV3Aggregator} from "../mocks/MockV3Aggregator.sol";

contract DSCEngineTest is Test {
    uint256 private constant LIQUIDATION_THRESHOLD = 50; // 200%
    uint256 private constant LIQUIDATION_PRECISION = 100;
    uint256 private constant ADDITIONAL_FEED_PRECISION = 1e10;
    uint256 private constant PRECISION = 1e18;

    uint256 private constant COLLATERAL_AMOUNT = 10 ether;
    uint256 private constant DSC_AMOUNT = 100 ether;
    address private immutable i_user = makeAddr("user 1");

    DeployDSC private deployer;
    DSCEngine private dscEngine;
    DecentralizedStableCoin private dscToken;
    HelperConfig private config;
    address private wethUsdPriceFeed;
    address private wbtcUsdPriceFeed;
    address private weth;
    address private wbtc;

    modifier givenUserDepositedWeth() {
        _depositWethForUser(dscEngine, COLLATERAL_AMOUNT);
        _;
    }

    modifier givenUserMintedDsc() {
        vm.prank(i_user);
        dscEngine.mintDsc(DSC_AMOUNT);
        _;
    }

    function setUp() public {
        deployer = new DeployDSC();
        (dscToken, dscEngine, config) = deployer.run();
        (wethUsdPriceFeed, wbtcUsdPriceFeed, weth, wbtc,) = config.activeNetworkConfig();
    }

    /*//////////////////////////////////////////////////////////////
                               CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/
    function test_Constructor_ConfiguresCollateralFeedsAndDscToken() public view {
        assertEq(dscEngine.getPriceFeed(weth), wethUsdPriceFeed);
        assertEq(dscEngine.getPriceFeed(wbtc), wbtcUsdPriceFeed);
        assertEq(dscEngine.getDscTokenAddress(), address(dscToken));
    }

    /*//////////////////////////////////////////////////////////////
                             PRICE AND VIEWS
    //////////////////////////////////////////////////////////////*/
    function test_GetUsdValue_ReturnsExpectedUsdValue() public view {
        uint256 amount = 3;
        uint256 expectedUsdValue = 9_000;

        uint256 actualUsdValue = dscEngine.getUsdValue(weth, amount);

        assertEq(expectedUsdValue, actualUsdValue);
    }

    function test_GetHealthFactor_ReturnsMaxWhenUserHasNoDebt() public givenUserDepositedWeth {
        uint256 expectedHealthFactor = type(uint256).max;

        uint256 actualHealthFactor = dscEngine.getHealthFactor(i_user);

        assertEq(expectedHealthFactor, actualHealthFactor);
    }

    function test_GetHealthFactor_ReturnsExpectedValueAfterMinting() public givenUserDepositedWeth givenUserMintedDsc {
        uint256 ethPrice = uint256(config.ETH_USD_PRICE());
        uint256 totalCollateralValueInUsd = (COLLATERAL_AMOUNT * (ethPrice * ADDITIONAL_FEED_PRECISION)) / PRECISION;
        uint256 collateralAdjustedForThreshold =
            ((totalCollateralValueInUsd * LIQUIDATION_THRESHOLD) / LIQUIDATION_PRECISION) * PRECISION;
        uint256 expectedHealthFactor = collateralAdjustedForThreshold / DSC_AMOUNT;

        uint256 actualHealthFactor = dscEngine.getHealthFactor(i_user);

        assertEq(expectedHealthFactor, actualHealthFactor);
    }

    /*//////////////////////////////////////////////////////////////
                           DEPOSIT COLLATERAL
    //////////////////////////////////////////////////////////////*/
    function test_DepositCollateral_RevertsOnZeroAmount() public {
        vm.prank(i_user);
        vm.expectRevert(DSCEngine.DSCEngine__NeedsMoreThanZero.selector);

        dscEngine.depositCollateral(weth, 0);
    }

    function test_DepositCollateral_RevertsOnInvalidCollateral() public {
        address invalidCollateral = makeAddr("LMAO");

        vm.prank(i_user);
        vm.expectRevert(DSCEngine.DSCEngine__CollateralNotValid.selector);

        dscEngine.depositCollateral(invalidCollateral, COLLATERAL_AMOUNT);
    }

    function test_DepositCollateral_RevertsWhenTransferFails() public {
        ERC20MockRevertable revertableWeth = new ERC20MockRevertable();
        address[] memory collaterals = new address[](2);
        address[] memory priceFeeds = new address[](2);
        (collaterals[0], collaterals[1]) = (address(revertableWeth), wbtc);
        (priceFeeds[0], priceFeeds[1]) = (wethUsdPriceFeed, wbtcUsdPriceFeed);
        DSCEngine engine = new DSCEngine(collaterals, priceFeeds, address(dscToken));

        revertableWeth.mint(i_user, COLLATERAL_AMOUNT);
        revertableWeth.setShouldRevertTrue();

        vm.startPrank(i_user);
        revertableWeth.approve(address(engine), COLLATERAL_AMOUNT);
        vm.expectRevert(DSCEngine.DSCEngine__TransferFailed.selector);

        engine.depositCollateral(address(revertableWeth), COLLATERAL_AMOUNT);
        vm.stopPrank();
    }

    function test_DepositCollateral_StoresUserDepositAndTransfersTokens() public givenUserDepositedWeth {
        uint256 expectedDeposit = COLLATERAL_AMOUNT;
        uint256 expectedEngineBalance = COLLATERAL_AMOUNT;

        uint256 actualDeposit = dscEngine.getCollateralDeposited(i_user, weth);
        uint256 actualEngineBalance = ERC20Mock(weth).balanceOf(address(dscEngine));

        assertEq(expectedDeposit, actualDeposit);
        assertEq(expectedEngineBalance, actualEngineBalance);
    }

    function test_DepositCollateral_EmitsCollateralDeposited() public {
        ERC20Mock(weth).mint(i_user, COLLATERAL_AMOUNT);

        vm.startPrank(i_user);
        ERC20Mock(weth).approve(address(dscEngine), COLLATERAL_AMOUNT);
        vm.expectEmit(true, true, true, false);
        emit DSCEngine.CollateralDeposited(i_user, weth, COLLATERAL_AMOUNT);

        dscEngine.depositCollateral(weth, COLLATERAL_AMOUNT);
        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                        DEPOSIT COLLATERAL AND MINT
    //////////////////////////////////////////////////////////////*/
    function test_DepositCollateralAndMintDsc_StoresCollateralDebtAndHealthFactor() public {
        ERC20Mock(weth).mint(i_user, COLLATERAL_AMOUNT);
        uint256 collateralValueInUsd = dscEngine.getUsdValue(weth, COLLATERAL_AMOUNT) * PRECISION;
        uint256 collateralAdjustedForThreshold = (collateralValueInUsd * LIQUIDATION_THRESHOLD) / LIQUIDATION_PRECISION;
        uint256 expectedHealthFactor = collateralAdjustedForThreshold / DSC_AMOUNT;
        uint256 expectedCollateralDeposited = COLLATERAL_AMOUNT;
        uint256 expectedDscMinted = DSC_AMOUNT;

        vm.startPrank(i_user);
        ERC20Mock(weth).approve(address(dscEngine), COLLATERAL_AMOUNT);
        dscEngine.depositCollateralAndMintDsc(weth, COLLATERAL_AMOUNT, DSC_AMOUNT);
        vm.stopPrank();

        uint256 actualHealthFactor = dscEngine.getHealthFactor(i_user);
        uint256 actualCollateralDeposited = dscEngine.getCollateralDeposited(i_user, weth);
        uint256 actualDscMinted = dscEngine.getDscMinted(i_user);

        assertEq(expectedHealthFactor, actualHealthFactor);
        assertEq(expectedCollateralDeposited, actualCollateralDeposited);
        assertEq(expectedDscMinted, actualDscMinted);
    }

    /*//////////////////////////////////////////////////////////////
                                MINT DSC
    //////////////////////////////////////////////////////////////*/
    function test_MintDsc_RevertsOnZeroAmount() public {
        vm.prank(i_user);
        vm.expectRevert(DSCEngine.DSCEngine__NeedsMoreThanZero.selector);

        dscEngine.mintDsc(0);
    }

    function test_MintDsc_RevertsWhenUserHasNoCollateral() public {
        vm.prank(i_user);
        vm.expectRevert(abi.encodeWithSelector(DSCEngine.DSCEngine__HealthFactorIsBroken.selector, 0));

        dscEngine.mintDsc(DSC_AMOUNT);
    }

    function test_MintDsc_RevertsWhenHealthFactorBreaks() public givenUserDepositedWeth {
        uint256 dscAmountToMint = 50_000e18; // 50,000 DSC (= $50,000) > 10 ETH (= $30,000)
        uint256 healthFactorBeforeMint = dscEngine.getHealthFactor(i_user);

        uint256 collateralValueInUsd = dscEngine.getUsdValue(weth, COLLATERAL_AMOUNT) * PRECISION;
        uint256 collateralAdjustedForThreshold = (collateralValueInUsd * LIQUIDATION_THRESHOLD) / LIQUIDATION_PRECISION;
        uint256 healthFactorAfterMint = collateralAdjustedForThreshold / dscAmountToMint;

        assertGt(healthFactorBeforeMint, healthFactorAfterMint);

        vm.prank(i_user);
        vm.expectRevert(
            abi.encodeWithSelector(DSCEngine.DSCEngine__HealthFactorIsBroken.selector, healthFactorAfterMint)
        );

        dscEngine.mintDsc(dscAmountToMint);
    }

    function test_MintDsc_RevertsWhenTokenMintFails() public {
        ERC20MockRevertable revertableDsc = new ERC20MockRevertable();
        DSCEngine engine = _deployEngineWithDsc(address(revertableDsc));
        _depositWethForUser(engine, COLLATERAL_AMOUNT);

        revertableDsc.setShouldRevertTrue();

        vm.prank(i_user);
        vm.expectRevert(DSCEngine.DSCEngine__MintFalied.selector);

        engine.mintDsc(DSC_AMOUNT);
    }

    function test_MintDsc_StoresDebtAndUpdatesHealthFactor() public givenUserDepositedWeth givenUserMintedDsc {
        uint256 expectedDscMinted = DSC_AMOUNT;
        uint256 collateralValueInUsd = dscEngine.getAccountCollateralValue(i_user) * PRECISION;
        uint256 expectedHealthFactor =
            ((collateralValueInUsd * LIQUIDATION_THRESHOLD) / LIQUIDATION_PRECISION) / DSC_AMOUNT;

        uint256 actualDscMinted = dscEngine.getDscMinted(i_user);
        uint256 actualHealthFactor = dscEngine.getHealthFactor(i_user);

        assertEq(expectedDscMinted, actualDscMinted);
        assertEq(expectedHealthFactor, actualHealthFactor);
    }

    /*//////////////////////////////////////////////////////////////
                                BURN DSC
    //////////////////////////////////////////////////////////////*/
    function test_BurnDsc_RevertsWhenTransferFromFails() public {
        uint256 amountDscToBurn = 1e18;
        ERC20MockRevertable revertableDsc = new ERC20MockRevertable();
        DSCEngine engine = _deployEngineWithDsc(address(revertableDsc));

        _depositWethForUser(engine, COLLATERAL_AMOUNT);
        vm.prank(i_user);
        engine.mintDsc(DSC_AMOUNT);

        revertableDsc.setShouldRevertTrue();
        vm.prank(i_user);
        vm.expectRevert(DSCEngine.DSCEngine__TransferFailed.selector);

        engine.burnDsc(amountDscToBurn);
    }

    function test_BurnDsc_BurnsDebtAndEmitsDscBurned() public givenUserDepositedWeth givenUserMintedDsc {
        uint256 amountToBurn = 10e18;
        uint256 userBalanceBeforeBurn = ERC20Mock(address(dscToken)).balanceOf(i_user);

        vm.startPrank(i_user);
        ERC20Mock(address(dscToken)).approve(address(dscEngine), amountToBurn);
        vm.expectEmit(true, true, true, false);
        emit DSCEngine.DscBurned(i_user, i_user, amountToBurn);

        dscEngine.burnDsc(amountToBurn);
        vm.stopPrank();

        uint256 userBalanceAfterBurn = ERC20Mock(address(dscToken)).balanceOf(i_user);

        assertEq(userBalanceBeforeBurn, userBalanceAfterBurn + amountToBurn);
    }

    /*//////////////////////////////////////////////////////////////
                            REDEEM COLLATERAL
    //////////////////////////////////////////////////////////////*/
    function test_RedeemCollateral_RevertsOnZeroAmount() public {
        vm.prank(i_user);
        vm.expectRevert(DSCEngine.DSCEngine__NeedsMoreThanZero.selector);

        dscEngine.redeemCollateral(weth, 0);
    }

    function test_RedeemCollateral_RevertsOnInvalidCollateral() public {
        address invalidCollateral = makeAddr("haha");

        vm.prank(i_user);
        vm.expectRevert(DSCEngine.DSCEngine__CollateralNotValid.selector);

        dscEngine.redeemCollateral(invalidCollateral, 5);
    }

    function test_RedeemCollateral_RevertsWhenUserHasNoCollateralToRedeem() public {
        vm.prank(i_user);
        vm.expectRevert(DSCEngine.DSCEngine__ThereIsNoCollateralToRedeem.selector);

        dscEngine.redeemCollateral(weth, 10);
    }

    function test_RedeemCollateral_RevertsWhenUsersHealthFactorBreakes() public givenUserDepositedWeth givenUserMintedDsc {
        uint256 amountToRedeem = 999e16;
        uint256 userCollateralValueAfterRedeem = dscEngine.getUsdValue(address(weth), 1e16) * PRECISION;
        uint256 healthFactorAfterRedeem = ((userCollateralValueAfterRedeem * LIQUIDATION_THRESHOLD) / LIQUIDATION_PRECISION) / DSC_AMOUNT;

        vm.prank(i_user);
        vm.expectRevert(abi.encodeWithSelector(DSCEngine.DSCEngine__HealthFactorIsBroken.selector, healthFactorAfterRedeem));
        dscEngine.redeemCollateral(weth, amountToRedeem);
    }

    function test_RedeemCollateral_RedeemsCollateralAndEmitsCollateralRedeemed() public givenUserDepositedWeth {
        uint256 amountToRedeem = 5e18;
        uint256 userCollateralValueBeforeRedeem = dscEngine.getAccountCollateralValue(i_user);
        uint256 engineCollateralAmountBeforeRedeem = ERC20Mock(weth).balanceOf(address(dscEngine));
        uint256 expectedUserCollateralAfterRedeem = 5e18;
        

        vm.prank(i_user);
        vm.expectEmit(true, true, true, true);
        emit DSCEngine.CollateralRedeemed(i_user, i_user, weth, amountToRedeem);

        dscEngine.redeemCollateral(weth, amountToRedeem);

        uint256 userCollateralValueAfterRedeem = dscEngine.getAccountCollateralValue(i_user);
        uint256 userRedeemedCollateralValue = dscEngine.getUsdValue(weth, amountToRedeem);
        uint256 engineCollateralAmountAfterRedeem = ERC20Mock(weth).balanceOf(address(dscEngine));
        uint256 actualUserCollateralAfterRedeem = dscEngine.getCollateralDeposited(i_user, weth);

        uint256 expectedHealthFactor = type(uint256).max;
        uint256 actualHealthFactor = dscEngine.getHealthFactor(i_user);

        assertEq(engineCollateralAmountBeforeRedeem, engineCollateralAmountAfterRedeem + amountToRedeem);
        assertEq(expectedUserCollateralAfterRedeem, actualUserCollateralAfterRedeem);
        assertEq(expectedHealthFactor, actualHealthFactor);
        // NOTE: The following assert dose not work on testnet or mainnet, because of price changing !
        assertEq(userCollateralValueBeforeRedeem, userCollateralValueAfterRedeem + userRedeemedCollateralValue);
    }

    /*//////////////////////////////////////////////////////////////
                               LIQUIDATE
    //////////////////////////////////////////////////////////////*/
    function test_Liquidate_RevertsWhenTargetCollateralDoesNotExist() public givenUserDepositedWeth {
        address liquidator = address(0x1);

        vm.prank(i_user);
        dscEngine.mintDsc(15_000e18);

        ERC20Mock(weth).mint(liquidator, COLLATERAL_AMOUNT);
        vm.startPrank(liquidator);
        ERC20Mock(weth).approve(address(dscEngine), COLLATERAL_AMOUNT);
        dscEngine.depositCollateral(weth, COLLATERAL_AMOUNT);
        dscEngine.mintDsc(10_000e18);
        vm.stopPrank();

        MockV3Aggregator wethPriceFeed = MockV3Aggregator(wethUsdPriceFeed);
        wethPriceFeed.updateAnswer(2500e8);

        vm.startPrank(liquidator);
        ERC20Mock(address(dscToken)).approve(address(dscEngine), 1000e18);
        vm.expectRevert(DSCEngine.DSCEngine__UserDontHaveThisCollateral.selector);

        dscEngine.liquidate(wbtc, i_user, 1000e18);
        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                                HELPERS
    //////////////////////////////////////////////////////////////*/
    function _deployEngineWithDsc(address dscAddress) internal returns (DSCEngine) {
        address[] memory collaterals = new address[](2);
        address[] memory priceFeeds = new address[](2);
        (collaterals[0], collaterals[1]) = (weth, wbtc);
        (priceFeeds[0], priceFeeds[1]) = (wethUsdPriceFeed, wbtcUsdPriceFeed);

        return new DSCEngine(collaterals, priceFeeds, dscAddress);
    }

    function _depositWethForUser(DSCEngine engine, uint256 amount) internal {
        ERC20Mock(weth).mint(i_user, amount);

        vm.startPrank(i_user);
        ERC20Mock(weth).approve(address(engine), amount);
        engine.depositCollateral(weth, amount);
        vm.stopPrank();
    }
}
