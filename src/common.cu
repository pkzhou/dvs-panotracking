// This file is part of dvs-panotracking.
//
// Copyright (C) 2017 Christian Reinbacher <reinbacher at icg dot tugraz dot at>
// Institute for Computer Graphics and Vision, Graz University of Technology
// https://www.tugraz.at/institute/icg/teams/team-pock/
//
// dvs-panotracking is free software: you can redistribute it and/or modify it under the
// terms of the GNU General Public License as published by the Free Software
// Foundation, either version 3 of the License, or any later version.
//
// dvs-panotracking is distributed in the hope that it will be useful, but WITHOUT ANY
// WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
// FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with this program.  If not, see <http://www.gnu.org/licenses/>.

#include "common.h"
#include "common.cuh"
#include "iu/iumath.h"
#include "iu/iucore.h"

inline __device__ float sum(float3 val)
{
    return val.x+val.y+val.z;
}
inline __device__ float sum(float2 val)
{
    return val.x+val.y;
}

inline __device__ float2 abs(float2 val)
{
    return make_float2(abs(val.x),abs(val.y));
}

__global__ void set_events_kernel(iu::ImageGpu_32f_C1::KernelData output, iu::LinearDeviceMemory_32f_C2::KernelData events)
{
    int event_id = blockIdx.x*blockDim.x + threadIdx.x;

    if(event_id<events.numel_) {
        float2 event = events.data_[event_id];
        output(round(event.x),round(event.y)) = 0;
    }
}


__global__ void upsample_kernel(iu::ImageGpu_32f_C1::KernelData output, cudaTextureObject_t tex_input, float scale)
{
    int x = blockIdx.x*blockDim.x + threadIdx.x;
    int y = blockIdx.y*blockDim.y + threadIdx.y;

    if(x<output.width_ && y<output.height_)
    {
        output(x,y) = tex2D<float>(tex_input,x/scale+0.5f,y/scale+0.5f);
    }
}

__global__ void upsample_exp_kernel(iu::ImageGpu_32f_C1::KernelData output, cudaTextureObject_t tex_input, float scale)
{
    int x = blockIdx.x*blockDim.x + threadIdx.x;
    int y = blockIdx.y*blockDim.y + threadIdx.y;

    if(x<output.width_ && y<output.height_)
    {
        output(x,y) = exp(tex2D<float>(tex_input,x/scale+0.5f,y/scale+0.5f));
    }
}
namespace cuda {
inline uint divUp(uint a, uint b) { return (a + b - 1) / b; }

void setEvents(iu::ImageGpu_32f_C1 *output, iu::LinearDeviceMemory_32f_C2 *events_gpu)
{
    int gpu_block_x = GPU_BLOCK_SIZE*GPU_BLOCK_SIZE;
    int gpu_block_y = 1;

    // compute number of Blocks
    int nb_x = divUp(events_gpu->numel(),gpu_block_x);
    int nb_y = 1;

    dim3 dimBlock(gpu_block_x,gpu_block_y);
    dim3 dimGrid(nb_x,nb_y);

    set_events_kernel <<< dimGrid, dimBlock>>>(*output,*events_gpu);
    CudaCheckError();
}

void upsample(iu::ImageGpu_32f_C1 *in, iu::ImageGpu_32f_C1 *out, UpsampleMethod method, bool exponentiate)
{
    int width = out->width();
    int height = out->height();

    int gpu_block_x = GPU_BLOCK_SIZE;
    int gpu_block_y = GPU_BLOCK_SIZE;

    // compute number of Blocks
    int nb_x = iu::divUp(width,gpu_block_x);
    int nb_y = iu::divUp(height,gpu_block_y);

    dim3 dimBlock(gpu_block_x,gpu_block_y);
    dim3 dimGrid(nb_x,nb_y);

    in->prepareTexture(cudaReadModeElementType,method==UPSAMPLE_LINEAR? cudaFilterModeLinear:cudaFilterModePoint,cudaAddressModeClamp);
    if(exponentiate)
        upsample_exp_kernel <<<dimGrid,dimBlock>>>(*out,in->getTexture(),out->width()/in->width());
    else
        upsample_kernel <<<dimGrid,dimBlock>>>(*out,in->getTexture(),out->width()/in->width());
    CudaCheckError();
}

} // namespace cuda
