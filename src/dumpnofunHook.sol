pragma solidity ^0.8.0;

import {BaseHook} from "v4-periphery/src/base/hooks/BaseHook.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {Hooks} from "v4-core/libraries/Hooks.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {Currency, CurrencyLibrary} from "v4-core/types/Currency.sol";
import {PoolManager} from "v4-core/PoolManager.sol";
import {PoolId} from "v4-core/types/PoolId.sol";
import {TickMath} from "v4-core/libraries/TickMath.sol";
import {TransientStateLibrary} from "v4-core/libraries/TransientStateLibrary.sol";
import {StateLibrary} from "v4-core/libraries/StateLibrary.sol";
import {BalanceDelta} from "v4-core/types/BalanceDelta.sol";
import {FullMath} from "v4-core/libraries/FullMath.sol";
import {FixedPoint96} from "v4-core/libraries/FixedPoint96.sol";

contract dumpnofunHook is BaseHook {
    using CurrencyLibrary for Currency;
    using CurrencySettler for Currency;
    using TransientStateLibrary for IPoolManager;
    using StateLibrary for IPoolManager;

    uint160 public constant SQRT_PRICE_1_1 = 79228162514264337593543950336;
    bytes constant ZERO_BYTES = new bytes(0);
    uint256 public constant BLOCKS_IN_30_DAYS = 216000;
    IPoolManager manager;
    bool private initialLiquidityDeposited;

    mapping(PoolId => address) internal lockupAddress;
    mapping(PoolId => uint256) internal lockupEndDateForPool;
    mapping(PoolId => address) internal createdTokens;

    event AwesomePoolTokenCreated(PoolId id, address tokenAddress);

    // Initialize BaseHook parent contract in the constructor
    constructor(IPoolManager _poolManager) BaseHook(_poolManager) {
        manager = _poolManager;
        initialLiquidityDeposited = false;
    }

    // Required override function for BaseHook to let the PoolManager know which hooks are implemented
    function getHookPermissions()
        public
        pure
        override
        returns (Hooks.Permissions memory)
    {
        return
            Hooks.Permissions({
                beforeInitialize: true,
                afterInitialize: false,
                beforeAddLiquidity: false,
                beforeRemoveLiquidity: false,
                afterAddLiquidity: false,
                afterRemoveLiquidity: false,
                beforeSwap: false,
                afterSwap: false,
                beforeDonate: false,
                afterDonate: false,
                beforeSwapReturnDelta: false,
                afterSwapReturnDelta: false,
                afterAddLiquidityReturnDelta: false,
                afterRemoveLiquidityReturnDelta: false
            });
    }

    function beforeInitialize(
        address,
        PoolKey calldata key,
        uint160,
        bytes calldata
    ) external pure override returns (bytes4) {
        revert();
    }

    function deployPool(
        TokenParams calldata params
    ) external returns (PoolKey memory, SimpleERC20Token token) {
        SimpleERC20Token token = new SimpleERC20Token(msg.sender, params);
        Currency ETH = Currency.wrap(address(0));
        PoolKey memory key = PoolKey(
            ETH,
            Currency.wrap(address(token)),
            3000,
            60,
            this
        );
        manager.initialize(key, SQRT_PRICE_1_1, ZERO_BYTES);
        uint160 sqrtPriceAtTickLower = TickMath.getSqrtPriceAtTick(-1020); // upside of 10+\%
        uint160 sqrtPriceAtTickUpper = TickMath.getSqrtPriceAtTick(0);

        uint128 liquidity = getLiquidityForAmounts(
            SQRT_PRICE_1_1,
            sqrtPriceAtTickLower,
            sqrtPriceAtTickUpper,
            0,
            params.totalSupply
        );

        IPoolManager.ModifyLiquidityParams memory liquidityParams = IPoolManager
            .ModifyLiquidityParams({
                tickLower: -1020,
                tickUpper: 0,
                liquidityDelta: int128(liquidity),
                salt: 0
            });

        BalanceDelta delta = abi.decode(
            manager.unlock(
                abi.encode(CallbackData(msg.sender, key, liquidityParams))
            ),
            (BalanceDelta)
        );

        PoolId poolId = key.toId();
        (uint128 liquidityAfter1, , ) = manager.getPositionInfo(
            poolId,
            address(this),
            -1020,
            0,
            0
        );
        (uint128 liquidityAfter2, , ) = manager.getPositionInfo(
            poolId,
            msg.sender,
            -1020,
            0,
            0
        );

        emit AwesomePoolTokenCreated(poolId, address(token));
        createdTokens[poolId] = address(token);
        lockupAddress[poolId] = msg.sender;
        lockupEndDateForPool[poolId] = block.number + BLOCKS_IN_30_DAYS;
        return (key, token);
    }

    function withdrawLiquidity(
        PoolKey memory key,
        IPoolManager.ModifyLiquidityParams memory liquidityParams
    ) external returns (PoolKey memory) {
        BalanceDelta delta = abi.decode(
            manager.unlock(
                abi.encode(CallbackData(msg.sender, key, liquidityParams))
            ),
            (BalanceDelta)
        );
        return key;
    }

    /// @notice Computes the maximum amount of liquidity received for a given amount of token0, token1, the current
    /// pool prices and the prices at the tick boundaries
    /// @param sqrtPriceX96 A sqrt price representing the current pool prices
    /// @param sqrtPriceAX96 A sqrt price representing the first tick boundary
    /// @param sqrtPriceBX96 A sqrt price representing the second tick boundary
    /// @param amount0 The amount of token0 being sent in
    /// @param amount1 The amount of token1 being sent in
    /// @return liquidity The maximum amount of liquidity received
    function getLiquidityForAmounts(
        uint160 sqrtPriceX96,
        uint160 sqrtPriceAX96,
        uint160 sqrtPriceBX96,
        uint256 amount0,
        uint256 amount1
    ) internal pure returns (uint128 liquidity) {
        if (sqrtPriceAX96 > sqrtPriceBX96)
            (sqrtPriceAX96, sqrtPriceBX96) = (sqrtPriceBX96, sqrtPriceAX96);

        if (sqrtPriceX96 <= sqrtPriceAX96) {
            liquidity = getLiquidityForAmount0(
                sqrtPriceAX96,
                sqrtPriceBX96,
                amount0
            );
        } else if (sqrtPriceX96 < sqrtPriceBX96) {
            uint128 liquidity0 = getLiquidityForAmount0(
                sqrtPriceX96,
                sqrtPriceBX96,
                amount0
            );
            uint128 liquidity1 = getLiquidityForAmount1(
                sqrtPriceAX96,
                sqrtPriceX96,
                amount1
            );

            liquidity = liquidity0 < liquidity1 ? liquidity0 : liquidity1;
        } else {
            liquidity = getLiquidityForAmount1(
                sqrtPriceAX96,
                sqrtPriceBX96,
                amount1
            );
        }
    }

    /// @notice Computes the amount of liquidity received for a given amount of token0 and price range
    /// @dev Calculates amount0 * (sqrt(upper) * sqrt(lower)) / (sqrt(upper) - sqrt(lower))
    /// @param sqrtPriceAX96 A sqrt price representing the first tick boundary
    /// @param sqrtPriceBX96 A sqrt price representing the second tick boundary
    /// @param amount0 The amount0 being sent in
    /// @return liquidity The amount of returned liquidity
    function getLiquidityForAmount0(
        uint160 sqrtPriceAX96,
        uint160 sqrtPriceBX96,
        uint256 amount0
    ) internal pure returns (uint128 liquidity) {
        if (sqrtPriceAX96 > sqrtPriceBX96)
            (sqrtPriceAX96, sqrtPriceBX96) = (sqrtPriceBX96, sqrtPriceAX96);
        uint256 intermediate = FullMath.mulDiv(
            sqrtPriceAX96,
            sqrtPriceBX96,
            FixedPoint96.Q96
        );
        return
            toUint128(
                FullMath.mulDiv(
                    amount0,
                    intermediate,
                    sqrtPriceBX96 - sqrtPriceAX96
                )
            );
    }

    /// @notice Computes the amount of liquidity received for a given amount of token1 and price range
    /// @dev Calculates amount1 / (sqrt(upper) - sqrt(lower)).
    /// @param sqrtPriceAX96 A sqrt price representing the first tick boundary
    /// @param sqrtPriceBX96 A sqrt price representing the second tick boundary
    /// @param amount1 The amount1 being sent in
    /// @return liquidity The amount of returned liquidity
    function getLiquidityForAmount1(
        uint160 sqrtPriceAX96,
        uint160 sqrtPriceBX96,
        uint256 amount1
    ) internal pure returns (uint128 liquidity) {
        if (sqrtPriceAX96 > sqrtPriceBX96)
            (sqrtPriceAX96, sqrtPriceBX96) = (sqrtPriceBX96, sqrtPriceAX96);
        return
            toUint128(
                FullMath.mulDiv(
                    amount1,
                    FixedPoint96.Q96,
                    sqrtPriceBX96 - sqrtPriceAX96
                )
            );
    }

    /// @notice Downcasts uint256 to uint128
    /// @param x The uint258 to be downcasted
    /// @return y The passed value, downcasted to uint128
    function toUint128(uint256 x) private pure returns (uint128 y) {
        require((y = uint128(x)) == x, "liquidity overflow");
    }

    function _unlockCallback(
        bytes calldata rawData
    ) internal virtual override returns (bytes memory) {
        CallbackData memory data = abi.decode(rawData, (CallbackData));
        if (initialLiquidityDeposited) {
            require(
                data.sender == lockupAddress[data.key.toId()] &&
                    block.number >= lockupEndDateForPool[data.key.toId()],
                "Liquidity is locked"
            );
        } else {
            initialLiquidityDeposited = true;
        }
        (uint128 liquidityBefore, , ) = manager.getPositionInfo(
            data.key.toId(),
            address(this),
            data.params.tickLower,
            data.params.tickUpper,
            data.params.salt
        );

        (BalanceDelta delta, ) = manager.modifyLiquidity(
            data.key,
            data.params,
            ""
        );

        (uint128 liquidityAfter, , ) = manager.getPositionInfo(
            data.key.toId(),
            address(this),
            data.params.tickLower,
            data.params.tickUpper,
            data.params.salt
        );

        (, , int256 delta0) = _fetchBalances(
            data.key.currency0,
            data.sender,
            address(this)
        );
        (, , int256 delta1) = _fetchBalances(
            data.key.currency1,
            data.sender,
            address(this)
        );
        require(
            int128(liquidityBefore) + data.params.liquidityDelta ==
                int128(liquidityAfter),
            "liquidity change incorrect"
        );

        if (data.params.liquidityDelta < 0) {
            assert(delta0 > 0 || delta1 > 0);
            assert(!(delta0 < 0 || delta1 < 0));
        } else if (data.params.liquidityDelta > 0) {
            assert(delta0 < 0 || delta1 < 0);
            assert(!(delta0 > 0 || delta1 > 0));
        }

        if (delta0 < 0)
            data.key.currency0.settle(manager, data.sender, uint256(-delta0));
        if (delta1 < 0)
            data.key.currency1.settle(manager, data.sender, uint256(-delta1));

        if (delta0 > 0)
            data.key.currency0.take(manager, data.sender, uint256(delta0));
        if (delta1 > 0)
            data.key.currency1.take(manager, data.sender, uint256(delta1));

        return abi.encode(delta);
    }

    function _fetchBalances(
        Currency currency,
        address user,
        address deltaHolder
    )
        internal
        view
        returns (uint256 userBalance, uint256 poolBalance, int256 delta)
    {
        userBalance = currency.balanceOf(user);
        poolBalance = currency.balanceOf(address(manager));
        delta = manager.currencyDelta(deltaHolder, currency);
    }
}

