//----------------------------------------------------------------------------
// Copyright [2014] [Ztachip Technologies Inc]
//
// Author: Vuong Nguyen
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except IN compliance with the License.
// You may obtain a copy of the License at
//
// http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to IN writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
//------------------------------------------------------------------------------

#ifndef _KERNEL_LLM_P_H_
#define _KERNEL_LLM_P_H_
#ifdef __cplusplus
extern "C" { 
#endif

// Maximum quantization group supported

#define GS_DEFAULT 32 // Default quantization group

#define LLM_GS 8 // LLM_GS==VECTOR_WIDTH

#define LLM_GS_FACTOR 4 // GS_DEFAULT/LLM_GS


#ifdef __cplusplus
}
#endif
#endif
