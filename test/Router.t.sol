// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import {Test} from "forge-std/Test.sol";
import {Router} from "../src/Router.sol";

contract RouterTest is Test {
    MockV2Pool internal v2Pool;
    MockV3Pool internal v3Pool;
    MockInfinityClPoolManager internal infinityClPoolManager;
    Router internal router;

    bytes32 internal constant INFINITY_POOL_ID = 0x673dbd89b4de73f139ccca01f515536d386bc993c35efb3abf0a4d4b02b6dd20;

    function setUp() public {
        v2Pool = new MockV2Pool();
        v3Pool = new MockV3Pool();
        infinityClPoolManager = new MockInfinityClPoolManager();
        router = new Router(address(infinityClPoolManager));
    }

    function test_constructor_reverts_for_zero_infinity_manager() public {
        vm.expectRevert(Router.InvalidInfinityClPoolManager.selector);
        new Router(address(0));
    }

    function test_readPrices_reads_v2_reserves() public {
        v2Pool.setReserves(100 ether, 5 ether, 123456);

        Router.PriceRequest[] memory requests = new Router.PriceRequest[](1);
        requests[0] = Router.PriceRequest({kind: Router.PoolKind.V2, pool: address(v2Pool), poolId: bytes32(0)});

        Router.PriceResponse[] memory responses = router.readPrices(requests);

        assertEq(responses.length, 1);
        assertTrue(responses[0].success);
        assertEq(uint8(responses[0].kind), uint8(Router.PoolKind.V2));
        assertEq(responses[0].pool, address(v2Pool));
        assertEq(responses[0].reserve0, 100 ether);
        assertEq(responses[0].reserve1, 5 ether);
        assertEq(responses[0].blockTimestampLast, 123456);
        assertEq(responses[0].sqrtPriceX96, 0);
        assertEq(responses[0].liquidity, 0);
        assertEq(responses[0].errorData.length, 0);
    }

    function test_readPrices_reads_v3_slot0_and_liquidity() public {
        v3Pool.setSlot0(79228162514264337593543950336, -123, 42_000 ether);

        Router.PriceRequest[] memory requests = new Router.PriceRequest[](1);
        requests[0] = Router.PriceRequest({kind: Router.PoolKind.V3, pool: address(v3Pool), poolId: bytes32(0)});

        Router.PriceResponse[] memory responses = router.readPrices(requests);

        assertEq(responses.length, 1);
        assertTrue(responses[0].success);
        assertEq(uint8(responses[0].kind), uint8(Router.PoolKind.V3));
        assertEq(responses[0].pool, address(v3Pool));
        assertEq(responses[0].sqrtPriceX96, 79228162514264337593543950336);
        assertEq(responses[0].tick, -123);
        assertEq(responses[0].liquidity, 42_000 ether);
        assertEq(responses[0].reserve0, 0);
        assertEq(responses[0].reserve1, 0);
        assertEq(responses[0].errorData.length, 0);
    }

    function test_readPrices_reads_infinity_cl_slot0_and_liquidity() public {
        infinityClPoolManager.setPool(
            INFINITY_POOL_ID, 1461446703485210103287273052203988822378723970342, 887272, 67, 67, 9_999 ether
        );

        Router.PriceRequest[] memory requests = new Router.PriceRequest[](1);
        requests[0] =
            Router.PriceRequest({kind: Router.PoolKind.InfinityCL, pool: address(0), poolId: INFINITY_POOL_ID});

        Router.PriceResponse[] memory responses = router.readPrices(requests);

        assertEq(responses.length, 1);
        assertTrue(responses[0].success);
        assertEq(uint8(responses[0].kind), uint8(Router.PoolKind.InfinityCL));
        assertEq(responses[0].pool, address(infinityClPoolManager));
        assertEq(responses[0].poolId, INFINITY_POOL_ID);
        assertEq(responses[0].sqrtPriceX96, 1461446703485210103287273052203988822378723970342);
        assertEq(responses[0].tick, 887272);
        assertEq(responses[0].protocolFee, 67);
        assertEq(responses[0].lpFee, 67);
        assertEq(responses[0].liquidity, 9_999 ether);
        assertEq(responses[0].errorData.length, 0);
    }

    function test_readPrices_reads_mixed_batch() public {
        v2Pool.setReserves(10 ether, 1 ether, 111);
        v3Pool.setSlot0(79228162514264337593543950336, 0, 20 ether);
        infinityClPoolManager.setPool(INFINITY_POOL_ID, 79228162514264337593543950336, 0, 67, 67, 30 ether);

        Router.PriceRequest[] memory requests = new Router.PriceRequest[](3);
        requests[0] = Router.PriceRequest({kind: Router.PoolKind.V2, pool: address(v2Pool), poolId: bytes32(0)});
        requests[1] = Router.PriceRequest({kind: Router.PoolKind.V3, pool: address(v3Pool), poolId: bytes32(0)});
        requests[2] =
            Router.PriceRequest({kind: Router.PoolKind.InfinityCL, pool: address(0), poolId: INFINITY_POOL_ID});

        Router.PriceResponse[] memory responses = router.readPrices(requests);

        assertEq(responses.length, 3);
        assertTrue(responses[0].success);
        assertTrue(responses[1].success);
        assertTrue(responses[2].success);
        assertEq(responses[0].reserve0, 10 ether);
        assertEq(responses[1].liquidity, 20 ether);
        assertEq(responses[2].liquidity, 30 ether);
    }

    function test_readPrices_marks_item_failed_when_v2_pool_reverts() public {
        v2Pool.setShouldRevert(true);

        Router.PriceRequest[] memory requests = new Router.PriceRequest[](1);
        requests[0] = Router.PriceRequest({kind: Router.PoolKind.V2, pool: address(v2Pool), poolId: bytes32(0)});

        Router.PriceResponse[] memory responses = router.readPrices(requests);

        assertEq(responses.length, 1);
        assertFalse(responses[0].success);
        assertEq(uint8(responses[0].kind), uint8(Router.PoolKind.V2));
        assertEq(responses[0].pool, address(v2Pool));
        assertGt(responses[0].errorData.length, 0);
    }

    function test_readPrices_marks_item_failed_when_v3_slot0_reverts() public {
        v3Pool.setShouldRevertSlot0(true);

        Router.PriceRequest[] memory requests = new Router.PriceRequest[](1);
        requests[0] = Router.PriceRequest({kind: Router.PoolKind.V3, pool: address(v3Pool), poolId: bytes32(0)});

        Router.PriceResponse[] memory responses = router.readPrices(requests);

        assertEq(responses.length, 1);
        assertFalse(responses[0].success);
        assertEq(uint8(responses[0].kind), uint8(Router.PoolKind.V3));
        assertEq(responses[0].pool, address(v3Pool));
        assertGt(responses[0].errorData.length, 0);
    }

    function test_readPrices_marks_item_failed_when_v3_liquidity_reverts() public {
        v3Pool.setShouldRevertLiquidity(true);

        Router.PriceRequest[] memory requests = new Router.PriceRequest[](1);
        requests[0] = Router.PriceRequest({kind: Router.PoolKind.V3, pool: address(v3Pool), poolId: bytes32(0)});

        Router.PriceResponse[] memory responses = router.readPrices(requests);

        assertEq(responses.length, 1);
        assertFalse(responses[0].success);
        assertEq(responses[0].sqrtPriceX96, 79228162514264337593543950336);
        assertGt(responses[0].errorData.length, 0);
    }

    function test_readPrices_marks_item_failed_when_infinity_slot0_reverts() public {
        infinityClPoolManager.setShouldRevertSlot0(true);

        Router.PriceRequest[] memory requests = new Router.PriceRequest[](1);
        requests[0] =
            Router.PriceRequest({kind: Router.PoolKind.InfinityCL, pool: address(0), poolId: INFINITY_POOL_ID});

        Router.PriceResponse[] memory responses = router.readPrices(requests);

        assertEq(responses.length, 1);
        assertFalse(responses[0].success);
        assertEq(uint8(responses[0].kind), uint8(Router.PoolKind.InfinityCL));
        assertEq(responses[0].pool, address(infinityClPoolManager));
        assertEq(responses[0].poolId, INFINITY_POOL_ID);
        assertGt(responses[0].errorData.length, 0);
    }

    function test_readPrices_marks_item_failed_when_infinity_liquidity_reverts() public {
        infinityClPoolManager.setPool(INFINITY_POOL_ID, 79228162514264337593543950336, 0, 67, 67, 1 ether);
        infinityClPoolManager.setShouldRevertLiquidity(true);

        Router.PriceRequest[] memory requests = new Router.PriceRequest[](1);
        requests[0] =
            Router.PriceRequest({kind: Router.PoolKind.InfinityCL, pool: address(0), poolId: INFINITY_POOL_ID});

        Router.PriceResponse[] memory responses = router.readPrices(requests);

        assertEq(responses.length, 1);
        assertFalse(responses[0].success);
        assertEq(responses[0].sqrtPriceX96, 79228162514264337593543950336);
        assertEq(responses[0].protocolFee, 67);
        assertEq(responses[0].lpFee, 67);
        assertGt(responses[0].errorData.length, 0);
    }
}

