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

        for (uint256 i; i < requests.length;) {
            PriceRequest calldata request = requests[i];

            if (request.kind == PoolKind.V2) {
                responses[i] = _readV2(request);
            } else if (request.kind == PoolKind.V3) {
                responses[i] = _readV3(request);
            } else if (request.kind == PoolKind.InfinityCL) {
                responses[i] = _readInfinityCl(request);
            } else {
                responses[i].kind = request.kind;
                responses[i].pool = request.pool;
                responses[i].poolId = request.poolId;
                responses[i].errorData = abi.encodeWithSelector(UnsupportedPoolKind.selector, request.kind);
            }

            unchecked {
                ++i;
            }
        }
    }

    function _readV2(PriceRequest calldata request) internal view returns (PriceResponse memory response) {
        response.kind = request.kind;
        response.pool = request.pool;
        response.poolId = request.poolId;

        (bool success, bytes memory data) = request.pool.staticcall(abi.encodeCall(IV2Pool.getReserves, ()));
        if (!success) {
            response.errorData = data;
            return response;
        }

        if (data.length != 96) {
            response.errorData = data;
            return response;
        }

        (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast) = abi.decode(data, (uint112, uint112, uint32));
        response.success = true;
        response.reserve0 = reserve0;
        response.reserve1 = reserve1;
        response.blockTimestampLast = blockTimestampLast;
    }

    function _readV3(PriceRequest calldata request) internal view returns (PriceResponse memory response) {
        response.kind = request.kind;
        response.pool = request.pool;
        response.poolId = request.poolId;

        (bool slot0Success, bytes memory slot0Data) = request.pool.staticcall(abi.encodeCall(IV3Pool.slot0, ()));
        if (!slot0Success) {
            response.errorData = slot0Data;
            return response;
        }

        if (slot0Data.length != 224) {
            response.errorData = slot0Data;
            return response;
        }

        (uint160 sqrtPriceX96, int24 tick,,,,,) =
            abi.decode(slot0Data, (uint160, int24, uint16, uint16, uint16, uint32, bool));

        response.sqrtPriceX96 = sqrtPriceX96;
        response.tick = tick;

        (bool liquiditySuccess, bytes memory liquidityData) =
            request.pool.staticcall(abi.encodeCall(IV3Pool.liquidity, ()));
        if (!liquiditySuccess) {
            response.errorData = liquidityData;
            return response;
        }

        if (liquidityData.length != 32) {
            response.errorData = liquidityData;
            return response;
        }

        uint128 liquidity = abi.decode(liquidityData, (uint128));
        response.success = true;
        response.sqrtPriceX96 = sqrtPriceX96;
        response.tick = tick;
        response.liquidity = liquidity;
    }

    function _readInfinityCl(PriceRequest calldata request) internal view returns (PriceResponse memory response) {
        response.kind = request.kind;
        response.pool = INFINITY_CL_POOL_MANAGER;
        response.poolId = request.poolId;

        (bool slot0Success, bytes memory slot0Data) =
            INFINITY_CL_POOL_MANAGER.staticcall(abi.encodeCall(IInfinityClPoolManager.getSlot0, (request.poolId)));
        if (!slot0Success) {
            response.errorData = slot0Data;
            return response;
        }

        if (slot0Data.length != 128) {
            response.errorData = slot0Data;
            return response;
        }

        (uint160 sqrtPriceX96, int24 tick, uint24 protocolFee, uint24 lpFee) =
            abi.decode(slot0Data, (uint160, int24, uint24, uint24));

        response.sqrtPriceX96 = sqrtPriceX96;
        response.tick = tick;
        response.protocolFee = protocolFee;
        response.lpFee = lpFee;

        (bool liquiditySuccess, bytes memory liquidityData) =
            INFINITY_CL_POOL_MANAGER.staticcall(abi.encodeCall(IInfinityClPoolManager.getLiquidity, (request.poolId)));
        if (!liquiditySuccess) {
            response.errorData = liquidityData;
            return response;
        }

        if (liquidityData.length != 32) {
            response.errorData = liquidityData;
            return response;
        }

        uint128 liquidity = abi.decode(liquidityData, (uint128));
        response.success = true;
        response.sqrtPriceX96 = sqrtPriceX96;
        response.tick = tick;
        response.protocolFee = protocolFee;
        response.lpFee = lpFee;
        response.liquidity = liquidity;
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
            uint32 feeProtocol,
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