struct TokenParams {
    string name; // Token name
    string symbol; // Token symbol
    uint8 decimals; // Token decimal places
    uint256 totalSupply; // Total supply of the token
}

struct CallbackData {
    address sender;
    PoolKey key;
    IPoolManager.ModifyLiquidityParams params;
}

contract SimpleERC20Token {
    string public name; // Token name
    string public symbol; // Token symbol
    uint8 public decimals; // Token decimal places
    uint256 public totalSupply; // Total supply of the token

    mapping(address => uint256) private balances; // Mapping of address to balance
    mapping(address => mapping(address => uint256)) private allowances; // Allowance mapping

    // Events as per the ERC-20 standard
    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(
        address indexed owner,
        address indexed spender,
        uint256 value
    );

    // Constructor to set the token details and mint initial supply to the deployer
    constructor(address tokenCreator, TokenParams memory params) {
        name = params.name;
        symbol = params.symbol;
        decimals = params.decimals;
        totalSupply = params.totalSupply * 10 ** uint256(decimals); // Set total supply with decimals
        balances[tokenCreator] = params.totalSupply; // Assign the entire supply to the deployer
        allowances[tokenCreator][msg.sender] = totalSupply; // Approve the PoolManager to spend the total supply
        emit Transfer(address(0), msg.sender, totalSupply); // Emit transfer event from zero address to deployer
    }

    // Function to check the balance of an address
    function balanceOf(address account) public view returns (uint256) {
        return balances[account];
    }

    // Function to transfer tokens to another address
    function transfer(address to, uint256 amount) public returns (bool) {
        require(to != address(0), "ERC20: transfer to the zero address");
        require(
            balances[msg.sender] >= amount,
            "ERC20: transfer amount exceeds balance"
        );

        balances[msg.sender] -= amount; // Deduct from sender
        balances[to] += amount; // Add to recipient

        emit Transfer(msg.sender, to, amount); // Emit Transfer event
        return true;
    }

    // Function to approve another address to spend tokens on behalf of the caller
    function approve(address spender, uint256 amount) public returns (bool) {
        require(spender != address(0), "ERC20: approve to the zero address");

        allowances[msg.sender][spender] = amount; // Set allowance

        emit Approval(msg.sender, spender, amount); // Emit Approval event
        return true;
    }

    // Function to check the allowance of a spender on behalf of an owner
    function allowance(
        address owner,
        address spender
    ) public view returns (uint256) {
        return allowances[owner][spender];
    }

    // Function to transfer tokens on behalf of another address (using allowance)
    function transferFrom(
        address from,
        address to,
        uint256 amount
    ) public returns (bool) {
        require(to != address(0), "ERC20: transfer to the zero address");
        require(
            balances[from] >= amount,
            "ERC20: transfer amount exceeds balance"
        );
        require(
            allowances[from][msg.sender] >= amount,
            "ERC20: transfer amount exceeds allowance"
        );

        balances[from] -= amount; // Deduct from the owner
        balances[to] += amount; // Add to the recipient
        allowances[from][msg.sender] -= amount; // Reduce the allowance

        emit Transfer(from, to, amount); // Emit Transfer event
        return true;
    }
}