contract MockV2Pool {
    bool internal shouldRevert;
    uint112 internal reserve0;
    uint112 internal reserve1;
    uint32 internal blockTimestampLast;

    function setReserves(uint112 _reserve0, uint112 _reserve1, uint32 _blockTimestampLast) external {
        reserve0 = _reserve0;
        reserve1 = _reserve1;
        blockTimestampLast = _blockTimestampLast;
    }

    function setShouldRevert(bool _shouldRevert) external {
        shouldRevert = _shouldRevert;
    }

    function getReserves() external view returns (uint112, uint112, uint32) {
        if (shouldRevert) {
            revert("V2_REVERT");
        }

        return (reserve0, reserve1, blockTimestampLast);
    }
}

contract MockV3Pool {
    bool internal shouldRevertSlot0;
    bool internal shouldRevertLiquidity;
    uint160 internal sqrtPriceX96 = 79228162514264337593543950336;
    int24 internal tick;
    uint128 internal poolLiquidity = 1 ether;

    function setSlot0(uint160 _sqrtPriceX96, int24 _tick, uint128 _liquidity) external {
        sqrtPriceX96 = _sqrtPriceX96;
        tick = _tick;
        poolLiquidity = _liquidity;
    }

    function setShouldRevertSlot0(bool _shouldRevertSlot0) external {
        shouldRevertSlot0 = _shouldRevertSlot0;
    }

    function setShouldRevertLiquidity(bool _shouldRevertLiquidity) external {
        shouldRevertLiquidity = _shouldRevertLiquidity;
    }

    function slot0() external view returns (uint160, int24, uint16, uint16, uint16, uint8, bool) {
        if (shouldRevertSlot0) {
            revert("V3_SLOT0_REVERT");
        }

        return (sqrtPriceX96, tick, 0, 0, 0, 0, true);
    }

    function liquidity() external view returns (uint128) {
        if (shouldRevertLiquidity) {
            revert("V3_LIQUIDITY_REVERT");
        }

        return poolLiquidity;
    }
}

