/*
 * gemm_tiled.cu
 *
 * Shared-memory tiled GEMM kernel with TILE_SIZE = 8.
 *
 * Computes: C = alpha * A * B + beta * C
 *   A : M x K
 *   B : K x N
 *   C : M x N
 *
 * How it works:
 *   Each 8x8 thread block cooperatively loads one 8x8 tile of A and one 8x8
 *   tile of B into shared memory, multiplies the tiles, accumulates the
 *   partial dot-products, then advances to the next tile pair across the K
 *   dimension.  This reuses each loaded value TILE_SIZE times, cutting global
 *   memory traffic by ~TILE_SIZE compared to the naive kernel.
 *
 * Compile:
 *   nvcc -O2 -o gemm_tiled gemm_tiled.cu
 *
 * Run:
 *   ./gemm_tiled [M] [N] [K]   (defaults: 512 512 512)
 */

#include <cuda_runtime.h>
#include <stdio.h>
#include <stdlib.h>

#define TILE_SIZE 8

#define CUDA_CHECK(call)                                                        \
    do {                                                                        \
        cudaError_t err = (call);                                               \
        if (err != cudaSuccess) {                                               \
            fprintf(stderr, "CUDA error at %s:%d  %s\n",                       \
                    __FILE__, __LINE__, cudaGetErrorString(err));               \
            exit(EXIT_FAILURE);                                                 \
        }                                                                       \
    } while (0)

/* -------------------------------------------------------------------------- */
/* Kernel                                                                      */
/* -------------------------------------------------------------------------- */

__global__ void gemm_tiled_kernel(
    const float* __restrict__ A,   // [M x K]  row-major
    const float* __restrict__ B,   // [K x N]  row-major
    float*       __restrict__ C,   // [M x N]  row-major
    int M, int N, int K,
    float alpha, float beta)
{
    /* Shared-memory tiles (one tile of A, one tile of B) */
    __shared__ float sA[TILE_SIZE][TILE_SIZE];
    __shared__ float sB[TILE_SIZE][TILE_SIZE];

    int tx = threadIdx.x;   // 0 .. TILE_SIZE-1  (column within tile)
    int ty = threadIdx.y;   // 0 .. TILE_SIZE-1  (row within tile)

    /* Global output element this thread is responsible for */
    int row = blockIdx.y * TILE_SIZE + ty;   // 0 .. M-1
    int col = blockIdx.x * TILE_SIZE + tx;   // 0 .. N-1

    float acc = 0.0f;

    /* Number of full+partial tiles needed along K */
    int numTiles = (K + TILE_SIZE - 1) / TILE_SIZE;

    for (int t = 0; t < numTiles; ++t) {
        /* Column of A / Row of B for this tile */
        int aCol = t * TILE_SIZE + tx;
        int bRow = t * TILE_SIZE + ty;

        /* Collaborative load of A tile: each thread loads one element */
        sA[ty][tx] = (row < M && aCol < K) ? A[row * K + aCol] : 0.0f;

        /* Collaborative load of B tile */
        sB[ty][tx] = (bRow < K && col < N) ? B[bRow * N + col] : 0.0f;

        /* All threads in the block must have finished loading before any
           thread starts reading the shared tiles */
        __syncthreads();

        /* Multiply the two tiles together */
        #pragma unroll
        for (int k = 0; k < TILE_SIZE; ++k) {
            acc += sA[ty][k] * sB[k][tx];
        }

        /* All threads must finish reading before the next iteration
           overwrites the shared-memory tiles */
        __syncthreads();
    }

    /* Write result (guard for non-multiple matrix dimensions) */
    if (row < M && col < N) {
        C[row * N + col] = alpha * acc + beta * C[row * N + col];
    }
}

/* -------------------------------------------------------------------------- */
/* Host utilities                                                              */
/* -------------------------------------------------------------------------- */

static void fill_random(float* buf, int n)
{
    for (int i = 0; i < n; ++i)
        buf[i] = (float)rand() / RAND_MAX;
}

static double max_abs_diff(const float* a, const float* b, int n)
{
    double d = 0.0;
    for (int i = 0; i < n; ++i)
        d = fmax(d, fabs((double)a[i] - (double)b[i]));
    return d;
}