/// @notice Library used to interact with PoolManager.sol to settle any open deltas.
/// To settle a positive delta (a credit to the user), a user may take or mint.
/// To settle a negative delta (a debt on the user), a user make transfer or burn to pay off a debt.
/// @dev Note that sync() is called before any erc-20 transfer in `settle`.
library CurrencySettler {
    /// @notice Settle (pay) a currency to the PoolManager
    /// @param currency Currency to settle
    /// @param manager IPoolManager to settle to
    /// @param payer Address of the payer, the token sender
    /// @param amount Amount to send
    function settle(
        Currency currency,
        IPoolManager manager,
        address payer,
        uint256 amount
    ) internal {
        // for native currencies or burns, calling sync is not required
        // short circuit for ERC-6909 burns to support ERC-6909-wrapped native tokens
        if (currency.isAddressZero()) {
            manager.settle{value: amount}();
        } else {
            manager.sync(currency);
            if (payer != address(this)) {
                SimpleERC20Token(Currency.unwrap(currency)).transferFrom(
                    payer,
                    address(manager),
                    amount
                );
            } else {
                SimpleERC20Token(Currency.unwrap(currency)).transfer(
                    address(manager),
                    amount
                );
            }
            manager.settle();
        }
    }

    /// @notice Take (receive) a currency from the PoolManager
    /// @param currency Currency to take
    /// @param manager IPoolManager to take from
    /// @param recipient Address of the recipient, the token receiver
    /// @param amount Amount to receive
    function take(
        Currency currency,
        IPoolManager manager,
        address recipient,
        uint256 amount
    ) internal {
        manager.take(currency, recipient, amount);
    }
}
