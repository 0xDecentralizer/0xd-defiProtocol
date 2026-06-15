// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.30;

import {StdInvariant} from "forge-std/StdInvariant.sol";
import {Test, console} from "forge-std/Test.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";
import {DeployDSC} from "../../script/DeployDSC.s.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import {Handler} from "../handler/Handler.t.sol";

contract InvariantTest is StdInvariant, Test {
    DeployDSC deployer;
    DSCEngine dsce;
    DecentralizedStableCoin dsc;
    HelperConfig config;
    address weth;
    address wbtc;
    address wethUsdPriceFeed;
    address wbtcUsdPriceFeed;
    Handler handler;

    uint256 private constant LIQUIDATION_THRESHOLD = 50;
    uint256 private constant LIQUIDATION_PRECISION = 100;
    uint256 private constant PRECISION = 100;

    function setUp() external {
        deployer = new DeployDSC();
        (dsc, dsce, config) = deployer.run();
        (wethUsdPriceFeed, wbtcUsdPriceFeed, weth, wbtc,) = config.activeNetworkConfig();
        handler = new Handler(dsce, dsc, config);
        targetContract(address(handler));
    }

    function invariant_testCollateralValueShouldBeGreaterThanTotalDscSupply() public {
        uint256 totalWeth = ERC20Mock(weth).balanceOf(address(dsce));
        uint256 totalWbtc = ERC20Mock(wbtc).balanceOf(address(dsce));

        uint256 wethUsdValue = dsce.getUsdValue(weth, totalWeth);
        uint256 wbtcUsdValue = dsce.getUsdValue(wbtc, totalWbtc);

        uint256 totalCollateralValue = wethUsdValue + wbtcUsdValue;
        uint256 totalDscSupply = dsc.totalSupply();
        uint256 maxProtocolPain = ((totalCollateralValue * LIQUIDATION_THRESHOLD) / LIQUIDATION_PRECISION);

        console.log("weth: ", totalWeth / PRECISION);
        console.log("wbtc: ", totalWbtc / PRECISION);
        console.log("totalDscSupply: ", totalDscSupply / PRECISION);
        console.log("totalCollateralValue: ", totalCollateralValue / PRECISION);
        console.log("Adjusted: ", maxProtocolPain / PRECISION);

        console.log("deposit called: ", handler.ghost_depositCalled());
        console.log("redeem called: ", handler.ghost_redeemCalled());
        console.log("mint called: ", handler.ghost_mintCalled());
        assertGe(maxProtocolPain, totalDscSupply);
    }

    // function invariant_testHealthFactor
}
