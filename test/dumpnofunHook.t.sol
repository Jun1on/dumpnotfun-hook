// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";
import {Deployers} from "@uniswap/v4-core/test/utils/Deployers.sol";
import {MockERC20} from "solmate/src/test/utils/mocks/MockERC20.sol";
import {PoolManager} from "v4-core/PoolManager.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {Currency, CurrencyLibrary} from "v4-core/types/Currency.sol";
import {PoolId, PoolIdLibrary} from "v4-core/types/PoolId.sol";
import {LPFeeLibrary} from "v4-core/libraries/LPFeeLibrary.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {Hooks} from "v4-core/libraries/Hooks.sol";
import {PoolSwapTest} from "v4-core/test/PoolSwapTest.sol";
import {dumpnofunHook, SimpleERC20Token, TokenParams} from "../src/dumpnofunHook.sol";
import {TickMath} from "v4-core/libraries/TickMath.sol";
import {StateLibrary} from "v4-core/libraries/StateLibrary.sol";
import {BalanceDelta,BalanceDeltaLibrary} from "v4-core/types/BalanceDelta.sol";

import {console} from "forge-std/console.sol";

contract dumpnofunHookTest is Test, Deployers {
    using CurrencyLibrary for Currency;
    using PoolIdLibrary for PoolKey;
    using StateLibrary for IPoolManager;
    using BalanceDeltaLibrary for BalanceDelta;

    dumpnofunHook myHook;

    function setUp() public {
    // Deploy v4-core
    deployFreshManagerAndRouters();

    // Deploy, mint tokens, and approve all periphery contracts for two tokens
    deployMintAndApprove2Currencies();

    address hookAddress = address(
        uint160(
            Hooks.BEFORE_INITIALIZE_FLAG
        )
    );
    deployCodeTo("dumpnofunHook", abi.encode(manager), hookAddress);
    myHook = dumpnofunHook(hookAddress);
    }


    function testTokenCreation() public {
        SimpleERC20Token token = new SimpleERC20Token(address(this),TokenParams("GatorCoin", "GC", 6, 1000));

        assertTrue(token.totalSupply() == 1000000000, "Token incorrect supply.");
        assertTrue(keccak256(abi.encodePacked(token.symbol())) == keccak256(abi.encodePacked("GC")), "Token incorrect symbol.");

    }

    function testPoolCreation() public {
        (PoolKey memory key, SimpleERC20Token token) = myHook.deployPool(TokenParams("GatorCoin", "GC", 6, 1000000));
        PoolId poolId = key.toId();
        (uint160 sqrtPriceX96, int24 tick, uint24 protocolFee, uint24 lpFee) = manager.getSlot0(poolId);
        (uint128 liquidity,,) = manager.getPositionInfo(poolId, address(myHook), -1020, 0, 0);

        assertTrue(sqrtPriceX96 > 0, "Pool not initialized");
        assertTrue(liquidity > 0, "No liquidity in pool");        
    }

    function testCreateFraudPoolFails() public {
        Currency USDC = Currency.wrap(address(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48));
        Currency ETH = Currency.wrap(address(0));
        PoolKey memory key = PoolKey(ETH, USDC, 3000, 60, myHook);
        vm.expectRevert();
        manager.initialize(key, SQRT_PRICE_1_1, ZERO_BYTES);
    }

    function testWithdrawLiquidity() public {
        uint256 totalSupply = 1000000000;
        (PoolKey memory key, SimpleERC20Token token) = myHook.deployPool(TokenParams("GatorCoin", "GC", 6, totalSupply));
        PoolId poolId = key.toId();
        (uint128 liquidity,,) = manager.getPositionInfo(poolId, address(myHook), -1020, 0, 0);

        IPoolManager.ModifyLiquidityParams memory liquidityParams = IPoolManager.ModifyLiquidityParams(-1020,0,-int128(liquidity),0);
        
        vm.roll(216001);
        
        myHook.withdrawLiquidity(key, liquidityParams);

        (uint128 liquidityafter,,) = manager.getPositionInfo(poolId, address(myHook), -1020, 0, 0);

        assertTrue(liquidity > 0, "No liquidity initially in pool");
        assertTrue(liquidityafter == 0, "Initial liquidity failed to withdraw");
        assertApproxEqAbs(totalSupply, token.balanceOf(address(this)), 1);        
    }

    function testWithdrawLiquidityFailureTooEarly() public {
        uint256 totalSupply = 1000000000;
        (PoolKey memory key, SimpleERC20Token token) = myHook.deployPool(TokenParams("GatorCoin", "GC", 6, totalSupply));
        PoolId poolId = key.toId();
        (uint128 liquidity,,) = manager.getPositionInfo(poolId, address(myHook), -1020, 0, 0);

        IPoolManager.ModifyLiquidityParams memory liquidityParams = IPoolManager.ModifyLiquidityParams(-1020,0,-int128(liquidity),0);
        
        vm.expectRevert();
        myHook.withdrawLiquidity(key, liquidityParams); 
    }

    function testWithdrawLiquidityFailureWrongUser() public {
        uint256 totalSupply = 1000000000;
        (PoolKey memory key, SimpleERC20Token token) = myHook.deployPool(TokenParams("GatorCoin", "GC", 6, totalSupply));
        PoolId poolId = key.toId();
        (uint128 liquidity,,) = manager.getPositionInfo(poolId, address(myHook), -1020, 0, 0);

        IPoolManager.ModifyLiquidityParams memory liquidityParams = IPoolManager.ModifyLiquidityParams(-1020,0,-int128(liquidity),0);
        
        address otherUser = address(0x999);
        vm.prank(otherUser);

        vm.expectRevert();
        myHook.withdrawLiquidity(key, liquidityParams); 
    }

    function testSwap() public {
        (PoolKey memory key, SimpleERC20Token token) = myHook.deployPool(TokenParams("GatorCoin", "GC", 6, 1000000));
        PoolId poolId = key.toId();

        BalanceDelta delta = swapRouter.swap{value: 100 wei}(key, IPoolManager.SwapParams({
            zeroForOne: true,
            amountSpecified: -100 wei, // Exact input for output swap
            sqrtPriceLimitX96: TickMath.MIN_SQRT_PRICE + 1
        }), PoolSwapTest.TestSettings({
            takeClaims: false,
            settleUsingBurn: false
        }), "");

        (uint160 sqrtPriceX96, , ,) = manager.getSlot0(poolId);        
        assertTrue(sqrtPriceX96 < SQRT_PRICE_1_1, "Trade not executed");
        assertTrue(delta.amount0() < 0, "ETH direction is wrong");
        assertTrue(delta.amount1() > 0, "Meme Token direction is wrong");        
    }

    function testSwapAndRemoveLiquidity() public {
        (PoolKey memory key, SimpleERC20Token token) = myHook.deployPool(TokenParams("GatorCoin", "GC", 18, 1000000));
        PoolId poolId = key.toId();

        swapRouter.swap{value: 100 wei}(key, IPoolManager.SwapParams({
            zeroForOne: true,
            amountSpecified: -100 wei, // Exact input for output swap
            sqrtPriceLimitX96: TickMath.MIN_SQRT_PRICE + 1
        }), PoolSwapTest.TestSettings({
            takeClaims: false,
            settleUsingBurn: false
        }), "");

        vm.roll(216001);

        uint256 initialETHbalance = address(this).balance;
        uint256 initialTokenbalance = token.balanceOf(address(this));
        
        (uint128 liquidity,,) = manager.getPositionInfo(poolId, address(myHook), -1020, 0, 0);
        
        IPoolManager.ModifyLiquidityParams memory liquidityParams = IPoolManager.ModifyLiquidityParams(-1020,0,-int128(liquidity),0);

        myHook.withdrawLiquidity(key, liquidityParams);

        (uint128 liquidityafter,,) = manager.getPositionInfo(poolId, address(myHook), -1020, 0, 0);

        uint256 finalETHbalance = address(this).balance;
        uint256 finalTokenbalance = token.balanceOf(address(this));

        assertTrue(liquidityafter == 0, "Initial liquidity failed to withdraw");
        assertTrue(finalETHbalance > initialETHbalance, "No ETH received");
        assertTrue(finalTokenbalance > initialTokenbalance, "No Token received");
    }

}