static void gemm_cpu(
    const float* A, const float* B, float* C,
    int M, int N, int K, float alpha, float beta)
{
    for (int i = 0; i < M; ++i)
        for (int j = 0; j < N; ++j) {
            float acc = 0.f;
            for (int k = 0; k < K; ++k)
                acc += A[i * K + k] * B[k * N + j];
            C[i * N + j] = alpha * acc + beta * C[i * N + j];
        }
}

/* -------------------------------------------------------------------------- */
/* Main                                                                        */
/* -------------------------------------------------------------------------- */

int main(int argc, char** argv)
{
    int M = (argc > 1) ? atoi(argv[1]) : 512;
    int N = (argc > 2) ? atoi(argv[2]) : 512;
    int K = (argc > 3) ? atoi(argv[3]) : 512;

    printf("Tiled GEMM (TILE_SIZE=%d)  M=%d  N=%d  K=%d\n",
           TILE_SIZE, M, N, K);

    float alpha = 1.0f, beta = 0.0f;
    srand(42);

    /* Host allocations */
    size_t bytesA = (size_t)M * K * sizeof(float);
    size_t bytesB = (size_t)K * N * sizeof(float);
    size_t bytesC = (size_t)M * N * sizeof(float);

    float *hA = (float*)malloc(bytesA);
    float *hB = (float*)malloc(bytesB);
    float *hC = (float*)calloc(M * N, sizeof(float));
    float *hC_ref = (float*)calloc(M * N, sizeof(float));

    fill_random(hA, M * K);
    fill_random(hB, K * N);

    /* CPU reference (only for small sizes) */
    int do_verify = (M <= 256 && N <= 256 && K <= 256);
    if (do_verify) {
        gemm_cpu(hA, hB, hC_ref, M, N, K, alpha, beta);
    }

    /* Device allocations */
    float *dA, *dB, *dC;
    CUDA_CHECK(cudaMalloc(&dA, bytesA));
    CUDA_CHECK(cudaMalloc(&dB, bytesB));
    CUDA_CHECK(cudaMalloc(&dC, bytesC));

    CUDA_CHECK(cudaMemcpy(dA, hA, bytesA, cudaMemcpyHostToDevice));
    CUDA_CHECK(cudaMemcpy(dB, hB, bytesB, cudaMemcpyHostToDevice));
    CUDA_CHECK(cudaMemset(dC, 0, bytesC));

    /* Launch config: TILE_SIZE x TILE_SIZE thread blocks */
    dim3 block(TILE_SIZE, TILE_SIZE);
    dim3 grid((N + TILE_SIZE - 1) / TILE_SIZE,
              (M + TILE_SIZE - 1) / TILE_SIZE);

    /* Warm-up */
    gemm_tiled_kernel<<<grid, block>>>(dA, dB, dC, M, N, K, alpha, beta);
    CUDA_CHECK(cudaDeviceSynchronize());

    /* Timed run */
    cudaEvent_t t0, t1;
    CUDA_CHECK(cudaEventCreate(&t0));
    CUDA_CHECK(cudaEventCreate(&t1));

    CUDA_CHECK(cudaMemset(dC, 0, bytesC));
    CUDA_CHECK(cudaEventRecord(t0));
    gemm_tiled_kernel<<<grid, block>>>(dA, dB, dC, M, N, K, alpha, beta);
    CUDA_CHECK(cudaEventRecord(t1));
    CUDA_CHECK(cudaEventSynchronize(t1));

    float ms = 0.f;
    CUDA_CHECK(cudaEventElapsedTime(&ms, t0, t1));

    double gflops = 2.0 * M * N * K / (ms * 1e-3) / 1e9;
    printf("  Time : %.3f ms\n", ms);
    printf("  GFLOPS: %.2f\n", gflops);

    /* Verify */
    if (do_verify) {
        CUDA_CHECK(cudaMemcpy(hC, dC, bytesC, cudaMemcpyDeviceToHost));
        double diff = max_abs_diff(hC, hC_ref, M * N);
        printf("  Max |GPU - CPU| diff: %e  %s\n",
               diff, diff < 1e-3 ? "PASS" : "FAIL");
    } else {
        printf("  (verification skipped for large matrix)\n");
    }

    /* Cleanup */
    CUDA_CHECK(cudaFree(dA));
    CUDA_CHECK(cudaFree(dB));
    CUDA_CHECK(cudaFree(dC));
    free(hA); free(hB); free(hC); free(hC_ref);

    return 0;
}