contract MockInfinityClPoolManager {
    struct PoolData {
        uint160 sqrtPriceX96;
        int24 tick;
        uint24 protocolFee;
        uint24 lpFee;
        uint128 liquidity;
    }

    bool internal shouldRevertSlot0;
    bool internal shouldRevertLiquidity;
    mapping(bytes32 => PoolData) internal pools;

    constructor() {
        pools[bytes32(0)] = PoolData({
            sqrtPriceX96: 79228162514264337593543950336, tick: 0, protocolFee: 67, lpFee: 67, liquidity: 1 ether
        });
    }

    function setPool(
        bytes32 poolId,
        uint160 sqrtPriceX96,
        int24 tick,
        uint24 protocolFee,
        uint24 lpFee,
        uint128 liquidity
    ) external {
        pools[poolId] = PoolData({
            sqrtPriceX96: sqrtPriceX96, tick: tick, protocolFee: protocolFee, lpFee: lpFee, liquidity: liquidity
        });
    }

    function setShouldRevertSlot0(bool _shouldRevertSlot0) external {
        shouldRevertSlot0 = _shouldRevertSlot0;
    }

    function setShouldRevertLiquidity(bool _shouldRevertLiquidity) external {
        shouldRevertLiquidity = _shouldRevertLiquidity;
    }

    function getSlot0(bytes32 id) external view returns (uint160, int24, uint24, uint24) {
        if (shouldRevertSlot0) {
            revert("INFINITY_SLOT0_REVERT");
        }

        PoolData memory pool = pools[id];
        return (pool.sqrtPriceX96, pool.tick, pool.protocolFee, pool.lpFee);
    }

    function getLiquidity(bytes32 id) external view returns (uint128) {
        if (shouldRevertLiquidity) {
            revert("INFINITY_LIQUIDITY_REVERT");
        }

        return pools[id].liquidity;
    }
}
