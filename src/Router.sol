// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

/// @notice Minimal batch price-data router for pool watchers.
/// @dev This contract is intended to be called via `eth_call`.
/// It batches pool state reads so the offchain indexer can fetch many pools in one RPC request.
contract Router {
    enum PoolKind {
        V2,
        V3,
        InfinityCL
    }

    struct PriceRequest {
        PoolKind kind;
        address pool;
        bytes32 poolId;
    }

    struct PriceResponse {
        bool success;
        PoolKind kind;
        address pool;
        bytes32 poolId;
        uint112 reserve0;
        uint112 reserve1;
        uint32 blockTimestampLast;
        uint160 sqrtPriceX96;
        int24 tick;
        uint128 liquidity;
        uint24 protocolFee;
        uint24 lpFee;
        bytes errorData;
    }

    address public immutable INFINITY_CL_POOL_MANAGER;

    error InvalidInfinityClPoolManager();
    error UnsupportedPoolKind(PoolKind kind);

    constructor(address _infinityClPoolManager) {
        if (_infinityClPoolManager == address(0)) {
            revert InvalidInfinityClPoolManager();
        }

        INFINITY_CL_POOL_MANAGER = _infinityClPoolManager;
    }

    function readPrices(PriceRequest[] calldata requests) external view returns (PriceResponse[] memory responses) {
        responses = new PriceResponse[](requests.length);

        for (uint256 i = 0; i < requests.length; i++) {
            PriceRequest calldata request = requests[i];

            if (request.kind == PoolKind.V2) {
                responses[i] = _readV2(request);
            } else if (request.kind == PoolKind.V3) {
                responses[i] = _readV3(request);
            } else if (request.kind == PoolKind.InfinityCL) {
                responses[i] = _readInfinityCl(request);
            }
        }
    }

    function _readV2(PriceRequest calldata request) internal view returns (PriceResponse memory response) {
        response.kind = request.kind;
        response.pool = request.pool;
        response.poolId = request.poolId;

        try IV2Pool(request.pool)
            .getReserves() returns (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast) {
            response.success = true;
            response.reserve0 = reserve0;
            response.reserve1 = reserve1;
            response.blockTimestampLast = blockTimestampLast;
        } catch (bytes memory errorData) {
            response.errorData = errorData;
        }
    }

    function _readV3(PriceRequest calldata request) internal view returns (PriceResponse memory response) {
        response.kind = request.kind;
        response.pool = request.pool;
        response.poolId = request.poolId;

        try IV3Pool(request.pool)
            .slot0() returns (uint160 sqrtPriceX96, int24 tick, uint16, uint16, uint16, uint8, bool) {
            response.sqrtPriceX96 = sqrtPriceX96;
            response.tick = tick;
        } catch (bytes memory errorData) {
            response.errorData = errorData;
            return response;
        }

        try IV3Pool(request.pool).liquidity() returns (uint128 liquidity) {
            response.success = true;
            response.liquidity = liquidity;
        } catch (bytes memory errorData) {
            response.errorData = errorData;
        }
    }

    function _readInfinityCl(PriceRequest calldata request) internal view returns (PriceResponse memory response) {
        response.kind = request.kind;
        response.pool = INFINITY_CL_POOL_MANAGER;
        response.poolId = request.poolId;

        try IInfinityClPoolManager(INFINITY_CL_POOL_MANAGER)
            .getSlot0(request.poolId) returns (uint160 sqrtPriceX96, int24 tick, uint24 protocolFee, uint24 lpFee) {
            response.sqrtPriceX96 = sqrtPriceX96;
            response.tick = tick;
            response.protocolFee = protocolFee;
            response.lpFee = lpFee;
        } catch (bytes memory errorData) {
            response.errorData = errorData;
            return response;
        }

        try IInfinityClPoolManager(INFINITY_CL_POOL_MANAGER).getLiquidity(request.poolId) returns (uint128 liquidity) {
            response.success = true;
            response.liquidity = liquidity;
        } catch (bytes memory errorData) {
            response.errorData = errorData;
        }
    }
}

interface IV2Pool {
    function getReserves() external view returns (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast);
}

interface IV3Pool {
    function slot0()
        external
        view
        returns (
            uint160 sqrtPriceX96,
            int24 tick,
            uint16 observationIndex,
            uint16 observationCardinality,
            uint16 observationCardinalityNext,
            uint8 feeProtocol,
            bool unlocked
        );

    function liquidity() external view returns (uint128);
}

interface IInfinityClPoolManager {
    function getSlot0(bytes32 id)
        external
        view
        returns (uint160 sqrtPriceX96, int24 tick, uint24 protocolFee, uint24 lpFee);

    function getLiquidity(bytes32 id) external view returns (uint128 liquidity);
}
