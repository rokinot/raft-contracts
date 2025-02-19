// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import { Test } from "forge-std/Test.sol";
import { AggregatorV3Interface } from "../contracts/Dependencies/AggregatorV3Interface.sol";
import { IWstETH } from "../contracts/Dependencies/IWstETH.sol";
import { IPriceOracle } from "../contracts/Oracles/Interfaces/IPriceOracle.sol";
import { ChainlinkPriceOracle } from "../contracts/Oracles/ChainlinkPriceOracle.sol";

contract ChainlinkPriceOracleTest is Test {
    AggregatorV3Interface public constant aggregatorV3StETH =
        AggregatorV3Interface(0xCfE54B5cD566aB89272946F602D76Ea879CAb4a8);
    IWstETH public constant wstETH = IWstETH(0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0);
    ChainlinkPriceOracle public chainlinkPriceOracle;

    function setUp() public {
        vm.createSelectFork("mainnet", 17_214_483);

        chainlinkPriceOracle = new ChainlinkPriceOracle(aggregatorV3StETH, wstETH);
    }

    function testChainlinkWstETHPrice() public {
        vm.warp(1_683_535_099);
        IPriceOracle.PriceOracleResponse memory priceOracleResponse = chainlinkPriceOracle.getPriceOracleResponse();
        assertEq(priceOracleResponse.isBrokenOrFrozen, false);
        assertEq(priceOracleResponse.priceChangeAboveMax, false);
        assertApproxEqAbs(priceOracleResponse.price, 2_084_356e15, 1e15);
    }
}
