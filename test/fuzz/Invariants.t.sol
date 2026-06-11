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

    function setUp() external {
        deployer = new DeployDSC();
        (dsc, dsce, config) = deployer.run();
        (wethUsdPriceFeed, wbtcUsdPriceFeed ,weth, wbtc,) = config.activeNetworkConfig();
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

        console.log("weth: ", totalWeth / 1e18);
        console.log("wbtc: ", totalWbtc / 1e18);
        console.log("totalDscSupply: ", totalDscSupply / 1e18);
        console.log("totalCollateralValue: ", totalCollateralValue / 1e18);
        console.log("Adjusted: ", ((totalCollateralValue * LIQUIDATION_PRECISION) / LIQUIDATION_PRECISION) / 1e18);

        assertGe((totalCollateralValue * LIQUIDATION_PRECISION) / LIQUIDATION_PRECISION , totalDscSupply);
    }

    // function invariant_testHealthFactor
}